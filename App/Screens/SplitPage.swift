import SwiftUI
import TrackCore

/// A split, as the website's split page: its name (✏︎ to rename) over its size, Start workout, "Your exercises" (swipe
/// one left to remove it, hold and drag to move it), Add exercise, Resume while a workout is on, and Delete split.
struct SplitPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let splitId: String
    @State private var picking = false

    var body: some View {
        if let split = model.training.splits.first(where: { $0.id == splitId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(split.name).font(.system(size: 34, weight: .bold)).foregroundStyle(Palette.text)
                            Text(split.exercises.isEmpty ? "Tap to add exercises" : split.summary).font(.body)
                                .foregroundStyle(split.exercises.isEmpty ? Palette.accent : Palette.muted)
                        }
                        Spacer()
                        GlassCircleButton(icon: "pencil", label: "Rename split") {
                            model.naming = Naming(title: "Rename split", name: split.name, action: "Save") { name in model.update { $0.edit(splitId) { $0.name = name } } }
                        }
                    }
                    if split.exercises.isEmpty {
                        EmptyCard(icon: "dumbbell", title: "Build your session.", detail: "Search the exercise library to add your first movement.")
                    } else {
                        Button { model.start(split) } label: { Label("Start workout", systemImage: "play") }
                            .buttonStyle(PrimaryButtonStyle()).disabled(model.training.active != nil)
                        SmallHeader(title: "Your exercises")
                        NativeList(items: split.exercises, deleteLabel: "Remove", onDelete: { remove($0, from: split) },
                                   onMove: { from, to in model.update { $0.edit(splitId) { $0.exercises = $0.exercises.moved(from, to: to) } } }) { exercise in
                            HStack {
                                Text(exercise.name).foregroundStyle(Palette.text)
                                Spacer()
                                Text(count(exercise.sets.count, "set")).font(.subheadline).foregroundStyle(Palette.muted)
                            }
                            .frame(minHeight: 28)
                        }
                    }
                    Button { picking = true } label: { Label("Add exercise", systemImage: "plus") }.buttonStyle(SecondaryButtonStyle())
                    if model.training.active != nil {
                        Button("Resume your active workout") { model.workoutOpen = true }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    Button { model.deleteSplit(split) } label: { Label("Delete split", systemImage: "trash") }
                        .buttonStyle(SecondaryButtonStyle(danger: true))
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
                .animation(.smooth(duration: 0.3), value: split.exercises.map(\.id))
                .sensoryFeedback(.selection, trigger: split.exercises.map(\.id))
            }
            .background(Backdrop())
            .navigationTitle(split.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
            .sheet(isPresented: $picking) {
                ExercisePicker { name in model.update { $0.edit(splitId) { $0.exercises.append(Exercise.new(named: name)) } } }
            }
        } else {
            // Deleted: back to Home.
            Color.clear.onAppear { dismiss() }
        }
    }

    private func remove(_ exercise: Exercise, from split: Split) {
        model.confirm = Confirm(title: "Remove \(exercise.name)?",
                                message: "Past workouts keep it.",
                                label: "Remove exercise", destructive: true) {
            model.update { $0.edit(splitId) { $0.exercises.removeAll { $0.id == exercise.id } } }
        }
    }
}

extension Training {
    /// Changes one split.
    mutating func edit(_ splitId: String, _ change: (inout Split) -> Void) {
        guard let index = splits.firstIndex(where: { $0.id == splitId }) else { return }
        change(&splits[index])
    }
}
