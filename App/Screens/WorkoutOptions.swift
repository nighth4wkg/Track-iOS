import SwiftUI
import TrackCore

/// The workout's options, as the PWA's sheet: Arrange exercises, Rename workout, the weight unit, Discard workout.
struct WorkoutOptions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let arrange: () -> Void
    let rename: () -> Void

    var body: some View {
        let active = model.training.active
        SheetFrame(title: active?.name ?? "Workout") {
            RowCard {
                Button(action: arrange) { Row(title: "Arrange exercises", value: "", chevron: true) }
                    .buttonStyle(PressStyle()).disabled((active?.exercises.count ?? 0) < 2)
                Button(action: rename) { Row(title: "Rename workout", value: "", chevron: true) }.buttonStyle(PressStyle())
                Row(title: "Weight unit") {
                    Seg(label: "Weight unit", options: [(value: TrackCore.Settings.Unit.kg, text: "kg"), (value: .lb, text: "lb")],
                        value: Binding(get: { model.training.settings.unit }, set: { unit in model.update { $0.settings.unit = unit } }), compact: true)
                }
                Button { dismiss(); model.discard() } label: { Row(title: "Discard workout", tint: Palette.danger) { EmptyView() } }
                    .buttonStyle(PressStyle())
            }
            .padding(.top, Space.s3)
        }
    }
}

/// Renaming the workout renames its split as well.
struct RenameWorkout: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        let save = {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            model.update { training in
                training.active?.name = trimmed
                if let id = training.active?.splitId { training.edit(id) { $0.name = trimmed } }
            }
            dismiss()
        }
        SheetFrame(title: "Rename workout", closeLabel: "Cancel") {
            VStack(alignment: .leading, spacing: Space.s2) {
                Field(placeholder: "Workout name", text: $name, label: "Workout name", submit: save)
                Text("Your split is renamed too.").type(.t14).foregroundStyle(Palette.muted)
                Button("Save", action: save).buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.top, Space.s2)
            }
            .padding(.top, Space.s3)
        }
        .onAppear { name = model.training.active?.name ?? "" }
    }
}

/// An exercise's options, as the PWA's: Swap exercise, Sides (Both → Left first → Right first), Remove last set,
/// Remove exercise. It shows the exercise's latest state.
struct ExerciseOptions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let exerciseId: String
    let swap: (Exercise) -> Void

    var body: some View {
        if let exercise = model.training.active?.exercises.first(where: { $0.id == exerciseId }) {
            let sides = switch exercise.startingSide { case nil: "Both"; case .left?: "Left first"; case .right?: "Right first" }
            SheetFrame(title: exercise.name) {
                RowCard {
                    Button { swap(exercise) } label: { Row(title: "Swap exercise", value: "", chevron: true) }.buttonStyle(PressStyle())
                    Button { model.update { $0.updateActive(exercise: exerciseId) { $0 = $0.cyclingSides() } } } label: { Row(title: "Sides", value: sides) }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Sides: \(sides). Change")
                        .sensoryFeedback(.selection, trigger: sides)
                }
                .padding(.top, Space.s3)
                RowCard {
                    Button { if let last = exercise.setGroups.last?.first { model.removeSet(last.id, in: exerciseId) } } label: {
                        Row(title: "Remove last set") { EmptyView() }
                    }
                    .buttonStyle(PressStyle()).disabled(exercise.setCount < 2)
                    Button { dismiss(); model.removeExercise(exercise) } label: { Row(title: "Remove exercise", tint: Palette.danger) { EmptyView() } }
                        .buttonStyle(PressStyle())
                }
                .padding(.top, Space.s3)
            }
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }
}
