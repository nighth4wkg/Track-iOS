import Foundation
import SwiftUI
import Observation
import TrackCore

/// Where the person keeps their training: synced through their Track account, or only on this iPhone. Chosen once on
/// the first screen; local can turn on sync later in Settings.
enum StorageMode: String {
    case sync, local
}

enum AppTab: Hashable, CaseIterable { case home, history, progress, rank }

/// A page opened over a tab, as the PWA's deeper routes: back returns to what was under it.
enum Route: Hashable {
    case split(String), lift(String), session(String), settings
}

/// Something shown in a sheet over the screen (UI/Overlays.swift draws them, newest on top).
struct Presented: Identifiable {
    let id = UUID()
    let view: AnyView
    /// As tall as the screen whatever it holds (the picker, whose list grows and shrinks as you search).
    let tall: Bool
    /// What a tap outside it or a drag down does (usually just closing it).
    let onClose: (() -> Void)?
}

/// A question before something that can't be taken back, shown in Track's own dialog (as the website's).
struct Confirm: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let label: String
    var destructive = false
    let action: () -> Void
}

/// A short note at the bottom ("Set removed"), with Undo when there's something to bring back.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var undo: (() -> Void)?
    /// Something went wrong: a red alert instead of the tick (the PWA's toastError).
    var problem = false
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

/// The just-finished workout's recap, and what it earned beyond the recap's own numbers.
struct Finished: Identifiable {
    let id: String
    let xp: Int
    let level: Int
    let leveledUp: Bool
    /// Muscles that reached a new rank, as "Chest → Strong".
    let rankUps: [String]
}

/// The app's state: the training data (saved to this device after every change), the storage choice, and what's
/// on screen.
@Observable
final class AppModel {
    private(set) var training: Training
    /// nil until the first screen's choice is made.
    private(set) var mode: StorageMode?
    /// Why the saved copy couldn't be read, if it couldn't. The app then starts empty without overwriting it.
    private(set) var loadError: String?
    var confirm: Confirm?
    var toast: Toast?
    var tab = AppTab.home
    /// Pages open over the tab, last on top.
    var pages: [Route] = []
    /// Sheets open, last on top.
    var sheets: [Presented] = []
    var workoutOpen = false
    /// Today, refreshed when Track comes back on a new day, so Home's date, "Done today" and the week move on.
    private(set) var day = dayKey(nowMillis())
    var finished: Finished?

    /// A tab, from the nav pill: whatever was open over the last one closes.
    func go(_ next: AppTab) { tab = next; pages = []; sheets = [] }
    func open(_ route: Route) { pages.append(route) }
    func back() { _ = pages.popLast() }
    /// Shows a sheet; returns its id for closing it.
    @discardableResult func present(_ view: some View, tall: Bool = false, onClose: (() -> Void)? = nil) -> UUID {
        let sheet = Presented(view: AnyView(view), tall: tall, onClose: onClose)
        sheets.append(sheet)
        return sheet.id
    }
    func dismiss(_ id: UUID) { sheets.removeAll { $0.id == id } }
    /// The top sheet closes as a tap outside or a drag down closes it.
    func closeTop() {
        guard let top = sheets.last else { return }
        if let close = top.onClose { close() } else { dismiss(top.id) }
    }

    private let file: TrainingFile?
    @ObservationIgnored private var canSave = true
    /// Saving happens off the main thread, in order, so typing and dragging never wait on the disk.
    @ObservationIgnored private let saver: TrainingSaver?
    @ObservationIgnored private var memo: [String: (stamp: AnyHashable, value: Any)] = [:]
    @ObservationIgnored private var memoSessions: [Session] = []
    private static let modeKey = "track.storageMode"
    /// -dryRun (testing on a phone with real data): changes stay in memory and nothing is saved; the rest alert and
    /// Live Activity still run (they hold no data, so they can be checked).
    static let dryRun = ProcessInfo.processInfo.arguments.contains("-dryRun")

    init(file: TrainingFile? = try? TrainingFile.standard()) {
        self.file = file
        saver = file.map { TrainingSaver(file: $0) }
        mode = UserDefaults.standard.string(forKey: Self.modeKey).flatMap(StorageMode.init)
        do {
            training = try file?.load() ?? Training()
            if file == nil { loadError = "Track can’t save on this iPhone right now, so new workouts won’t be kept." }
        } catch {
            training = Training()
            canSave = false
            loadError = "Your saved workouts couldn’t be read, so they were left untouched. New changes won’t be kept until you restore a backup in Settings → Data."
        }
    }

