import SwiftUI
import QuartzCore
import os
import TrackCore

/// The motion check (Settings → About, hold Version): Track makes its own motions one after another, as the taps that
/// cause them would, and measures each one's late frames at the screen's own rate (60 or 120 Hz). Nothing is attached
/// to the app, so nothing else slows it (a test tool turns on accessibility, which adds to every update). It works on a
/// copy of the training that's never saved (AppModel.beginBench) and puts the real one back after. The results show in
/// a sheet and go to the device log ("Track", "motion"), a line a step.
@MainActor
final class MotionCheck {
    private(set) static var running = false
    /// -dryRun -motionCheck: the check runs by itself after launch, so it's measured with no test tool ever attached.
    static let onLaunch = AppModel.dryRun && ProcessInfo.processInfo.arguments.contains("-motionCheck")
    private static let log = Logger(subsystem: "Track", category: "motion")
    private let model: AppModel
    private let meter = Meter()
    private var rows: [MotionRow] = []

    private init(_ model: AppModel) { self.model = model }

    static func run(_ model: AppModel) {
        guard !running else { return }
        running = true
        let (tab, pages) = (model.tab, model.pages)
        Task { @MainActor in
            let check = MotionCheck(model)
            let kept = model.beginBench()
            await check.all()
            check.meter.stop()
            model.bench = nil; model.confirm = nil; model.toast = nil; model.finished = nil
            model.workoutOpen = false; model.sheets = []
            model.endBench(kept)
            model.tab = tab; model.pages = pages
            running = false
            let rate = keyWindow?.screen.maximumFramesPerSecond ?? 60
            log.log("motion done: \(check.rows.count) steps at \(rate) Hz")
            model.present(MotionResults(rows: check.rows, rate: rate), tall: true)
        }
    }

    /// One motion: what was late from the change until it settled.
    private func step(_ name: String, settle: Double = 1, _ change: () -> Void) async {
        await Self.pause(0.3)
        _ = meter.take()
        Sampler.begin("motion \(name)", for: Self.sampled) // with -probe: where the main thread's time went
        change()
        await Self.pause(settle)
        let late = meter.take()
        rows.append(MotionRow(name: name, late: late))
        Self.log.log("motion \(name, privacy: .public): \(late.map { "\($0)" }.joined(separator: " "), privacy: .public)")
    }

    private func sheet(_ name: String, _ open: () -> Void) async {
        await step("\(name) opens", open)
        await step("\(name) closes") { if let id = model.sheets.last?.id { model.dismiss(id) } }
    }

    /// The first frames, where the late ones are.
    private static let sampled = 0.25

    private static func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    private func all() async {
        model.workoutOpen = false
        let tabs: [(String, AppTab)] = [("History", .history), ("Progress", .progress), ("Rank", .rank), ("Home", .home)]
        for (name, tab) in tabs {
            await step("Tab \(name)") { model.go(tab) }
        }
        let training = model.training
        await step("Settings page") { model.open(.settings) }
        await step("Settings back") { model.back() }
        if let split = training.splits.first {
            await step("Split page") { model.open(.split(split.id)) }
            await step("Split back") { model.back() }
        }
        if let session = training.sessions.first {
            await step("Past workout page") { model.open(.session(session.id)) }
            await step("Past workout back") { model.back() }
            if let lift = session.exercises.first?.name {
                await step("Lift page") { model.open(.lift(lift)) }
                await step("Lift back") { model.back() }
            }
        }
        await sheet("New split sheet") { model.present(NewSplitSheet()) }
        await sheet("Exercise picker") { model.present(ExercisePicker { _ in }, tall: true) }
        await step("Question opens") { model.confirm = Confirm(title: "Motion check", message: "Nothing changes.", label: "OK") {} }
        await step("Question closes") { model.confirm = nil }
        await step("Toast shows") { model.show("Motion check.") }
        await step("Toast goes") { model.toast = nil }
        await workout()
    }

