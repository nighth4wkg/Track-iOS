import SwiftUI
import TrackCore

/// A split, as the website's split page: its name (✏︎ to rename) over its size, Start workout, "Your exercises" (✕ to
/// remove one), Add exercise, Resume while a workout is on, and Delete split.
struct SplitPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let splitId: String
    @State private var picking = false
    @State private var renaming = false

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
                        GlassCircleButton(icon: "pencil", label: "Rename split") { renaming = true }
                    }
                    if split.exercises.isEmpty {
                        EmptyCard(icon: "dumbbell", title: "Build your session.", detail: "Search the exercise library to add your first movement.")
                    } else {
                        Button { model.start(split) } label: { Label("Start workout", systemImage: "play") }
                            .buttonStyle(PrimaryButtonStyle()).disabled(model.training.active != nil)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your exercises").font(.headline).foregroundStyle(Palette.text)
                            Text("Remove what you don’t do with ✕, or add your own below.").font(.subheadline).foregroundStyle(Palette.muted)
                                .padding(.bottom, 6)
                            ForEach(split.exercises) { exercise in
                                HStack {
                                    Text(exercise.name).foregroundStyle(Palette.text)
                                    Spacer()
                                    Text(count(exercise.sets.count, "set")).font(.subheadline).foregroundStyle(Palette.muted)
                                    GlassCircleButton(icon: "xmark", label: "Remove \(exercise.name)") { remove(exercise, from: split) }
                                }
                                .frame(minHeight: 48)
                            }
                        }
                        .padding(16).glass()
                    }
                    Button { picking = true } label: { Label("Add exercise", systemImage: "plus") }.buttonStyle(SecondaryButtonStyle())
                    if model.training.active != nil {
                        Button("Resume your active workout") { model.workoutOpen = true }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    Button { model.deleteSplit(split); } label: { Label("Delete split", systemImage: "trash") }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.danger).frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
                .animation(.smooth(duration: 0.3), value: split.exercises.map(\.id))
            }
            .background(Backdrop())
            .navigationTitle(split.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
            .sheet(isPresented: $picking) {
                ExercisePicker { name in model.update { $0.edit(splitId) { $0.exercises.append(Exercise.new(named: name)) } } }
            }
            .sheet(isPresented: $renaming) {
                NameSheet(title: "Rename split", name: split.name, action: "Save") { name in model.update { $0.edit(splitId) { $0.name = name } } }
            }
        } else {
            // Deleted: back to Home.
            Color.clear.onAppear { dismiss() }
        }
    }

    private func remove(_ exercise: Exercise, from split: Split) {
        model.confirm = Confirm(title: "Remove \(exercise.name)?",
                                message: "Remove this exercise and its sets from the saved split. Past workouts stay in your history.",
                                label: "Remove exercise", destructive: true) {
            model.update { $0.edit(splitId) { $0.exercises.removeAll { $0.id == exercise.id } } }
        }
    }
}

/// Naming a split, as the website's dialog: "Give your routine a name that makes sense to you."
struct NameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State var name: String
    let action: String
    let onSave: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(Palette.text)
            Text("Give your routine a name that makes sense to you.").font(.subheadline).foregroundStyle(Palette.muted)
            TextField("Split name", text: $name).focused($focused).submitLabel(.done).onSubmit(save)
                .font(.body.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.input))
                .onChange(of: name) { _, value in if value.count > 100 { name = String(value.prefix(100)) } }
            Button(action, action: save).buttonStyle(PrimaryButtonStyle()).disabled(trimmed.isEmpty)
        }
        .padding(24)
        .presentationDetents([.height(280)])
        .presentationBackground(.ultraThinMaterial)
        .onAppear { focused = true }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}

extension Training {
    /// Changes one split.
    mutating func edit(_ splitId: String, _ change: (inout Split) -> Void) {
        guard let index = splits.firstIndex(where: { $0.id == splitId }) else { return }
        change(&splits[index])
    }
}
