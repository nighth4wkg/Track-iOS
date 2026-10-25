import SwiftUI
import TrackCore

/// A set (the PWA's row): its number (green on the next to do), last time's numbers, kg · reps · RIR, and ✓. In
/// auto mode, changing a number logs the set. Swipe left and ✓ becomes a red ✕ that deletes it (Undo). A new heaviest
/// set says what it beat under the row.
/// What you type shows at once (✓, errors) and is saved when you pause, leave the row or tap ✓, so typing never waits
/// on the whole workout redrawing.
struct SetRow: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise
    let set: TrainingSet
    /// "1", or "1L" / "1R" for a side.
    let label: String
    /// The first set still to do.
    let next: Bool
    let unit: TrackCore.Settings.Unit
    let autoLog: Bool
    let bests: RecordBests
    /// The same set last time: the Last column.
    let last: TrainingSet?
    var focus: Binding<String?>
    /// The field being typed in when it's in this row ("kg", "reps", "rir"): read instead of the focus, so moving the
    /// keyboard redraws only the rows it leaves and enters.
    let focused: String?
    @State private var weight = ""
    @State private var reps = ""
    @State private var rir = ""
    @State private var armed = false
    /// Auto mode logs the set once a key is pressed in its RIR, even the same number again. Tapping into the RIR, or a
    /// RIR only carried over, doesn't count.
    @State private var rirTyped = false
    @State private var pending: Task<Void, Never>?
    @State private var replacing: String? // the field just tapped: its first keystroke replaces it (key)

    var body: some View {
        let shown = typed
        let error = TrainingSet.inputError(weight: weight, reps: reps, rir: rir, unit: unit)
        let heaviest: Double? = if case .heaviest(let before)? = bests.record(for: exercise.name, shown) { before } else { nil }
        let best = heaviest != nil && shown.done
        let name = set.side.map { "Set \(label), \($0.rawValue) side" } ?? "Set \(label)"
        VStack(alignment: .leading, spacing: Space.s2) {
            SetColumns {
                Text(label).type(.t16).fontWeight(.semibold).monospacedDigit()
                    .foregroundStyle(next ? Palette.accent : Palette.text)
                    .frame(maxWidth: .infinity, minHeight: Size.control).raised(.control, .inner)
                    .accessibilityLabel(name)
                Text(ExerciseCard.lastText(last, unit)).type(.t12).monospacedDigit().foregroundStyle(Palette.muted)
                    .lineLimit(1).minimumScaleFactor(Shrink.figure)
                    .accessibilityLabel("Last time \(ExerciseCard.lastText(last, unit))")
                field(weight, id: "kg", label: "\(unit.rawValue), \(name)", bad: error?.fields.contains("kg") == true)
                field(reps, id: "reps", label: "Reps, \(name)", bad: error?.fields.contains("reps") == true)
                field(rir, id: "rir", label: "Reps in reserve, \(name)", bad: error?.fields.contains("rir") == true)
                check(done: shown.done, name: name)
            }
            if let message = error?.message { Text(message).type(.t12).foregroundStyle(Palette.danger) }
            if let heaviest, best {
                HStack(spacing: Space.s2) {
                    Badge(text: "New best")
                    Text("\(TrainingSet.display(kg: shown.kg ?? 0, unit: unit)) \(unit.rawValue) beats \(TrainingSet.display(kg: heaviest, unit: unit)) \(unit.rawValue)")
                        .type(.t14).foregroundStyle(Palette.muted)
                }
            }
        }
        .swipeToArm($armed)
        .onAppear { load(unit) }
        .onDisappear(perform: flush)
        // Leaving the app saves a number still waiting on its pause.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in if pending != nil { flush() } }
        .onChange(of: set) { load(unit) }.onChange(of: unit) { load(unit) }
        .onChange(of: rir) { if let n = Int(rir), n > Limits.rir { rir = String(Limits.rir) } } // up to Limits.rir
        .onChange(of: focused) { old, now in
            // Leaving the row saves it straight away; tapping a number arms it, so the first keystroke replaces it.
            if old != nil, now == nil { flush() }
            if let now { replacing = now }
        }
        // A key on the workout's one keyboard (SetKeyboard), for the field being typed in here.
        .onReceive(NotificationCenter.default.publisher(for: KeyInput.typed)) { if let focused { key(focused, $0.object as? String) } }
        .sensoryFeedback(.success, trigger: best) { _, now in now }
    }

    /// ✓ (green once done), or the red ✕ while armed.
    private func check(done: Bool, name: String) -> some View {
        Button { armed ? delete() : tapCheck() } label: {
            (armed ? Icon.close : Icon.check).image(IconSize.medium, bold: true)
                .foregroundStyle(armed ? Palette.danger : done ? Palette.onGreen : Palette.muted)
                .frame(maxWidth: .infinity, minHeight: Size.control)
                .raised(done && !armed ? .green : .control, .inner)
        }
        .buttonStyle(CardStyle())
        .accessibilityLabel(armed ? "Delete \(name)" : done ? "\(name) done" : "Mark \(name) done")
        .accessibilityAddTraits(done ? .isSelected : [])
        .accessibilityAction(named: "Delete set") { delete() } // the swipe, for VoiceOver
    }

    /// A number field on the workout's one keyboard, named for VoiceOver as the PWA's: "Reps, Set 1". Its ring: red
    /// out of range, green while typing in it.
    private func field(_ text: String, id: String, label: String, bad: Bool) -> some View {
        Text(text).type(.t16).fontWeight(.semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(Shrink.value)
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity, minHeight: Size.control)
            .sunk(.inner, ring: bad ? Palette.danger : focused == id ? Palette.accent : nil)
            .contentShape(Rectangle())
            .onTapGesture { focus.wrappedValue = "\(set.id).\(id)" }
            .accessibilityLabel(label).accessibilityValue(text)
            .accessibilityAddTraits(focused == id ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { focus.wrappedValue = "\(set.id).\(id)" }
    }
    private func typedInto(_ id: String) {
        if id == "rir" { rirTyped = true }
        pending?.cancel()
        pending = Task { try? await Task.sleep(for: .milliseconds(400)); if !Task.isCancelled { flush() } }
    }
    /// A key typed into a field here: a digit (or, in the weight, the decimal point), or nil for delete. As the
    /// website selects a number on focus, the first key after arriving in a field replaces it (deleting clears it).
    private func key(_ field: String, _ text: String?) {
        let allowed = field == "kg" ? "0123456789.," : "0123456789"
        if let text, text.isEmpty || !text.allSatisfy({ allowed.contains($0) }) { return }
        var value = replacing == field ? "" : field == "kg" ? weight : field == "reps" ? reps : rir
        replacing = nil
        if let text { value += text } else { value = String(value.dropLast()) }
        if field == "kg" { weight = value } else if field == "reps" { reps = value } else { rir = value }
        typedInto(field)
    }
    private func delete() {
        armed = false
        model.removeSet(set.id, in: exercise.id)
    }

    /// Shows the set's numbers, unless they already read the same (so typing "62." isn't rewritten to "62").
    private func load(_ unit: TrackCore.Settings.Unit) {
        let shown = (TrainingSet.display(kg: set.kg, unit: unit), set.reps.map(String.init) ?? "", set.rir.map(String.init) ?? "")
        if TrainingSet.display(kg: TrainingSet.kilograms(from: weight, unit: unit), unit: unit) != shown.0 { weight = shown.0 }
        if TrainingSet.wholeNumber(reps) != set.reps { reps = shown.1 }
        if TrainingSet.wholeNumber(rir) != set.rir { rir = shown.2 }
    }

    /// The set as typed so far. Fields that still read as the set's own numbers (just shown, or carried over from
    /// last time) are not an edit, so suggestions stay unlogged until changed, ticked or their RIR typed.
    private var typed: TrainingSet {
        if !(autoLog && rirTyped), TrainingSet.display(kg: TrainingSet.kilograms(from: weight, unit: unit), unit: unit) == TrainingSet.display(kg: set.kg, unit: unit),
           TrainingSet.wholeNumber(reps) == set.reps, TrainingSet.wholeNumber(rir) == set.rir { return set }
        return set.edited(weight: weight, reps: reps, rir: rir, unit: unit, autoLog: autoLog && rirTyped)
    }

    /// Saves what was typed now (a pause, leaving the row, the ✓, the row going away). Numbers out of range stay as
    /// typed, with their error, and aren't saved: saving would drop them and clear the field.
    private func flush() { pending?.cancel(); pending = nil; if !invalid { save(typed) } }
    private var invalid: Bool { TrainingSet.inputError(weight: weight, reps: reps, rir: rir, unit: unit) != nil }

    /// The ✓ answers what you see: it logs the typed numbers, or un-logs a set that just logged itself (and then
    /// it stays un-logged until its RIR is typed again).
    private func tapCheck() { guard !invalid else { return }; flush(); rirTyped = false; model.toggle(set: set.id, in: exercise.id) } // invalid: its error says why

    private func save(_ next: TrainingSet) {
        guard next != set else { return }
        let started = next.done && !set.done
        model.update { training in
            training.updateActive(exercise: exercise.id) { exercise in
                if let index = exercise.sets.firstIndex(where: { $0.id == set.id }) { exercise.sets[index] = next }
            }
            if started { training.restUntil = nowMillis() + training.settings.restSeconds * 1000 }
        }
    }
}


