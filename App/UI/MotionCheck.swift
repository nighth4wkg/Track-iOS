import SwiftUI
import QuartzCore
import os
import TrackCore

/// The motion check (Settings → About, hold Version): Track makes its own motions one after another, as the taps that
/// cause them would, and measures each one's late frames at the screen's own rate (60 or 120 Hz). Nothing is attached
/// to the app, so nothing else slows it (a test tool turns on accessibility, which adds to every update). It works on a
/// copy of the training that's never saved (AppModel.beginBench) and puts the real one back after. The results show in
/// a sheet and go to the device log ("Track", "motion"), a line a step. Find causes runs it twice more: every motion
/// with where the main thread's time went from the change until it settled (Sampler, which slows frames a little), then
/// every motion again with each screen empty (no tab, page, sheet or recap content, no cards), so a screen's own build
/// shows against what's around it; iOS's keyboard is also timed on a plain field. The results share as text: no
/// cable is needed.
@MainActor
final class MotionCheck {
    private(set) static var running = false
    /// -dryRun -motionCheck: the check runs by itself after launch, so it's measured with no test tool ever attached.
    static let onLaunch = AppModel.dryRun && ProcessInfo.processInfo.arguments.contains("-motionCheck")
    private static let log = Logger(subsystem: "Track", category: "motion")
    private let model: AppModel
    private let meter = Meter()
    private let causes: Bool
    /// Added to each motion's name (", empty" in the empty pass).
    private var suffix = ""
    private var rows: [MotionRow] = []
    /// The training as the check began: every run opens the same split, past workout and lift (each run adds a workout).
    private var base: Training?
    /// ms from the process starting to the first screen, at this launch (TrackApp).
    static var launch: Int?
    /// The plain check runs every motion this many times and keeps the middle run: one run's numbers vary.
    private static let runs = 3

    private init(_ model: AppModel, causes: Bool) { (self.model, self.causes) = (model, causes) }

    static func run(_ model: AppModel, causes: Bool = false) {
        guard !running else { return }
        running = true
        let (tab, pages) = (model.tab, model.pages)
        if causes { Sampler.install(always: true) }
        Task { @MainActor in
            let check = MotionCheck(model, causes: causes)
            let kept = model.beginBench()
            if !causes {
                var passes: [[MotionRow]] = []
                for _ in 0..<runs {
                    check.rows = []
                    await check.all()
                    check.reset()
                    passes.append(check.rows)
                }
                check.rows = middle(passes)
            } else {
                await check.all()
                check.reset()
                await check.plainKeyboard()
                check.suffix = ", empty"
                AB.emptyScreens = true
                // Each tab kept from the first pass takes its empty page now, unmeasured: else its empty run timed the
                // full page being taken down (build 117's Progress, empty, still sampled its rows).
                for tab in AppTab.allCases {
                    model.go(tab)
                    await Self.pause(Motion.travel)
                }
                await check.all()
                AB.emptyScreens = false
                Sampler.uninstall()
                Sampler.found = [:]
            }
            check.meter.stop()
            check.reset()
            model.endBench(kept)
            model.tab = tab; model.pages = pages
            running = false
            let rate = keyWindow?.screen.maximumFramesPerSecond ?? 60
            log.log("motion done: \(check.rows.count) steps at \(rate) Hz")
            model.present(MotionResults(rows: check.rows, rate: rate, causes: causes), tall: true)
        }
    }

    /// Each motion's middle run by its worst late frame, with every run's worst (motions in the order first seen).
    private static func middle(_ passes: [[MotionRow]]) -> [MotionRow] {
        var names: [String] = []
        for row in passes.joined() where !names.contains(row.name) { names.append(row.name) }
        return names.compactMap { name in
            let runs = passes.compactMap { $0.first { $0.name == name } }
            let worst = { (row: MotionRow) in row.late.max() ?? 0 }
            guard var row = runs.sorted(by: { worst($0) < worst($1) }).dropFirst(runs.count / 2).first else { return nil }
            row.runs = runs.map(worst)
            return row
        }
    }

    /// Nothing over the pages, no workout shown.
    private func reset() {
        model.bench = nil; model.confirm = nil; model.toast = nil; model.finished = nil
        model.workoutOpen = false; model.sheets = []
    }

    /// iOS's keyboard on a plain field with the set fields' keys, out of sight: what showing it costs without Track's.
    private func plainKeyboard() async {
        guard let window = keyWindow else { return }
        let field = UITextField(frame: CGRect(x: 0, y: -Size.control, width: Size.control, height: Size.control))
        field.keyboardType = .decimalPad
        window.addSubview(field)
        await step("Keyboard up, plain field", settle: 1.2) { field.becomeFirstResponder() }
        await step("Keyboard down, plain field", settle: 1.2) { field.resignFirstResponder() }
        field.removeFromSuperview()
    }

