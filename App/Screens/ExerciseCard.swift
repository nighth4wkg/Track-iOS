import SwiftUI
import TrackCore

/// One exercise, as the website's card: a header that opens and closes it (swipe the header left to remove the
/// exercise), then its sets and Add set | the sides switch. As on the website, it stays open until closed by hand or
/// until every set is done (taking the keyboard with it); one opened or closed by hand stays that way until its sets
/// change between all done and not. Hold the
/// name and drag to move the exercise (see ReorderList).
struct ExerciseCard: View, Equatable {
    @Environment(AppModel.self) private var model
    let exercise: Exercise
    let unit: TrackCore.Settings.Unit
    let autoLog: Bool
    let box: ReorderBox
    let bests: RecordBests
    var focus: FocusState<String?>.Binding
    /// The field being typed in, when it's on this card: a card skipped as unchanged doesn't see the focus move, so
    /// this tells it (and its rows) when the keyboard comes or goes here.
    let focusHere: String?
    @Binding var dragging: String?
    @State private var manual: (open: Bool, finished: Bool)?
    /// The sets' height. A closed card keeps its sets, clipped to nothing, so opening many at once (after a drag)
    /// only animates heights instead of building every row in one frame.
    @State private var setsHeight: CGFloat?
    /// A set's new best, over the header for a moment with room around it (each one a new id, so a better one
    /// restarts it). Drawn on the card, sized to the header, since the header's swipe clips anything larger.
    @State private var best: (text: String, id: Int)?
    @State private var headerHeight: CGFloat = 44

    var body: some View {
        let done = exercise.sets.filter(\.done).count
        let finished = !exercise.sets.isEmpty && done == exercise.sets.count
        let open = (manual.map { $0.finished == finished ? $0.open : !finished } ?? !finished)
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
                .onTapGesture { withAnimation(.smooth(duration: Motion.standard)) { manual = (!open, finished) } }
                .reorderHandle(exercise.id, box: box, dragging: $dragging) {
                    Text(exercise.name).font(.title3.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                        .padding(.horizontal, 20).frame(minWidth: 220, minHeight: 60, alignment: .leading).glass(fill: Palette.dialog)
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(open ? "Open" : "Closed")
                // Moving without the drag, for VoiceOver and Switch Control.
                .accessibilityAction(named: "Move up") { move(by: -1) }
                .accessibilityAction(named: "Move down") { move(by: 1) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("SET").frame(width: 28)
                        Text(unit.rawValue.uppercased()).frame(maxWidth: .infinity)
                        Text("REPS").frame(maxWidth: .infinity)
                        Text("RIR").frame(maxWidth: .infinity)
                        Color.clear.frame(width: 52, height: 1)
                    }
                    .font(.caption2.weight(.bold)).foregroundStyle(Palette.muted)
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        SetRow(exercise: exercise, set: set, number: index + 1, unit: unit, autoLog: autoLog, bests: bests,
                               earlier: Array(exercise.sets.prefix(index)), focus: focus,
                               onRecord: { best = ($0, (best?.id ?? 0) + 1) })
                            .transition(.opacity)
                    }
                    HStack(spacing: 0) {
                        Button { addSet() } label: { Label("Add set", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44) }
                            .disabled(exercise.sets.count >= Limits.sets)
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
                withAnimation(.smooth(duration: Motion.standard)) { manual = (true, finished) }
            }
        }
        // Done or not done again: back to folding by itself (one opened by hand and re-ticked folds too). Its last
        // set logged while typing in it: the card folds, so the keyboard goes too.
        .onChange(of: finished) { _, now in
            manual = nil
            if now, typingHere(focus.wrappedValue) { focus.wrappedValue = nil }
        }
        .overlay(alignment: .top) {
            if let best {
                RecordNote(text: best.text).frame(height: headerHeight + 12).padding(.horizontal, -6).offset(y: -6)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: Motion.standard), value: best?.id)
        .task(id: best?.id) { if best != nil { try? await Task.sleep(for: .seconds(RecordNote.seconds)); best = nil } }
        .padding(16)
        .glass(lifted: false)
        .clipShape(RoundedRectangle(cornerRadius: Measure.card, style: .continuous))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { box.cards[exercise.id] = $0 }
        .animation(.smooth(duration: Motion.standard), value: open)
        .animation(.smooth(duration: Motion.quick), value: exercise.sets.map(\.id))
        .sensoryFeedback(.selection, trigger: open)
    }

    /// Saving a set redraws only its card, not every card in the workout (the keyboard focus updates each by itself).
    static func == (a: Self, b: Self) -> Bool {
        a.exercise == b.exercise && a.unit == b.unit && a.autoLog == b.autoLog && a.bests.id == b.bests.id
            && a.focusHere == b.focusHere
    }

    private func typingHere(_ id: String?) -> Bool {
        guard let id else { return false }
        return exercise.sets.contains { id.hasPrefix($0.id) }
    }

    private var sidesLabel: String {
        switch exercise.startingSide { case nil: "Sides: both"; case .left?: "Sides: left first"; case .right?: "Sides: right first" }
    }

    /// A new set with the last one's weight and reps to start from (RIR blank), on the other side if in sides.
    private func addSet() {
        model.update { $0.updateActive(exercise: exercise.id) { exercise in exercise.sets.append(exercise.nextSet) } }
    }

    private func move(by step: Int) {
        model.update { training in
            guard let from = training.active?.exercises.firstIndex(where: { $0.id == exercise.id }),
                  training.active?.exercises.indices.contains(from + step) == true else { return }
            training.active?.exercises.swapAt(from, from + step)
        }
    }
}
