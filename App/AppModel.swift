import Foundation
import CoreGraphics
import Observation
import TrackCore

/// Where the person keeps their training: synced through their Track account, or only on this iPhone. Chosen once on
/// the first screen; local can turn on sync later in Settings.
enum StorageMode: String {
    case sync, local
}

enum AppTab: Hashable, CaseIterable { case home, history, progress, rank }

/// A question before something that can't be taken back, shown in Track's own dialog (as the website's).
struct Confirm: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let label: String
    var destructive = false
    let action: () -> Void
}

/// Something to type in Track's dialog: a split's or workout's name, or the bodyweight.
struct Naming: Identifiable {
    let id = UUID()
    let title: String
    var message = "Give your routine a name that makes sense to you."
    var name = ""
    var label = "Split name"
    var placeholder = "e.g. Upper body"
    var number = false
    let action: String
    let onSave: (String) -> Void
}

/// A short note at the bottom ("Set removed"), with Undo when there's something to bring back.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var undo: (() -> Void)?
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
    /// A problem to show, such as finishing without a logged set: it appears as a toast on whatever screen is in front.
    var message: String? {
        get { nil }
        set { if let newValue { show(newValue) } }
    }
    var confirm: Confirm? { didSet { dialogChanged() } }
    var naming: Naming? { didSet { dialogChanged() } }
    var toast: Toast?
    /// The screens that can show the toast, in the order they came up (see ToastOverlay).
    var toastHosts: [UUID] = []
    var tab = AppTab.home {
        didSet { tabStep = (AppTab.allCases.firstIndex(of: tab) ?? 0) > (AppTab.allCases.firstIndex(of: oldValue) ?? 0) ? 1 : -1 }
    }
    /// Which way the last tab change went (1: to the right), for the page's slide in.
    @ObservationIgnored var tabStep: CGFloat = 1
    /// The tab whose page last came up, so coming back from a split's page doesn't count as switching.
    @ObservationIgnored var arrivedTab = AppTab.home
    var workoutOpen = false
    /// The open workout fully covers the tabs (not sliding in or pulled aside), so they needn't be drawn under it.
    var workoutCovers = false
    var finished: Finished?
    /// The level bar's XP before and after the last finished workout, for its fill on Progress.
    var xpFill: (from: Int, to: Int)?
    /// The finished workout open in its detail sheet.
    var history: Session?

    private let file: TrainingFile?
    @ObservationIgnored private var canSave = true
    /// Saving happens off the main thread, in order, so typing and dragging never wait on the disk.
    @ObservationIgnored private let saver = DispatchQueue(label: "track.save", qos: .userInitiated)
    @ObservationIgnored private var memo: [String: Any] = [:]
    @ObservationIgnored private var memoSessions: [Session] = []
    private static let modeKey = "track.storageMode"

    init(file: TrainingFile? = try? TrainingFile.standard()) {
        self.file = file
        mode = UserDefaults.standard.string(forKey: Self.modeKey).flatMap(StorageMode.init)
        do {
            training = try file?.load() ?? Training()
        } catch {
            training = Training()
            canSave = false
            loadError = "Your saved workouts couldn’t be read, so they were left untouched."
        }
    }

    func choose(_ choice: StorageMode) {
        mode = choice
        UserDefaults.standard.set(choice.rawValue, forKey: Self.modeKey)
    }

    /// Changes the training data, keeps the split in step with the workout, and saves it on this device. A change
    /// that throws is shown and not applied.
    func update(_ change: (inout Training) throws -> Void) {
        var next = training
        do { try change(&next) } catch { message = error.localizedDescription; return }
        next.syncRoutine()
        next.editedAt = nowMillis()
        if next.restUntil != training.restUntil || (next.active == nil) != (training.active == nil) {
            if let until = next.restUntil, until > nowMillis() {
                RestAlert.schedule(at: until)
                RestLive.show(until: until, seconds: max(1, (until - nowMillis()) / 1000), workout: next.active?.name ?? "Track")
            } else {
                RestAlert.cancel()
                if next.active != nil { RestLive.idle() } else { RestLive.end() }
            }
        }
        training = next
        guard canSave, let file else { return }
        saver.async { [weak self] in
            do { try file.save(next) } catch {
                DispatchQueue.main.async { self?.message = "Couldn’t save on this iPhone. Free up some space and try again." }
            }
        }
    }

    /// A figure worked out from the workouts (records, achievements, levels, ranks, streaks), kept until they change,
    /// so typing a set or dragging an exercise doesn't redo them on every screen. The comparison is instant while the
    /// workouts are untouched (the same storage). Keys carry what else a figure depends on, such as the day.
    func derived<T>(_ key: String, _ make: ([Session]) -> T) -> T {
        if memoSessions != training.sessions {
            memo = [:]
            memoSessions = training.sessions
        }
        if let stored = memo[key], let value = stored as? T { return value }
        let value = make(training.sessions)
        memo[key] = value
        return value
    }

    /// Each exercise's past bests for the live record check.
    var bests: RecordBests { derived("bests") { RecordBests($0) } }

    /// Replaces everything with a backup (the website's backup file, or one exported here).
    func restore(_ backup: Training) {
        update { $0 = backup }
        workoutOpen = false
    }

    private func dialogChanged() { DialogWindow.update(open: confirm != nil || naming != nil, typing: naming != nil) }

    func show(_ text: String, undo: (() -> Void)? = nil) { toast = Toast(text: text, undo: undo) }

    // MARK: Workouts

    func start(_ split: Split, carryOver: Bool = true) {
        update { try $0.start(split, carryOver: carryOver) }
        if training.active != nil { workoutOpen = true }
    }

    /// Starts a past workout again with its own numbers.
    func repeatWorkout(_ session: Session) {
        history = nil
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

extension Training {
    /// Like updateActive, for a change that can fail (marking a set done without numbers).
    mutating func updateActiveThrowing(exercise id: String, _ change: (inout Exercise) throws -> Void) throws {
        guard let index = active?.exercises.firstIndex(where: { $0.id == id }) else { return }
        try change(&active!.exercises[index])
    }
}
