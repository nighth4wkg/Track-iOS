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

/// What the motion check does on the workout screen, whose state is its own.
enum BenchMove: Equatable {
    case card(String), focus(String?), arrange(Bool)
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
    /// The workout just finished or discarded, while its screen is taken away (AppActions.leave).
    var leaving: Session?
    /// The motion check's move on the workout screen (MotionCheck), as a tap there would make it.
    var bench: BenchMove?

    /// A tab, from the nav pill: whatever was open over the last one closes. Not `swapping` (the recap's Continue), the
    /// tab comes back as a page does: shifted in from the left.
    // Written only when they change: any write wakes every view that reads them (a tap on the chosen tab redrew all).
    func go(_ next: AppTab, swapping swaps: Bool = true) {
        if swaps { swapAt = ProcessInfo.processInfo.systemUptime }
        if tab != next { tab = next }
        if !pages.isEmpty { pages = [] }
        if !sheets.isEmpty { sheets = [] }
    }
    /// When go() last ran: a screen shown just after was swapped to (it just shows), not come back to (it shifts in).
    @ObservationIgnored private var swapAt: TimeInterval = 0
    var swapping: Bool { ProcessInfo.processInfo.systemUptime - swapAt < Motion.fast }
    func open(_ route: Route) { pages.append(route) }
    func back() { if !pages.isEmpty { pages.removeLast() } }
    /// Shows a sheet (it closes itself through closeSheet).
    func present(_ view: some View, tall: Bool = false) { sheets.append(Presented(view: AnyView(view), tall: tall)) }
    func dismiss(_ id: UUID) {
        guard let index = sheets.firstIndex(where: { $0.id == id }) else { return }
        sheets.remove(at: index)
        sheetClosedAt = ProcessInfo.processInfo.systemUptime
    }
    /// When a sheet last closed: a question coming up while its dim still fades out takes over that dim (AskLayer).
    @ObservationIgnored private var sheetClosedAt: TimeInterval = 0
    var sheetClosing: Bool { ProcessInfo.processInfo.systemUptime - sheetClosedAt < Motion.travel }

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

    /// The rest's alert and Live Activity follow the data when its rest or workout changes.
    private func syncRest(_ old: Training, _ next: Training) {
        guard !benching, next.restUntil != old.restUntil || (next.active == nil) != (old.active == nil) else { return }
        if let until = next.restUntil, until > nowMillis() {
            RestAlert.schedule(at: until)
            // The ring's whole is the rest setting, as Track's own ring: after +15s or −15s it keeps its place.
            RestLive.show(until: until, seconds: max(1, next.settings.restSeconds), workout: next.active?.name ?? "Track")
        } else {
            RestAlert.cancel()
            if next.active != nil { RestLive.idle() } else { RestLive.end() }
        }
    }

    /// Changes the training data and saves it on this device. A change that throws is shown and not applied. It shows
    /// as a tap's change (Motion.tap: rows glide, new ones are uncovered); `moving` false for one that follows a finger
    /// or the keyboard (an arranged row let go, a set typed), which shows at once as the PWA's do.
    func update(moving: Bool = true, _ change: (inout Training) throws -> Void) {
        var next = training
        do { try change(&next) } catch { problem(error.localizedDescription); return }
        next.editedAt = nowMillis()
        syncRest(training, next)
        if moving { Motion.tap { training = next } } else { training = next }
        guard canSave, !Self.dryRun, !benching, let saver else { return }
        saver.save(next) { [weak self] _ in
            DispatchQueue.main.async { self?.problem("Couldn’t save on this iPhone.") }
        }
    }

    /// A figure worked out from the workouts (records, achievements, levels, ranks, streaks), kept until they change,
    /// so typing a set or dragging an exercise doesn't redo them on every screen. The comparison is instant while the
    /// workouts are untouched (the same storage).
    /// `stamp` is what else it depends on that changes over time (the day, the minute, a search): a new one replaces
    /// the figure kept under `key` rather than adding another, so the store stays one figure per key.
    func derived<T>(_ key: String, at stamp: AnyHashable = 0, _ make: ([Session]) -> T) -> T {
        derived(key, of: training.sessions, at: stamp, make)
    }

    /// The same from the workouts a tab was handed (Shell's TabData: its kept copy while hidden), so working it out
    /// doesn't tie the tab to every change.
    func derived<T>(_ key: String, of sessions: [Session], at stamp: AnyHashable = 0, _ make: ([Session]) -> T) -> T {
        if memoSessions != sessions {
            memo = [:]
            memoSessions = sessions
        }
        if let stored = memo[key], stored.stamp == stamp, let value = stored.value as? T { return value }
        let value = make(sessions)
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

    /// While the motion check runs: the training is a copy, never saved, and the rest alert and Live Activity are left
    /// as they were.
    @ObservationIgnored private(set) var benching = false

    /// Starts the motion check on a copy of the training (saving and the rest's alerts stop) and hands back the real one.
    func beginBench() -> Training {
        benching = true
        return training
    }

    /// Ends it: the real training back as it was, saving on again.
    func endBench(_ kept: Training) {
        training = kept
        benching = false
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
            if started { training.startRest() }
        }
    }
}
