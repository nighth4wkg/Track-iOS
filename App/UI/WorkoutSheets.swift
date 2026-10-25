import SwiftUI
import TrackCore

/// The workout's options (the PWA's sheet): Arrange exercises, Rename workout, the weight unit, Discard workout.
struct WorkoutOptions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeSheet) private var close
    let arrange: () -> Void

    var body: some View {
        let active = model.training.active
        SheetFrame(title: active?.name ?? "Workout") {
            RowCard {
                Button { close(); arrange() } label: { Row(title: "Arrange exercises", value: "", chevron: true) }
                    .buttonStyle(RowStyle()).disabled((active?.exercises.count ?? 0) < 2)
                Button { close(); model.present(RenameWorkout()) } label: { Row(title: "Rename workout", value: "", chevron: true) }
                    .buttonStyle(RowStyle())
                Row(title: "Weight unit") {
                    Seg(label: "Weight unit", options: [(value: TrackCore.Settings.Unit.kg, text: "kg"), (value: .lb, text: "lb")],
                        value: Binding(get: { model.training.settings.unit }, set: { unit in model.update { $0.settings.unit = unit } }), compact: true)
                }
                Button { close(); model.discard() } label: { Row(title: "Discard workout", tint: Palette.danger) { EmptyView() } }
                    .buttonStyle(RowStyle())
            }
            .padding(.top, Space.s3)
        }
    }
}

/// Renaming the workout renames its split as well.
struct RenameWorkout: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeSheet) private var close
    @State private var name = ""

    var body: some View {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Limits.name))
        let save = {
            guard !trimmed.isEmpty else { return }
            model.update { training in
                training.active?.name = trimmed
                if let id = training.active?.splitId { training.edit(id) { $0.name = trimmed } }
            }
            close()
        }
        SheetFrame(title: "Rename workout", closeLabel: "Cancel") {
            VStack(alignment: .leading, spacing: Space.s2) {
                Field(placeholder: "Workout name", text: $name, label: "Workout name", submit: save)
                Text("Your split is renamed too.").type(.t14).foregroundStyle(Palette.muted)
                Button("Save", action: save).buttonStyle(PrimaryStyle()).disabled(trimmed.isEmpty).padding(.top, Space.s2)
            }
            .padding(.top, Space.s3)
        }
        .onAppear { name = model.training.active?.name ?? "" }
    }
}

/// An exercise's options (the PWA's): Swap exercise, Sides (Both → Left first → Right first), Remove last set, Remove
/// exercise. It shows the exercise's latest state.
struct ExerciseOptions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeSheet) private var close
    let exerciseId: String

    var body: some View {
        if let exercise = model.training.active?.exercises.first(where: { $0.id == exerciseId }) {
            let sides = switch exercise.startingSide { case nil: "Both"; case .left?: "Left first"; case .right?: "Right first" }
            SheetFrame(title: exercise.name) {
                RowCard {
                    Button {
                        close()
                        model.present(ExercisePicker(replacing: exercise.name) { name in
                            model.swap(exercise, for: name, inWorkout: true, splitId: model.training.active?.splitId)
                        }, tall: true)
                    } label: { Row(title: "Swap exercise", value: "", chevron: true) }
                    .buttonStyle(RowStyle())
                    Button { model.update { $0.updateActive(exercise: exerciseId) { $0 = $0.cyclingSides() } } } label: { Row(title: "Sides", value: sides) }
                        .buttonStyle(RowStyle())
                        .accessibilityLabel("Sides: \(sides). Change")
                        .sensoryFeedback(.selection, trigger: sides)
                }
                .padding(.top, Space.s3)
                RowCard {
                    Button { if let last = exercise.setGroups.last?.first { model.removeSet(last.id, in: exerciseId) } } label: {
                        Row(title: "Remove last set") { EmptyView() }
                    }
                    .buttonStyle(RowStyle()).disabled(exercise.setCount < 2)
                    Button { close(); model.removeExercise(exercise) } label: { Row(title: "Remove exercise", tint: Palette.danger) { EmptyView() } }
                        .buttonStyle(RowStyle())
                }
                .padding(.top, Space.s3)
            }
        } else {
            SheetFrame(title: "Exercise") { Text("This exercise is no longer in the workout.").type(.t14).foregroundStyle(Palette.muted).padding(.top, Space.s3) }
        }
    }
}