extension View {
    /// The workout's set numbers typed on one keyboard: an unseen input (KeyInput) stays first responder while any
    /// set is typed in, so Next only moves the highlight. A field taking the keyboard made iOS rebuild it, most of
    /// what each Next cost. The set being typed in is scrolled into view, as iOS does for a field it focuses.
    func setKeyboard(_ focus: Binding<String?>) -> some View { modifier(SetKeyboard(focus: focus)) }
}

private struct SetKeyboard: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var focus: String?

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .background(alignment: .topLeading) {
                    // Only built while typing, so there's no field of its own for VoiceOver or the UI tests (the set's
                    // boxes are) and nothing for iOS to hand the keyboard back to when a sheet closes. The keyboard going
                    // by itself (dragged away, another field taking it) ends the typing.
                    if focus != nil {
                        KeyInput { if focus != nil { focus = nil } }
                            .frame(width: Size.anchor, height: Size.anchor).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .onChange(of: focus) { reveal(proxy) }
                // A question over the workout ends the typing, rather than leaving the keyboard under it.
                .onChange(of: model.confirm != nil) { _, open in if open { focus = nil } }
                // The keyboard coming up (or the bar over it changing) can cover the set.
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { _ in reveal(proxy) }
        }
    }

    /// Scrolls just enough to show the set being typed in, once a card it opens has its height.
    private func reveal(_ proxy: ScrollViewProxy) {
        guard let focus, let dot = focus.lastIndex(of: ".") else { return }
        let set = String(focus[..<dot])
        DispatchQueue.main.async { proxy.scrollTo(set) }
    }
}

