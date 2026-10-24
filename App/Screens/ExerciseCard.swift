import SwiftUI
import TrackCore

/// One exercise, as the PWA's card. Closed: its number, name and "1 of 3 sets · last 60×8", tapped to open. Open: its
/// name over its muscle and rest, ⋯ for its options (swipe the name left and ⋯ becomes a red ✕ that removes it, with
/// Undo), the Set · Last · kg · Reps · RIR · Done columns, a row per set and Add set.
struct ExerciseCard: View, Equatable {
    @Environment(AppModel.self) private var model
    let exercise: Exercise
    let number: Int
    let open: Bool
    let unit: TrackCore.Settings.Unit
    let autoLog: Bool
    let bests: RecordBests
    /// This exercise in the split's last workout: the Last column.
    let last: Exercise?
    let restSeconds: Int
    let muscle: String
    var focus: Binding<String?>
    /// The field being typed in, when it's on this card: a card skipped as unchanged doesn't see the focus move, so
    /// this tells it (and its rows) when the keyboard comes or goes here.
    let focusHere: String?
    let onOpen: () -> Void
    let onOptions: () -> Void
    @State private var armed = false

    var body: some View {
        Group {
            if open { card } else { closed }
        }
        .onChange(of: open) { if !open { armed = false } }
    }

    private var closed: some View {
        Button(action: onOpen) {
            HStack(spacing: Space.s3) {
                Text("\(number)").type(.t16).monospacedDigit().foregroundStyle(Palette.text)
                    .frame(width: Size.tile, height: Size.tile).raised(.control, .inner)
                VStack(alignment: .leading, spacing: 0) {
                    Text(exercise.name).type(.t16).foregroundStyle(Palette.text).multilineTextAlignment(.leading)
                    Text(Self.detail(exercise, nil, unit, last: last)).type(.t14).monospacedDigit().foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: IconSize.medium, weight: .semibold)).foregroundStyle(Palette.muted)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .raised()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityValue("Closed")
    }

    private var card: some View {
        let labels = exercise.setLabels
        let next = exercise.sets.firstIndex { !$0.done }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(exercise.name).type(.t20).foregroundStyle(Palette.text)
                    Text("\(muscle) · Rest \(restText(restSeconds))").type(.t14).foregroundStyle(Palette.muted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { if armed { withAnimation(.smooth(duration: Motion.fast)) { armed = false } } }
                ZStack {
                    if armed {
                        RoundButton(icon: "xmark", label: "Remove \(exercise.name)", tint: Palette.danger) { armed = false; model.removeExercise(exercise) }
                            .transition(.opacity)
                    } else {
                        RoundButton(icon: "ellipsis", label: "\(exercise.name) options", action: onOptions).transition(.opacity)
                    }
                }
            }
            .swipeToArm($armed)
            SetColumns {
                Text("Set"); Text("Last"); Text(unit.rawValue); Text("Reps"); Text("RIR"); Text("Done")
            }
            .type(.t12).foregroundStyle(Palette.muted)
            .padding(.top, Space.s4)
            .accessibilityHidden(true)
            VStack(spacing: Space.s2) {
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                    SetRow(exercise: exercise, set: set, label: labels[index], next: index == next, unit: unit, autoLog: autoLog, bests: bests,
                           last: last.flatMap { $0.sets.indices.contains(index) ? $0.sets[index] : nil },
                           focus: focus,
                           focused: focusHere.flatMap { $0.hasPrefix("\(set.id).") ? String($0.dropFirst(set.id.count + 1)) : nil })
                        .id(set.id) // what the keyboard scrolls to (SetKeyboard)
                        .transition(.opacity)
                }
            }
            .padding(.top, Space.s2)
            Button { model.update { $0.updateActive(exercise: exercise.id) { $0 = $0.addingSet() } } } label: { Label("Add set", systemImage: "plus") }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(exercise.sets.count >= Limits.sets)
                .padding(.top, Space.s4)
        }
        .padding(Space.s4)
        .raised()
        .animation(.smooth(duration: Motion.quick), value: exercise.sets.map(\.id))
    }

    /// Saving a set redraws only its card, not every card in the workout (the keyboard focus updates each by itself).
    static func == (a: Self, b: Self) -> Bool {
        a.exercise == b.exercise && a.number == b.number && a.open == b.open && a.unit == b.unit && a.autoLog == b.autoLog
            && a.bests.id == b.bests.id && a.last == b.last && a.restSeconds == b.restSeconds && a.muscle == b.muscle && a.focusHere == b.focusHere
    }

    /// "1 of 3 sets · last 60×8": done of the sets as counted, and last time's first set.
    static func detail(_ exercise: Exercise, _ previous: Session?, _ unit: TrackCore.Settings.Unit, last: Exercise? = nil) -> String {
        let last = last ?? previous?.exercises.first { $0.id == exercise.id || $0.name == exercise.name }
        return "\(exercise.doneCount) of \(count(exercise.setCount, "set")) · last \(lastText(last?.sets.first, unit))"
    }

    /// A set from last time, compact so it fits its column on the smallest phones: "60×8", or "–".
    static func lastText(_ set: TrainingSet?, _ unit: TrackCore.Settings.Unit) -> String {
        guard let set, set.isValid, let kg = set.kg, let reps = set.reps else { return "–" }
        return "\(TrainingSet.display(kg: kg, unit: unit))×\(reps)"
    }
}

/// The set grid's six columns, as the PWA's .sets: each as wide as a cell at most, spread across the card.
struct SetColumns<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: Space.s1) {
            Group(subviews: content) { cells in
                ForEach(cells) { cell in cell.frame(maxWidth: Size.cell).frame(maxWidth: .infinity) }
            }
        }
    }
}