    /// Back to the first screen; the workouts stay on this iPhone.
    func leaveLocal() {
        mode = nil
        UserDefaults.standard.removeObject(forKey: Self.modeKey)
    }

    func choose(_ choice: StorageMode) {
        mode = choice
        UserDefaults.standard.set(choice.rawValue, forKey: Self.modeKey)
    }

    /// Changes the training data and saves it on this device. A change that throws is shown and not applied.
    /// The rest's alert and Live Activity follow the data when its rest or workout changes.
    private func syncRest(_ old: Training, _ next: Training) {
        guard next.restUntil != old.restUntil || (next.active == nil) != (old.active == nil) else { return }
        if let until = next.restUntil, until > nowMillis() {
            RestAlert.schedule(at: until)
            // The ring's whole is the rest setting, as Track's own ring: after +15s or −15s it keeps its place.
            RestLive.show(until: until, seconds: max(1, next.settings.restSeconds), workout: next.active?.name ?? "Track")
        } else {
            RestAlert.cancel()
            if next.active != nil { RestLive.idle() } else { RestLive.end() }
        }
    }

    func update(_ change: (inout Training) throws -> Void) {
        var next = training
        do { try change(&next) } catch { problem(error.localizedDescription); return }
        next.editedAt = nowMillis()
        syncRest(training, next)
        training = next
        guard canSave, !Self.dryRun, let saver else { return }
        saver.save(next) { [weak self] _ in
            DispatchQueue.main.async { self?.problem("Couldn’t save on this iPhone. Free up some space and try again.") }
        }
    }

    /// A figure worked out from the workouts (records, achievements, levels, ranks, streaks), kept until they change,
    /// so typing a set or dragging an exercise doesn't redo them on every screen. The comparison is instant while the
    /// workouts are untouched (the same storage).
    /// `stamp` is what else it depends on that changes over time (the day, the minute, a search): a new one replaces
    /// the figure kept under `key` rather than adding another, so the store stays one figure per key.
    func derived<T>(_ key: String, at stamp: AnyHashable = 0, _ make: ([Session]) -> T) -> T {
        if memoSessions != training.sessions {
            memo = [:]
            memoSessions = training.sessions
        }
        if let stored = memo[key], stored.stamp == stamp, let value = stored.value as? T { return value }
        let value = make(training.sessions)
        memo[key] = (stamp, value)
        return value
    }

    /// Each exercise's past bests for the live record check.
    var bests: RecordBests { derived("bests") { RecordBests($0) } }

    /// The saved copy that couldn't be read, to export as it is.
    var unreadableFile: URL? { canSave ? nil : file?.url }

    /// Replaces everything with a backup (the website's backup file, or one exported here). An unreadable copy is
    /// moved aside first, so saving can resume without destroying it.
    func restore(_ backup: Training) {
        if !canSave, (try? file?.setAside()) != nil {
            canSave = true
            loadError = nil
        }
        update { $0 = backup }
        workoutOpen = false
    }

    func show(_ text: String, undo: (() -> Void)? = nil) { toast = Toast(text: text, undo: undo) }

    func problem(_ text: String) { toast = Toast(text: text, problem: true) }

    func refreshDay() { if dayKey(nowMillis()) != day { day = dayKey(nowMillis()) } }

    // MARK: Workouts

    func start(_ split: Split, carryOver: Bool = true) {
        update { try $0.start(split, carryOver: carryOver) }
        if training.active != nil { workoutOpen = true }
    }

    /// Starts a past workout again with its own numbers.
    func repeatWorkout(_ session: Session) {
        pages.removeAll { if case .session = $0 { true } else { false } }
        start(Split(id: session.splitId, name: session.name, exercises: session.exercises), carryOver: false)
    }

    /// Logs a set, or un-logs it. Logging starts the rest timer.
    func toggle(set setId: String, in exerciseId: String) {
        update { training in
            var started = false
            try training.updateActiveThrowing(exercise: exerciseId) { exercise in
                guard let index = exercise.sets.firstIndex(where: { $0.id == setId }) else { return }
                exercise.sets[index] = try exercise.sets[index].toggledDone()
                started = exercise.sets[index].done
            }
            if started { training.restUntil = nowMillis() + training.settings.restSeconds * 1000 }
        }
    }
}