    /// One motion: what was late from the change until it settled.
    private func step(_ title: String, settle: Double = 1, _ change: () -> Void) async {
        let name = title + suffix
        await Self.pause(0.3)
        _ = meter.take()
        _ = Sampler.takeMarks()
        // Finding causes (or -probe): where the main thread's time went, the whole time it's watched.
        Sampler.begin("motion \(name)", for: causes ? settle : Self.sampled)
        Self.log.log("start \(name, privacy: .public)") // when the change happened, for lining up a screen recording
        let start = CACurrentMediaTime()
        meter.since = start
        change()
        await Self.pause(settle)
        let frames = meter.take()
        let late = frames.filter(\.moving).map(\.late), after = frames.filter { !$0.moving }.map(\.late)
        // When each late frame and each note came, from the change (ms): which work landed in which frame.
        let since = { (t: CFTimeInterval) in Int(((t - start) * 1000).rounded()) }
        let lates: [(Int, String)] = frames.map { (since($0.at), $0.moving ? "late \($0.late)" : "late \($0.late) settled") }
        let notes: [(Int, String)] = Sampler.takeMarks().map { (since($0.at), $0.text) }
        let timeline = (lates + notes)
            .sorted { $0.0 < $1.0 }.map { "\($0.0) \($0.1)" }
        // The sampler's report comes in once its window has closed, a moment after.
        if causes { await Self.pause(Self.reported) }
        rows.append(MotionRow(name: name, late: late, after: after, found: Sampler.found.removeValue(forKey: "motion \(name)"), timeline: causes ? timeline : []))
        Self.log.log("motion \(name, privacy: .public): \(late.map { "\($0)" }.joined(separator: " "), privacy: .public)")
    }

    private func sheet(_ name: String, _ open: () -> Void) async {
        await step("\(name) opens", open)
        await step("\(name) closes") { if let id = model.sheets.last?.id { model.dismiss(id) } }
    }

    /// The first frames, where the late ones are (with -probe).
    private static let sampled = 0.25
    /// How long the sampler takes to report a window.
    private static let reported = 0.25

