import SwiftUI
import TrackCore

/// One exercise, as the website's card: a header that opens and closes it (swipe the header left to remove the
/// exercise), then its sets and Add set | the sides switch. It stays open until closed by hand or until every set is
/// done; one opened or closed by hand stays that way until its sets change between all done and not. While
/// arranging, every card folds to its header with ↑ ↓.
struct ExerciseCard: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise
    let first: Bool
    let last: Bool
    let bests: RecordBests
    var focus: FocusState<String?>.Binding
    @State private var manual: (open: Bool, finished: Bool)?

    var body: some View {
        let done = exercise.sets.filter(\.done).count
        let finished = !exercise.sets.isEmpty && done == exercise.sets.count
        let arranging = model.arrangingExercises
        let open = !arranging && (manual.map { $0.finished == finished ? $0.open : !finished } ?? !finished)
        VStack(spacing: 8) {
            SwipeToDelete(onDelete: { model.removeExercise(exercise) }) {
                HStack(spacing: 8) {
                    Text(exercise.name).font(.title3.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if arranging {
                        GlassCircleButton(icon: "arrow.up", label: "Move \(exercise.name) up") { move(-1) }.disabled(first).opacity(first ? 0.35 : 1)
                        GlassCircleButton(icon: "arrow.down", label: "Move \(exercise.name) down") { move(1) }.disabled(last).opacity(last ? 0.35 : 1)
                    } else {
                        Chip(text: "\(done)/\(exercise.sets.count)", accent: finished)
                        Image(systemName: "chevron.down").font(.subheadline.weight(.bold)).foregroundStyle(Palette.muted)
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !arranging else { return }
                    withAnimation(.smooth(duration: 0.3)) { manual = (!open, finished) }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(open ? "Open" : "Closed")
            }
            if open {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("SET").frame(width: 28)
                        Text(model.training.settings.unit.rawValue.uppercased()).frame(maxWidth: .infinity)
                        Text("REPS").frame(maxWidth: .infinity)
                        Text("RIR").frame(maxWidth: .infinity)
                        Color.clear.frame(width: 52, height: 1)
                    }
                    .font(.caption2.weight(.bold)).foregroundStyle(Palette.muted)
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        SetRow(exercise: exercise, set: set, number: index + 1, bests: bests,
                               earlier: Array(exercise.sets.prefix(index)), focus: focus)
                            .transition(.opacity)
                    }
                    HStack(spacing: 0) {
                        Button { addSet() } label: { Label("Add set", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44) }
                            .disabled(exercise.sets.count >= 100)
                        Rectangle().fill(Palette.hairline).frame(width: 1, height: 20)
                        Button { model.update { $0.updateActive(exercise: exercise.id) { $0 = $0.togglingSides() } } } label: {
                            Label(sidesLabel, systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    .buttonStyle(PressStyle()).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .glass()
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.smooth(duration: 0.3), value: open)
        .animation(.smooth(duration: 0.25), value: exercise.sets.map(\.id))
        .sensoryFeedback(.selection, trigger: open)
    }

    private var sidesLabel: String {
        switch exercise.startingSide { case nil: "Both sides"; case .left?: "Left / Right"; case .right?: "Right / Left" }
    }

    /// A new empty set, on the other side if the exercise is in sides.
    private func addSet() {
        model.update { $0.updateActive(exercise: exercise.id) { exercise in
            let side = exercise.nextSide
            exercise.sets.append(TrainingSet(side: side))
        } }
    }

    private func move(_ direction: Int) {
        guard let index = model.training.active?.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        withAnimation(.smooth(duration: 0.3)) {
            model.update { training in
                guard let moved = training.active?.exercises.moving(index, by: direction) else { return }
                training.active?.exercises = moved
            }
        }
    }
}
