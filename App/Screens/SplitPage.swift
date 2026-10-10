import SwiftUI
import TrackCore

/// A split, as the website's split page: its name over its size, Start workout, "Your exercises" (swipe one left to
/// remove it, hold and drag to move it), Add exercise, Resume while a workout is on, and Delete split. The pen turns
/// editing on: Rename under the name, and ✎ (swap, asking first) and ✕ (remove) sliding in on each exercise.
struct SplitPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let splitId: String
    @State private var picking = false
    @State private var editingOn = false
    @State private var swapping: Exercise?
    @State private var picked: (exercise: Exercise, name: String)?

    var body: some View {
        if let split = model.training.splits.first(where: { $0.id == splitId }) {
            // Its workout is on: the split follows the workout, so changes belong there (here they'd be undone).
            let live = model.training.active?.splitId == split.id
            let editing = editingOn && !live
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(split.name).scaledFont(34, weight: .bold).foregroundStyle(Palette.text)
                            if split.exercises.isEmpty && !live {
                                Button("Tap to add exercises") { picking = true }.font(.body).foregroundStyle(Palette.accent)
                            } else {
                                Text(split.summary).font(.body).foregroundStyle(Palette.muted)
                            }
                            if editing {
                                Button {
                                    model.naming = Naming(title: "Rename split", name: split.name, action: "Save name") { name in model.update { $0.edit(splitId) { $0.name = name } } }
                                } label: { Label("Rename", systemImage: "pencil").frame(minHeight: 44) }
                                .buttonStyle(PressStyle()).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                                .transition(.opacity.combined(with: .offset(y: -8)))
                            }
                        }
                        Spacer()
                        if !live {
                            GlassCircleButton(icon: editing ? "checkmark" : "pencil", label: editing ? "Done editing" : "Edit split") {
                                withAnimation(.smooth(duration: Motion.standard)) { editingOn.toggle() }
                            }
                        }
                    }
                    if split.exercises.isEmpty {
                        EmptyCard(icon: "dumbbell", title: "Build your session.", detail: "Search the exercise library to add your first movement.")
                    } else {
                        Button { model.start(split) } label: { Label("Start workout", systemImage: "play") }
                            .buttonStyle(PrimaryButtonStyle()).disabled(model.training.active != nil)
                        SmallHeader(title: "Your exercises")
                        NativeList(items: split.exercises, deleteLabel: "Remove", onDelete: live ? nil : { remove($0, from: split) },
                                   onMove: live ? nil : { from, to in model.update { $0.edit(splitId) { $0.exercises = $0.exercises.moved(from, to: to) } } }) { exercise in
                            HStack(spacing: 8) {
                                Text(exercise.name).foregroundStyle(Palette.text)
                                Spacer()
                                Text(count(exercise.sets.count, "set")).font(.subheadline).foregroundStyle(Palette.muted)
                                if editing {
                                    HStack(spacing: 4) {
                                        rowButton("pencil", "Swap \(exercise.name)", Palette.muted) { swapping = exercise }
                                        rowButton("xmark", "Remove \(exercise.name)", Palette.dangerText) { remove(exercise, from: split) }
                                    }
                                    .transition(.opacity.combined(with: .offset(x: 12)))
                                }
                            }
                            .frame(minHeight: 28)
                        }
                    }
                    if live {
                        Text("This split’s workout is on. Change its exercises in the workout; the split keeps them.")
                            .font(.footnote).foregroundStyle(Palette.muted)
                    } else {
                        Button { picking = true } label: { Label("Add exercise", systemImage: "plus") }.buttonStyle(SecondaryButtonStyle())
                    }
                    if model.training.active != nil {
                        Button("Resume your active workout") { model.workoutOpen = true }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    Button { model.deleteSplit(split) } label: { Label("Delete split", systemImage: "trash") }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.dangerText).frame(maxWidth: .infinity, minHeight: 44)
                        .buttonStyle(PressStyle()).padding(.top, 24)
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
                .frame(maxWidth: Measure.page).frame(maxWidth: .infinity)
                .animation(.smooth(duration: Motion.standard), value: split.exercises.map(\.id))
                .sensoryFeedback(.selection, trigger: split.exercises.map(\.id))
            }
            .background(Backdrop())
            .navigationTitle(split.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
            .sheet(isPresented: $picking) {
                ExercisePicker { name in model.update { $0.edit(splitId) { $0.exercises.append(Exercise.new(named: name)) } } }
            }
            // The swap asks first once the picker has gone.
            .sheet(item: $swapping, onDismiss: {
                guard let picked else { return }
                self.picked = nil
                model.swap(picked.exercise, for: picked.name, inWorkout: false, splitId: splitId)
            }) { exercise in
                ExercisePicker(replacing: exercise.name) { picked = (exercise, $0) }
            }
        } else {
            // Deleted: back to Home.
            Color.clear.onAppear { dismiss() }
        }
    }

    /// A row's ✎ or ✕: the row's height, with a 44pt tap area reaching into its padding.
    private func rowButton(_ icon: String, _ label: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                .frame(width: 36, height: 28).padding(.vertical, 8).contentShape(Rectangle()).padding(.vertical, -8)
        }
        .buttonStyle(PressStyle()).accessibilityLabel(label)
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
