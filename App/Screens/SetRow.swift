import SwiftUI
import TrackCore

/// A set, as the PWA's row: its number (green on the next to do), last time's numbers, kg · reps · RIR, and ✓. In
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
    @State private var shownError: String? // set inside an animation, so the rows below glide as it opens and closes

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
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityLabel("Last time \(ExerciseCard.lastText(last, unit))")
                field(weight, id: "kg", label: "\(unit.rawValue), \(name)", bad: error?.fields.contains("kg") == true)
                field(reps, id: "reps", label: "Reps, \(name)", bad: error?.fields.contains("reps") == true)
                field(rir, id: "rir", label: "Reps in reserve, \(name)", bad: error?.fields.contains("rir") == true)
                check(done: shown.done, name: name)
            }
            if let shownError { Text(shownError).type(.t12).foregroundStyle(Palette.danger) }
            if let heaviest, best {
                HStack(spacing: Space.s2) {
                    Badge(text: "New best")
                    Text("\(TrainingSet.display(kg: shown.kg ?? 0, unit: unit)) \(unit.rawValue) beats \(TrainingSet.display(kg: heaviest, unit: unit)) \(unit.rawValue)")
                        .type(.t14).foregroundStyle(Palette.muted).lineLimit(1)
                }
                .transition(.opacity.combined(with: .scale(scale: Motion.press)))
            }
        }
        .onChange(of: error?.message) { _, now in withAnimation(.smooth(duration: Motion.standard)) { shownError = now } }
        .swipeToArm($armed)
        .animation(.smooth(duration: Motion.quick), value: shown.done)
        .animation(.smooth(duration: Motion.standard), value: best)
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
            Image(systemName: armed ? "xmark" : "checkmark").font(.system(size: IconSize.medium, weight: .bold))
                .foregroundStyle(armed ? Palette.danger : done ? Palette.primaryText : Palette.muted)
                .frame(maxWidth: .infinity, minHeight: Size.control)
                .raised(done && !armed ? .green : .control, .inner)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(armed ? "Delete \(name)" : done ? "\(name) done" : "Mark \(name) done")
        .accessibilityAddTraits(done ? .isSelected : [])
        .accessibilityAction(named: "Delete set") { delete() } // the swipe, for VoiceOver
    }

    /// A number field on the workout's one keyboard, named for VoiceOver as the PWA's: "Reps, Set 1". Its ring: red
    /// out of range, green while typing in it.
    private func field(_ text: String, id: String, label: String, bad: Bool) -> some View {
        Text(text).type(.t16).fontWeight(.semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
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
        withAnimation(.smooth(duration: Motion.quick)) { model.removeSet(set.id, in: exercise.id) }
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