    private func workout() async {
        if model.training.active == nil {
            guard let split = model.training.splits.first(where: { !$0.exercises.isEmpty }) else { return }
            await step("Start workout", settle: 1.5) { model.start(split) }
        } else {
            await step("Continue workout", settle: 1.5) { model.workoutOpen = true }
        }
        guard let cards = model.training.active?.exercises.map(\.id), let first = cards.first else { return }
        for (index, id) in cards.enumerated().prefix(8) { await step("Open card \(index + 1)") { model.bench = .card(id) } }
        await step("Open card 1 again") { model.bench = .card(first) }

        await step("Add set") { model.update { $0.updateActive(exercise: first) { $0 = $0.addingSet() } } }
        if let set = model.training.active?.exercises.first?.sets.last {
            await step("Remove set (toast)") { model.removeSet(set.id, in: first) }
            await step("Undo remove set") { model.toast?.undo?(); model.toast = nil }
        }
        if let set = model.training.active?.exercises.first?.sets.first(where: { !$0.done }) {
            await step("Keyboard up", settle: 1.2) { model.bench = .focus("\(set.id).kg") }
            await step("Keyboard down", settle: 1.2) { model.bench = .focus(nil) }
            model.update(moving: false) { training in training.updateActive(exercise: first) { exercise in Self.fill(&exercise, only: set.id) } }
            await step("Mark set done (rest starts)", settle: 1.2) { model.toggle(set: set.id, in: first) }
        }
        await step("Rest +15 s") { model.shiftRest(by: 15) }
        await step("Rest −15 s") { model.shiftRest(by: -15) }
        // With no rest running, Skip only puts the Live Activity right, which the check leaves alone.
        if model.training.restUntil != nil { await step("Rest skip") { model.skipRest() } }
        await sheet("Exercise options") { model.present(ExerciseOptions(exerciseId: first)) }
        await sheet("Workout options") { model.present(WorkoutOptions(arrange: {})) }
        if cards.count > 1, let last = model.training.active?.exercises.last {
            await step("Arrange exercises") { model.bench = .arrange(true) }
            await step("Done arranging") { model.bench = .arrange(false) }
            await step("Remove exercise (toast)") { model.removeExercise(last) }
            await step("Undo remove exercise") { model.toast?.undo?(); model.toast = nil }
        }
        await step("Keep for later", settle: 1.2) { model.workoutOpen = false }
        await step("Continue workout again", settle: 1.5) { model.workoutOpen = true }
        model.update(moving: false) { training in
            guard var active = training.active else { return }
            for index in active.exercises.indices { Self.fill(&active.exercises[index], only: nil) }
            training.active = active
        }
        await Self.pause(0.7)
        await step("Finish (recap)", settle: 2) { model.finish() }
        await step("Recap closes", settle: 1.2) { model.finished = nil; model.go(.home, swapping: false) }
    }

    /// Numbers in a set (or every set, done) so it can be marked done; ones already typed stay.
    nonisolated private static func fill(_ exercise: inout Exercise, only id: String?) {
        for index in exercise.sets.indices where id == nil || exercise.sets[index].id == id {
            exercise.sets[index].kg = exercise.sets[index].kg ?? 20
            exercise.sets[index].reps = exercise.sets[index].reps ?? 8
            if id == nil { exercise.sets[index].done = true }
        }
    }
}

/// A motion and its late frames (ms past their time).
struct MotionRow: Identifiable {
    let id = UUID()
    let name: String
    let late: [Int]
    var summary: String { late.isEmpty ? "Smooth" : "\(late.count) late, worst \(late.max() ?? 0) ms" }
}

/// Late frames as they happen: each refresh that came more than half a frame after its time.
@MainActor
private final class Meter: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var late: [Int] = []

    override init() {
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120) // the screen's full rate
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        let gap = link.timestamp - last, slot = link.targetTimestamp - link.timestamp
        if last > 0, gap > slot * 1.5 { late.append(Int(((gap - slot) * 1000).rounded())) }
    }

    func take() -> [Int] {
        defer { late = [] }
        return late
    }

    /// The link holds the meter until stopped.
    func stop() { link?.invalidate() }
}

/// The motion check's results: every motion, smooth or how late its frames were.
struct MotionResults: View {
    let rows: [MotionRow]
    let rate: Int

    var body: some View {
        let late = rows.filter { !$0.late.isEmpty }.count
        SheetFrame(title: "Motion check", subtitle: "\(rows.count) motions at \(rate) Hz" + dot + (late == 0 ? "all smooth" : "\(late) with late frames")) {
            RowCard {
                ForEach(rows) { row in
                    Row(title: row.name, value: row.summary, color: row.late.isEmpty ? Palette.muted : Palette.danger)
                }
            }
            .padding(.top, Space.s3)
        }
    }
}
