import SwiftUI
import TrackCore

/// One exercise, as the website's card: a header that opens and closes it (swipe the header left to remove the
/// exercise), then its sets and Add set | the sides switch. It stays open until closed by hand or until every set is
/// done; one opened or closed by hand stays that way until its sets change between all done and not. Hold the
/// name and drag to move the exercise (see ReorderDrop); every card stays folded while one is held.
struct ExerciseCard: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise
    let box: ReorderBox
    let bests: RecordBests
    var focus: FocusState<String?>.Binding
    @Binding var dragging: String?
    @State private var manual: (open: Bool, finished: Bool)?
    /// The sets' height. A closed card keeps its sets, clipped to nothing, so opening many at once (after a drag)
    /// only animates heights instead of building every row in one frame.
    @State private var setsHeight: CGFloat?

    var body: some View {
        let done = exercise.sets.filter(\.done).count
        let finished = !exercise.sets.isEmpty && done == exercise.sets.count
        let open = dragging == nil && (manual.map { $0.finished == finished ? $0.open : !finished } ?? !finished)
        VStack(spacing: 0) {
            SwipeToDelete(onDelete: { model.removeExercise(exercise) }) {
                HStack(spacing: 8) {
                    Text(exercise.name).font(.title3.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Chip(text: "\(done)/\(exercise.sets.count)", accent: finished)
                    Image(systemName: "chevron.down").font(.subheadline.weight(.bold)).foregroundStyle(Palette.muted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.smooth(duration: 0.3)) { manual = (!open, finished) } }
                .reorderHandle(exercise.id, dragging: $dragging) {
                    Text(exercise.name).font(.title3.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                        .padding(.horizontal, 20).frame(minWidth: 220, minHeight: 60, alignment: .leading).glass(fill: Palette.dialog)
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(open ? "Open" : "Closed")
            }
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
            .padding(.top, 8)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { setsHeight = $0 }
            .frame(height: open ? setsHeight : 0, alignment: .top)
            .clipped()
            .opacity(open ? 1 : 0)
            .allowsHitTesting(open)
            .accessibilityHidden(!open)
        }
        .onChange(of: focus.wrappedValue) { _, id in
            // The keyboard's Next reaching a closed card opens it.
            if let id, !open, exercise.sets.contains(where: { id.hasPrefix($0.id) }) {
                withAnimation(.smooth(duration: 0.3)) { manual = (true, finished) }
            }
        }
        .padding(16)
        .glass(lifted: false)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(dragging == exercise.id ? 0.4 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { box.frames[exercise.id] = $0 }
        .animation(.smooth(duration: 0.3), value: open)
        .animation(.smooth(duration: 0.25), value: exercise.sets.map(\.id))
        .sensoryFeedback(.selection, trigger: open)
    }

    private var sidesLabel: String {
        switch exercise.startingSide { case nil: "Both sides"; case .left?: "Left / Right"; case .right?: "Right / Left" }
    }

    /// A new set with the last one's weight and reps to start from (RIR blank), on the other side if in sides.
    private func addSet() {
        model.update { $0.updateActive(exercise: exercise.id) { exercise in exercise.sets.append(exercise.nextSet) } }
    }
}
