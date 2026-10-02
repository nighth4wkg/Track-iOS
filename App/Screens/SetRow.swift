import SwiftUI
import TrackCore

/// A set: its number (or side), kg · reps · RIR fields with number keyboards, and the ✓ that logs it. In auto mode
/// (the default, as on the website) changing the numbers logs the set too. Logging taps; un-logging ticks.
struct SetRow: View {
    @Environment(AppModel.self) private var model
    let exerciseId: String
    let set: TrainingSet
    let number: Int
    var focus: FocusState<String?>.Binding
    @State private var weight = ""
    @State private var reps = ""
    @State private var rir = ""

    var body: some View {
        let unit = model.training.settings.unit
        HStack(spacing: 8) {
            Text(set.side.map { $0 == .left ? "L" : "R" } ?? "\(number)")
                .font(.body.weight(.bold)).monospacedDigit()
                .foregroundStyle(set.done ? Palette.accent : Palette.muted)
                .frame(width: 28)
            field($weight, id: "kg", keyboard: .decimalPad, placeholder: "kg")
            field($reps, id: "reps", keyboard: .numberPad, placeholder: "reps")
            field($rir, id: "rir", keyboard: .numberPad, placeholder: "0")
            Button { model.toggle(set: set.id, in: exerciseId) } label: {
                Image(systemName: "checkmark").font(.body.weight(.bold))
                    .foregroundStyle(set.done ? Palette.primaryText : Palette.muted)
                    .frame(width: 48, height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(set.done ? Palette.primary : Palette.control))
                    .glass(radius: 14, fill: .clear, lifted: false)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(set.done ? "Logged. Tap to undo" : "Log set \(number)")
            .sensoryFeedback(trigger: set.done) { _, done in done ? .impact(weight: .medium) : .selection }
        }
        .animation(.smooth(duration: 0.25), value: set.done)
        .onAppear { load(unit) }
        .onChange(of: set) { load(unit) }
        .onChange(of: unit) { load(unit) }
    }

    private func field(_ text: Binding<String>, id: String, keyboard: UIKeyboardType, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.body.weight(.bold)).monospacedDigit()
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.input))
            .focused(focus, equals: "\(set.id).\(id)")
            .onChange(of: text.wrappedValue) { save() }
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
           TrainingSet.wholeNumber(reps) == set.reps,
           TrainingSet.wholeNumber(rir) == set.rir { return }
        let next = set.edited(weight: weight, reps: reps, rir: rir, unit: settings.unit, autoLog: settings.logSets != .manual)
        guard next != set else { return }
        let started = next.done && !set.done
        model.update { training in
            training.updateActive(exercise: exerciseId) { exercise in
                if let index = exercise.sets.firstIndex(where: { $0.id == set.id }) { exercise.sets[index] = next }
            }
            if started { training.restUntil = nowMillis() + training.settings.restSeconds * 1000 }
        }
    }
}

/// The rest timer: floats over the bottom while resting, counting down, with +15s and Skip. At zero it buzzes and
/// slides away.
struct RestCapsule: View {
    @Environment(AppModel.self) private var model
    @State private var finished = 0

    var body: some View {
        let until = model.training.restUntil
        Group {
            if let until, until > nowMillis() {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let left = max(0, Double(until) / 1000 - context.date.timeIntervalSince1970)
                    let total = Double(model.training.settings.restSeconds)
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(Palette.input, lineWidth: 5)
                            Circle().trim(from: 0, to: min(1, left / total)).stroke(Palette.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90)).animation(.linear(duration: 0.5), value: left)
                        }
                        .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(String(format: "%d:%02d", Int(left.rounded(.up)) / 60, Int(left.rounded(.up)) % 60))
                                .font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Palette.text)
                            Text("Rest").font(.caption).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button("+15s") { model.update { $0.restUntil = ($0.restUntil ?? nowMillis()) + 15_000 } }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                        Button("Skip") { model.update { $0.restUntil = nil } }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .glass(radius: 32, fill: .clear)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: until) {
                    let wait = Double(until) / 1000 - Date.now.timeIntervalSince1970
                    try? await Task.sleep(for: .seconds(max(0, wait)))
                    if !Task.isCancelled, model.training.restUntil == until { finished += 1; model.update { $0.restUntil = nil } }
                }
            }
        }
        .animation(.smooth(duration: 0.35), value: until)
        .sensoryFeedback(.success, trigger: finished)
    }
}