/// The unseen input: the system's decimal pad, whose keys go to the set row being typed in (SetRow.key).
struct KeyInput: UIViewRepresentable {
    /// A key: the text added, or nil for delete.
    static let typed = Notification.Name("KeyInput.typed")
    let onEnd: () -> Void

    func makeUIView(context: Context) -> Field { Field() }

    func updateUIView(_ view: Field, context: Context) {
        view.onEnd = onEnd
        guard !view.started else { return }
        view.started = true
        // After the update: taking the keyboard changes the safe area being laid out.
        DispatchQueue.main.async { _ = view.becomeFirstResponder() }
    }

    /// Typing ended: the keyboard goes with the field.
    static func dismantleUIView(_ view: Field, coordinator: ()) {
        view.onEnd = {}
        _ = view.resignFirstResponder()
    }

    final class Field: UIView, UIKeyInput {
        var onEnd: () -> Void = {}
        var started = false
        var keyboardType: UIKeyboardType = .decimalPad
        override var canBecomeFirstResponder: Bool { true }
        var hasText: Bool { true }
        func insertText(_ text: String) { NotificationCenter.default.post(name: KeyInput.typed, object: text) }
        func deleteBackward() { NotificationCenter.default.post(name: KeyInput.typed, object: nil) }
        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { onEnd() }
            return resigned
        }
    }
}


extension TrainingSet {
    /// What's wrong with a set's typed numbers, worded as on the website: every field out of range (each gets a red
    /// edge) and the first one's message (shown under the row).
    static func inputError(weight: String, reps: String, rir: String, unit: TrackCore.Settings.Unit) -> (fields: Set<String>, message: String)? {
        var bad: [(field: String, message: String)] = []
        if !weight.isEmpty, kilograms(from: weight, unit: unit).map({ $0 <= Limits.kg }) != true {
            bad.append(("kg", "Enter a weight from \(Limits.wholeRange(0...Limits.kg, unit))."))
        }
        if !reps.isEmpty, wholeNumber(reps).map({ (1...Limits.reps).contains($0) }) != true {
            bad.append(("reps", "Reps must be a whole number from 1 to \(Limits.grouped(Limits.reps))."))
        }
        if !rir.isEmpty, wholeNumber(rir).map({ (0...Limits.rir).contains($0) }) != true {
            bad.append(("rir", "RIR must be a whole number from 0 to \(Limits.rir)."))
        }
        return bad.first.map { (Set(bad.map(\.field)), $0.message) }
    }
}
