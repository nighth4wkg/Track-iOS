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
    /// How far the swipe has turned the ✓ into a red ✕ (0–1), and whether it's armed to delete.
    @State private var arm: CGFloat = 0
    @State private var armed = false
    @State private var deleted = 0

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
            Button { armed ? delete() : model.toggle(set: set.id, in: exerciseId) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(set.done ? Palette.primary : Palette.control)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Palette.danger, Color(hex: 0xBD1616)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .opacity(arm)
                    Image(systemName: "checkmark").font(.body.weight(.bold))
                        .foregroundStyle(set.done ? Palette.primaryText : Palette.muted)
                        .opacity(1 - arm).scaleEffect(1 - 0.4 * arm)
                    Image(systemName: "xmark").font(.body.weight(.bold)).foregroundStyle(.white)
                        .opacity(arm).scaleEffect(0.6 + 0.4 * arm)
                }
                .frame(width: 52, height: 48)
                .glass(radius: 14, fill: .clear, lifted: false)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(armed ? "Delete set \(number)" : set.done ? "Logged. Tap to undo" : "Log set \(number)")
            .accessibilityAction(named: "Delete set") { delete() }
            .sensoryFeedback(trigger: set.done) { _, done in done ? .impact(weight: .medium) : .selection }
            .sensoryFeedback(.impact(weight: .heavy), trigger: armed) { _, now in now }
            .sensoryFeedback(.warning, trigger: deleted)
        }
        .contentShape(Rectangle())
        .gesture(HorizontalPan(onChange: { x in
            arm = max(0, min(1, (armed ? 1 : 0) - x / 72))
        }, onEnd: { x, velocity in
            let arming = abs(velocity) > 300 ? velocity < 0 : arm > 0.5
            withAnimation(.smooth(duration: 0.2)) { arm = arming ? 1 : 0 }
            armed = arming
        }))
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
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.input))
            .focused(focus, equals: "\(set.id).\(id)")
            .onChange(of: text.wrappedValue) { save() }
    }

    private func delete() {
        deleted += 1
        withAnimation(.smooth(duration: 0.25)) {
            model.update { $0.updateActive(exercise: exerciseId) { $0.sets.removeAll { $0.id == set.id } } }
        }
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
