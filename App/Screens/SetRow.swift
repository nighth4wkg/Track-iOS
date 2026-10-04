import SwiftUI
import TrackCore

/// A set, as the website's row: its number (or side), kg · reps · RIR, and the ✓. Last time's numbers are suggestions
/// with a faint ✓ ("tap to repeat"); in auto mode, changing a number logs the set. A set that beats every earlier
/// result turns its ✓ into a trophy, glows, and says what it beat. Swipe left to arm a red ✕ that deletes it (Undo).
/// As on the website, what you type shows at once (✓, trophy, errors) and is saved when you pause, leave the row or
/// tap ✓, so typing never waits on the whole workout redrawing.
struct SetRow: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise
    let set: TrainingSet
    let number: Int
    let unit: TrackCore.Settings.Unit
    let autoLog: Bool
    let bests: RecordBests
    let earlier: [TrainingSet]
    var focus: FocusState<String?>.Binding
    @State private var weight = ""
    @State private var reps = ""
    @State private var rir = ""
    @State private var arm: CGFloat = 0
    @State private var armed = false
    @State private var celebrated: String?
    @State private var burst = 0
    @State private var hint = false
    /// Auto mode logs the set once its RIR is typed here, even the same number again; one only carried over doesn't.
    @State private var rirTyped = false
    @State private var pending: Task<Void, Never>?

    var body: some View {
        let shown = typed
        let record = bests.record(for: exercise.name, shown, earlierToday: earlier)
        let carried = !shown.done && shown.kg != nil && shown.reps != nil
        let error = inputError(unit)
        VStack(alignment: .leading, spacing: 4) {
            if hint, let record {
                (Text("New best ").bold() + Text(describe(record, shown))).font(.caption).foregroundStyle(Palette.record)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: 8) {
                Text(set.side.map { $0 == .left ? "L" : "R" } ?? "\(number)")
                    .font(.body.weight(.bold)).monospacedDigit()
                    .foregroundStyle(record != nil ? Palette.record : shown.done ? Palette.accent : Palette.muted)
                    .frame(width: 28)
                field($weight, id: "kg", label: "weight in \(unit.rawValue)", keyboard: .decimalPad, placeholder: "—", glow: record != nil, done: shown.done)
                field($reps, id: "reps", label: "reps", keyboard: .numberPad, placeholder: "—", glow: record != nil, done: shown.done)
                field($rir, id: "rir", label: "RIR", keyboard: .numberPad, placeholder: "0", glow: record != nil, done: shown.done)
                check(done: shown.done, carried: carried, record: record != nil)
            }
            if let error { Text(error).font(.caption).foregroundStyle(Palette.danger) }
        }
        .contentShape(Rectangle())
        .gesture(HorizontalPan(onChange: { x in
            arm = max(0, min(1, (armed ? 1 : 0) - x / 72))
        }, onEnd: { _, velocity in
            let arming = abs(velocity) > 300 ? velocity < 0 : arm > 0.5
            withAnimation(.smooth(duration: 0.2)) { arm = arming ? 1 : 0 }
            armed = arming
        }))
        .animation(.smooth(duration: 0.25), value: shown.done)
        .animation(.smooth(duration: 0.3), value: hint)
        .onAppear { load(unit); celebrated = signature(record, shown) }
        .onDisappear(perform: flush)
        .onChange(of: set) { load(unit) }
        .onChange(of: unit) { load(unit) }
        .onChange(of: signature(record, shown)) { _, now in celebrate(now) }
        .onChange(of: focus.wrappedValue) { old, id in
            // Leaving the row saves it straight away.
            if old?.hasPrefix(set.id) == true, id?.hasPrefix(set.id) != true { flush() }
            // Tapping a number selects it, so typing replaces it (the website's select-on-focus).
            if id?.hasPrefix(set.id) == true {
                DispatchQueue.main.async { UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil) }
            }
        }
        .sensoryFeedback(.success, trigger: burst)
    }

    private func check(done: Bool, carried: Bool, record: Bool) -> some View {
        Button { armed ? delete() : tapCheck() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(record ? Palette.record : done ? Palette.primary : Palette.control)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.danger, Color(hex: 0xBD1616)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .opacity(arm)
                Image(systemName: record ? "trophy.fill" : "checkmark").font(.body.weight(.bold))
                    .foregroundStyle(done ? Palette.primaryText : Palette.muted.opacity(carried ? 0.9 : 0.4))
                    .opacity(1 - arm).scaleEffect((1 - 0.4 * arm) * (hint ? 1.12 : 1))
                Image(systemName: "xmark").font(.body.weight(.bold)).foregroundStyle(.white)
                    .opacity(arm).scaleEffect(0.6 + 0.4 * arm)
            }
            .frame(width: 52, height: 48)
            .glass(radius: 14, fill: .clear, lifted: false)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(armed ? "Delete \(exercise.name) set \(number)"
            : "\(exercise.name) set \(number)\(record ? ", new best" : ""): \(done ? "done. Tap to undo" : carried ? "same as last time. Tap to log" : "mark done")")
        .sensoryFeedback(trigger: done) { _, now in now ? .impact(weight: .medium) : .selection }
        .sensoryFeedback(.impact(weight: .heavy), trigger: armed) { _, now in now }
    }

    /// A number field, named for VoiceOver as the website's: "Bench Press set 1 reps".
    private func field(_ text: Binding<String>, id: String, label: String, keyboard: UIKeyboardType, placeholder: String, glow: Bool, done: Bool) -> some View {
        // Every keystroke counts, even one that types over a number with the same number.
        TextField(placeholder, text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = $0; typedInto(id) }))
            .accessibilityLabel("\(exercise.name) set \(number) \(label)")
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.body.weight(.bold)).monospacedDigit()
            .foregroundStyle(done ? Palette.accent : Palette.text)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.input))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.record.opacity(glow ? 0.8 : 0), lineWidth: 1.5))
            .shadow(color: Palette.record.opacity(0.45), radius: glow && hint ? 6 : 0)
            .focused(focus, equals: "\(set.id).\(id)")
    }

    private func typedInto(_ id: String) {
        if id == "rir" { rirTyped = true }
        pending?.cancel()
        pending = Task { try? await Task.sleep(for: .milliseconds(400)); if !Task.isCancelled { flush() } }
    }

    /// The website's wording for what a best beat.
    private func describe(_ record: LiveRecord, _ set: TrainingSet) -> String {
        let w = { (kg: Double) in "\(TrainingSet.display(kg: kg, unit: unit)) \(unit.rawValue)" }
        switch record {
        case .heaviest(let kg): return "Heaviest ever · up from \(w(kg))"
        case .weightForReps(let kg): return "Heaviest for \(set.reps ?? 0) reps · up from \(w(kg))"
        case .repsForWeight(let reps): return "Most reps at \(w(set.kg ?? 0)) · up from \(reps)"
        case .repsAtOrAbove(let reps): return "More reps than any heavier set · was \(reps)"
        }
    }

    private func signature(_ record: LiveRecord?, _ set: TrainingSet) -> String? {
        record.map { "\($0):\(set.kg ?? 0):\(set.reps ?? 0)" }
    }

    /// A set that becomes a best celebrates at once; a best that improves celebrates again. One already there when the
    /// row appeared stays calm.
    private func celebrate(_ now: String?) {
        guard let now, now != celebrated else { return }
        celebrated = now
        burst += 1
        withAnimation(.smooth(duration: 0.3)) { hint = true }
        let mine = burst
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { if burst == mine { withAnimation(.smooth) { hint = false } } }
    }

    private func inputError(_ unit: TrackCore.Settings.Unit) -> String? {
        if !weight.isEmpty, TrainingSet.kilograms(from: weight, unit: unit).map({ $0 <= 5000 }) != true { return "Enter a weight from 0 to 5,000 kg." }
        if !reps.isEmpty, TrainingSet.wholeNumber(reps).map({ (1...1000).contains($0) }) != true { return "Reps must be a whole number from 1 to 1,000." }
        if !rir.isEmpty, TrainingSet.wholeNumber(rir).map({ (0...10).contains($0) }) != true { return "RIR must be a whole number from 0 to 10." }
        return nil
    }

    private func delete() {
        withAnimation(.smooth(duration: 0.2)) { arm = 0 }
        armed = false
        withAnimation(.smooth(duration: 0.25)) { model.removeSet(set.id, in: exercise.id) }
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

    /// Saves what was typed now (a pause, leaving the row, the ✓, the row going away).
    private func flush() { pending?.cancel(); pending = nil; save(typed) }

    /// The ✓ answers what you see: it logs the typed numbers, or un-logs a set that just logged itself (and then
    /// it stays un-logged until its RIR is typed again).
    private func tapCheck() { flush(); rirTyped = false; model.toggle(set: set.id, in: exercise.id) }

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
