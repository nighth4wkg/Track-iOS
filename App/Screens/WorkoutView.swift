import SwiftUI
import TrackCore

/// The active workout, over everything: the time and sets logged, then a card per exercise with its sets
/// (set · kg · reps · RIR · ✓), the rest timer floating at the bottom, and Finish.
struct WorkoutView: View {
    @Environment(AppModel.self) private var model
    @State private var addingExercise = false
    @State private var confirmDiscard = false
    @FocusState private var focus: String?

    var body: some View {
        if let active = model.training.active {
            NavigationStack {
                List {
                    Section { progress(active).bareRow() }
                    ForEach(active.exercises) { exercise in
                        ExerciseSection(exercise: exercise, focus: $focus)
                    }
                    Section {
                        Button { addingExercise = true } label: { Label("Add exercise", systemImage: "plus") }
                            .frame(maxWidth: .infinity).glassRow()
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background(Backdrop())
                .navigationTitle(active.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .safeAreaInset(edge: .bottom) { RestCapsule() }
            }
            .sheet(isPresented: $addingExercise) {
                ExercisePicker { name in model.update { $0.active?.exercises.append(Exercise.new(named: name)) } }
            }
            .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard workout", role: .destructive) { model.discard() }
            } message: {
                Text("Its sets won’t be saved.")
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { model.workoutOpen = false } label: { Image(systemName: "chevron.down") }
                .accessibilityLabel("Back to Home")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Discard workout", systemImage: "trash", role: .destructive) { confirmDiscard = true }
            } label: { Image(systemName: "ellipsis") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Finish") { model.finish() }.fontWeight(.semibold).tint(Palette.accent)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focus = nil }.fontWeight(.semibold)
        }
    }

    private func progress(_ active: Session) -> some View {
        let total = active.exercises.reduce(0) { $0 + $1.sets.count }
        let done = active.completedSets.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsed(since: active.startedAt, now: context.date)).monospacedDigit()
                }
                Text("·")
                Text("\(done) of \(count(total, "set"))")
                Spacer()
            }
            .font(.subheadline).foregroundStyle(Palette.muted)
            ProgressView(value: Double(done), total: Double(max(total, 1))).tint(Palette.primary)
                .animation(.smooth, value: done)
        }
        .padding(.horizontal, 4)
    }

    private func elapsed(since start: Int, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince1970) - start / 1000)
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// One exercise: its name with the sets logged, the column labels, its sets (swipe left to delete one), then Add set
/// and the sides switch.
private struct ExerciseSection: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise
    var focus: FocusState<String?>.Binding

    var body: some View {
        Section {
            HStack(spacing: 8) {
                Text("SET").frame(width: 28)
                Text(model.training.settings.unit.rawValue.uppercased()).frame(maxWidth: .infinity)
                Text("REPS").frame(maxWidth: .infinity)
                Text("RIR").frame(maxWidth: .infinity)
                Color.clear.frame(width: 48, height: 1)
            }
            .font(.caption2.weight(.bold)).foregroundStyle(Palette.muted).glassRow()
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(exerciseId: exercise.id, set: set, number: index + 1, focus: focus).glassRow()
            }
            .onDelete { offsets in model.update { $0.updateActive(exercise: exercise.id) { $0.sets.remove(atOffsets: offsets) } } }
            HStack {
                Button { addSet() } label: { Label("Add set", systemImage: "plus") }
                Spacer()
                Button { model.update { $0.updateActive(exercise: exercise.id) { $0 = $0.togglingSides() } } } label: {
                    Label(sidesLabel, systemImage: "arrow.left.arrow.right")
                }
            }
            .buttonStyle(.borderless).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text).glassRow()
        } header: {
            HStack {
                Header(title: exercise.name)
                Spacer()
                Chip(text: "\(exercise.sets.filter(\.done).count)/\(exercise.sets.count)",
                     accent: !exercise.sets.isEmpty && exercise.sets.allSatisfy(\.done))
            }
        }
    }

    private var sidesLabel: String {
        switch exercise.startingSide { case nil: "Both sides"; case .left?: "Left first"; case .right?: "Right first" }
    }

    /// A new set: the last set's numbers as a suggestion, on the other side if the exercise is in sides.
    private func addSet() {
        model.update { training in
            training.updateActive(exercise: exercise.id) { exercise in
                let last = exercise.sets.last
                exercise.sets.append(TrainingSet(kg: last?.kg, reps: last?.reps, rir: last?.rir, side: exercise.nextSide))
            }
        }
    }
}