    private static func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    private func all() async {
        model.workoutOpen = false
        let training = base ?? model.training
        base = training
        let tabs: [(String, AppTab)] = [("History", .history), ("Progress", .progress), ("Rank", .rank), ("Home", .home)]
        for (name, tab) in tabs {
            await step("Tab \(name)") { model.go(tab) }
        }
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
        let settings = training.settings
        await sheet("Rest timer list") { model.present(RestList()) }
        await sheet("Custom rest") { model.present(CustomRest(seconds: settings.restSeconds)) }
        await sheet("Motion list") { model.present(MotionList()) }
        await sheet("Privacy") { model.present(PrivacyPage()) }
        await sheet("Badges") { model.present(QuestList(), tall: true) }
        await sheet("Level help") { model.present(XpHelp()) }
        await sheet("Date picker") { model.present(DateSheet(label: "Date", key: .constant(dayKey(nowMillis())), range: Date.distantPast...Date())) }
        if let counted = training.sessions.countedNames().first { await sheet("Counts for") { model.present(CountsFor(row: counted)) } }
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
        // The page by finger: down (header away, the jump key up), the key back to the set, down again, back to the top.
        await step("Scroll down", settle: 1.5) { model.bench = .scroll(down: true) }
        await step("Jump key", settle: 1.5) { model.bench = .jump }
        await step("Scroll down again", settle: 1.5) { model.bench = .scroll(down: true) }
        await step("Scroll to top", settle: 1.5) { model.bench = .scroll(down: false) }

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
        await sheet("Rename workout") { model.present(RenameWorkout(name: model.training.active?.name ?? "")) }
        // A card's last set done: its ✓, a beat, then the next card opens and the page glides to it.
        if cards.count > 1, let last = model.training.active?.exercises.first?.sets.last(where: { !$0.done }) {
            model.update(moving: false) { training in
                training.updateActive(exercise: first) { exercise in
                    Self.fill(&exercise, only: nil)
                    if let index = exercise.sets.firstIndex(where: { $0.id == last.id }) { exercise.sets[index].done = false }
                }
            }
            await Self.pause(0.7)
            await step("Card's last set done (next opens)", settle: 2) { model.toggle(set: last.id, in: first) }
        }
        await sheet("Exercise options") { model.present(ExerciseOptions(exerciseId: first)) }
        await sheet("Workout options") { model.present(WorkoutOptions(arrange: {})) }
        if cards.count > 1, let last = model.training.active?.exercises.last {
            await step("Arrange exercises") { model.bench = .arrange(true) }
            await step("Arrange: a card moved") {
                model.update(moving: false) { training in
                    guard let moved = training.active?.exercises.moved(0, to: 1) else { return }
                    training.active?.exercises = moved
                }
            }
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
    /// Late frames once nothing moved any more (work after the motion): not seen, but the main thread was busy.
    var after: [Int] = []
    /// The plain check runs every motion three times: each run's worst late frame (0 smooth); this row is the middle run.
    var runs: [Int] = []
    /// Finding causes: where the main thread's time went.
    var found: Sampler.Found?
    /// Finding causes: each late frame and note, ms from the change.
    var timeline: [String] = []
    var summary: String { late.isEmpty ? "Smooth" : "\(late.count) late, worst \(late.max() ?? 0) ms" }
    /// Under the motion, in small type: each run's worst, late frames after it settled, the busy time and its libraries.
    var cause: String? {
        var parts: [String] = []
        if runs.count > 1 { parts.append("Runs \(Self.numbers(runs, " / ")) ms") }
        if !after.isEmpty { parts.append("\(after.count) late after it settled") }
        if let found {
            let libraries: String = Self.list(found.libraries.prefix(Self.shown), ", ")
            parts.append(found.libraries.isEmpty ? "Busy \(found.busy) ms" : "Busy \(found.busy) ms: \(libraries)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func numbers(_ values: [Int], _ separator: String) -> String {
        values.map { String($0) }.joined(separator: separator)
    }
    private static let shown = 3

    /// Everything, for sharing.
    var text: String {
        var head: String = late.isEmpty ? "\(name): smooth" : "\(name): \(Self.numbers(late, " ")) ms late"
        if runs.count > 1 { head += ", runs' worst \(Self.numbers(runs, "/"))" }
        if !after.isEmpty { head += ", after it settled \(Self.numbers(after, " ")) ms" }
        var lines = [head]
        if let found {
            lines.append("  busy \(found.busy) ms")
            for (title, list) in [("by library", found.libraries), ("Track's own", found.ours), ("innermost", found.leaves)] where !list.isEmpty {
                lines.append("  \(title): " + Self.list(list[...], "; "))
            }
        }
        if !timeline.isEmpty { lines.append("  timeline: " + timeline.joined(separator: "; ")) }
        return lines.joined(separator: "\n")
    }

    private static func list(_ items: ArraySlice<(String, Int)>, _ separator: String) -> String {
        items.map { "\($0.0) \($0.1)" }.joined(separator: separator)
    }
}

/// Late frames as they happen: each refresh that came more than half a frame after its time.
@MainActor
private final class Meter: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    /// Each late frame: ms past its time, when it came, and whether something was still moving (seen) or not.
    private var late: [(late: Int, at: CFTimeInterval, moving: Bool)] = []
    /// When the motion's change was made.
    var since: CFTimeInterval = 0

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
        if last > 0, gap > slot * 1.5 { late.append((Int(((gap - slot) * 1000).rounded()), link.timestamp, link.timestamp - since < Motion.travel * 1.5 || Self.animating())) }
    }

    /// A Core Animation move still running in any of the app's windows (looked at only when a frame was late). SwiftUI's
    /// own moves don't show here: the motion's first Motion.travel × 1.5 counts as moving whatever runs.
    private static func animating() -> Bool {
        func moving(_ layer: CALayer) -> Bool { layer.animationKeys()?.isEmpty == false || (layer.sublayers ?? []).contains(where: moving) }
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).contains { moving($0.layer) }
    }

    func take() -> [(late: Int, at: CFTimeInterval, moving: Bool)] {
        defer { late = [] }
        return late
    }

    /// The link holds the meter until stopped.
    func stop() { link?.invalidate() }
}

/// The motion check's results: every motion, smooth or how late its frames were.
struct MotionResults: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeSheet) private var close
    let rows: [MotionRow]
    let rate: Int
    let causes: Bool

    var body: some View {
        let late = rows.filter { !$0.late.isEmpty }.count
        SheetFrame(title: "Motion check", subtitle: "\(rows.count) motions at \(rate) Hz" + dot + (late == 0 ? "all smooth" : "\(late) with late frames")) {
            if causes {
                Text("Finding causes slows frames a little: compare a motion with its empty one, not with a plain check.")
                    .type(.t14).foregroundStyle(Palette.muted).padding(.top, Space.s3)
            }
            RowCard {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 0) {
                        Row(title: row.name, value: row.summary, color: row.late.isEmpty ? Palette.muted : Palette.danger)
                        if let cause = row.cause {
                            Text(cause).type(.t12).foregroundStyle(Palette.muted)
                                .padding([.horizontal, .bottom], Space.s4).padding(.top, -Space.s2)
                        }
                    }
                }
            }
            .padding(.top, Space.s3)
            VStack(spacing: Space.s3) {
                ShareLink(item: report) { Text("Share results") }.buttonStyle(PrimaryStyle())
                if !causes {
                    Button("Find causes") {
                        close()
                        MotionCheck.run(model, causes: true)
                    }
                    .buttonStyle(SecondaryStyle())
                }
            }
            .padding(.top, Space.s4)
        }
    }

    /// The results as text, with the phone and build, to send from the share sheet.
    private var report: String {
        var system = utsname()
        uname(&system)
        let device = withUnsafeBytes(of: system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        var head = "Track \(SettingsScreen.version) motion check" + (causes ? ", causes" : "")
            + " · \(device) iOS \(UIDevice.current.systemVersion) · \(rate) Hz"
        if let launch = MotionCheck.launch { head += " · launch \(launch) ms to first screen" }
        return ([head] + rows.map(\.text)).joined(separator: "\n")
    }
}
