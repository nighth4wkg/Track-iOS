import SwiftUI
import TrackCore

/// A set, as the website's row: its number (or side), kg · reps · RIR, and the ✓. Last time's numbers are suggestions
/// with a faint ✓ ("tap to repeat"); in auto mode, changing a number logs the set. A set that beats every earlier
/// result turns its ✓ into a trophy, glows, and says what it beat. Swipe left to arm a red ✕ that deletes it (Undo).
struct SetRow: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise
    let set: TrainingSet
    let number: Int
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
    /// Auto mode logs the set once its RIR is typed here; a RIR only carried over doesn't count.
    @State private var rirTyped = false

    var body: some View {
        let unit = model.training.settings.unit
        let record = bests.record(for: exercise.name, set, earlierToday: earlier)
        let carried = !set.done && set.kg != nil && set.reps != nil
        let error = inputError(unit)
        VStack(alignment: .leading, spacing: 4) {
            if hint, let record {
                (Text("New best ").bold() + Text(describe(record, unit))).font(.caption).foregroundStyle(Palette.record)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: 8) {
                Text(set.side.map { $0 == .left ? "L" : "R" } ?? "\(number)")
                    .font(.body.weight(.bold)).monospacedDigit()
                    .foregroundStyle(record != nil ? Palette.record : set.done ? Palette.accent : Palette.muted)
                    .frame(width: 28)
                field($weight, id: "kg", keyboard: .decimalPad, placeholder: "—", glow: record != nil)
                field($reps, id: "reps", keyboard: .numberPad, placeholder: "—", glow: record != nil)
                field($rir, id: "rir", keyboard: .numberPad, placeholder: "0", glow: record != nil)
                check(done: set.done, carried: carried, record: record != nil)
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
        .animation(.smooth(duration: 0.25), value: set.done)
        .animation(.smooth(duration: 0.3), value: hint)
        .onAppear { load(unit); celebrated = signature(record) }
        .onChange(of: set) { load(unit) }
        .onChange(of: unit) { load(unit) }
        .onChange(of: signature(record)) { _, now in celebrate(now) }
        .onChange(of: focus.wrappedValue) { _, id in
            // Tapping a number selects it, so typing replaces it (the website's select-on-focus).
            if id?.hasPrefix(set.id) == true {
                DispatchQueue.main.async { UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil) }
            }
        }
        .sensoryFeedback(.success, trigger: burst)
    }

    private func check(done: Bool, carried: Bool, record: Bool) -> some View {
        Button { armed ? delete() : model.toggle(set: set.id, in: exercise.id) } label: {
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

    private func field(_ text: Binding<String>, id: String, keyboard: UIKeyboardType, placeholder: String, glow: Bool) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.body.weight(.bold)).monospacedDigit()
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.input))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.record.opacity(glow ? 0.8 : 0), lineWidth: 1.5))
            .shadow(color: Palette.record.opacity(0.45), radius: glow && hint ? 6 : 0)
            .focused(focus, equals: "\(set.id).\(id)")
            .onChange(of: text.wrappedValue) { save() }
    }

    /// The website's wording for what a best beat.
    private func describe(_ record: LiveRecord, _ unit: TrackCore.Settings.Unit) -> String {
        let w = { (kg: Double) in "\(TrainingSet.display(kg: kg, unit: unit)) \(unit.rawValue)" }
        switch record {
        case .heaviest(let kg): return "Heaviest ever · up from \(w(kg))"
        case .weightForReps(let kg): return "Heaviest for \(set.reps ?? 0) reps · up from \(w(kg))"
        case .repsForWeight(let reps): return "Most reps at \(w(set.kg ?? 0)) · up from \(reps)"
        case .repsAtOrAbove(let reps): return "More reps than any heavier set · was \(reps)"
        }
    }

    private func signature(_ record: LiveRecord?) -> String? {
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

    /// Saves what was typed. Fields that still read as the set's own numbers (just shown, or carried over from last
    /// time) are not an edit, so suggestions stay unlogged until changed or ticked.
    private func save() {
        let settings = model.training.settings
        let unit = settings.unit
        if TrainingSet.display(kg: TrainingSet.kilograms(from: weight, unit: unit), unit: unit) == TrainingSet.display(kg: set.kg, unit: unit),
           TrainingSet.wholeNumber(reps) == set.reps, TrainingSet.wholeNumber(rir) == set.rir { return }
        if focus.wrappedValue == "\(set.id).rir" { rirTyped = true }
        let next = set.edited(weight: weight, reps: reps, rir: rir, unit: unit, autoLog: settings.logSets != .manual && rirTyped)
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
