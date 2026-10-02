import SwiftUI
import TrackCore

/// A new split: one of the starters (one tap, ready to start) or a blank one to build.
struct NewSplitView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onCreate: (Split) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section { ForEach(SplitTemplate.all) { template in
                    Button { create(template.makeSplit()) } label: {
                        ListRow(mark: true, title: template.name, detail: template.exercises.prefix(3).joined(separator: ", ") + "…") {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Palette.accent)
                        }
                    }
                    .glassRow()
                } } header: { Header(title: "Starters") }
                Section {
                    Button { create(Split(name: "New split")) } label: {
                        ListRow(icon: "square.and.pencil", title: "Blank split", detail: "Pick your own exercises") { EmptyView() }
                    }
                    .glassRow()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Backdrop())
            .navigationTitle("New split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func create(_ split: Split) {
        model.update { $0.splits.append(split) }
        dismiss()
        // The editor opens once this sheet has gone.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onCreate(split) }
    }
}

/// A split: its name, exercises (drag to reorder, swipe to remove) with their set counts, and Start.
struct SplitEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let splitId: String
    @State private var picking = false

    var body: some View {
        NavigationStack {
            if let split = model.training.splits.first(where: { $0.id == splitId }) {
                List {
                    Section {
                        TextField("Name", text: Binding(get: { split.name }, set: { name in
                            let trimmed = String(name.prefix(100))
                            model.update { $0.edit(splitId) { $0.name = trimmed.trimmingCharacters(in: .whitespaces).isEmpty ? $0.name : trimmed } }
                        }))
                        .font(.headline).glassRow()
                    } header: { Header(title: "Name") }
                    Section {
                        ForEach(split.exercises) { exercise in
                            Stepper(value: Binding(get: { exercise.sets.count }, set: { sets in setCount(exercise.id, sets) }), in: 1...20) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name).font(.headline).foregroundStyle(Palette.text)
                                    Text(count(exercise.sets.count, "set")).font(.subheadline).foregroundStyle(Palette.muted)
                                }
                            }
                            .glassRow()
                        }
                        .onDelete { offsets in model.update { $0.edit(splitId) { $0.exercises.remove(atOffsets: offsets) } } }
                        .onMove { from, to in model.update { $0.edit(splitId) { $0.exercises.move(fromOffsets: from, toOffset: to) } } }
                        Button { picking = true } label: { Label("Add exercise", systemImage: "plus") }.glassRow()
                    } header: { Header(title: "Exercises", count: split.exercises.isEmpty ? nil : split.exercises.count) }
                    Section {
                        Button { start(split) } label: { Label("Start workout", systemImage: "play") }
                            .buttonStyle(PrimaryButtonStyle()).disabled(split.exercises.isEmpty || model.training.active != nil)
                            .bareRow()
                    } footer: {
                        if model.training.active != nil { Text("Finish the current workout to start another.") }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Backdrop())
                .environment(\.editMode, .constant(.active))
                .navigationTitle(split.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $picking) {
                    ExercisePicker { name in model.update { $0.edit(splitId) { $0.exercises.append(Exercise.new(named: name)) } } }
                }
                .sensoryFeedback(.selection, trigger: split.exercises.map(\.sets.count))
            }
        }
    }

    private func setCount(_ exerciseId: String, _ sets: Int) {
        model.update { training in
            training.edit(splitId) { split in
                guard let index = split.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
                var exercise = split.exercises[index]
                while exercise.sets.count < sets { exercise.sets.append(TrainingSet(side: exercise.nextSide)) }
                if exercise.sets.count > sets { exercise.sets.removeLast(exercise.sets.count - sets) }
                split.exercises[index] = exercise
            }
        }
    }

    private func start(_ split: Split) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { model.start(split) }
    }
}

extension Training {
    /// Changes one split.
    mutating func edit(_ splitId: String, _ change: (inout Split) -> Void) {
        guard let index = splits.firstIndex(where: { $0.id == splitId }) else { return }
        change(&splits[index])
    }
}
