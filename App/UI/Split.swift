import SwiftUI
import TrackCore

/// A split (the PWA's Split): its name over its size with Edit, each exercise on a card (number, sets, last time's top
/// set), Add exercise, Last time, and Start workout docked at the bottom. Editing renames it, moves exercises by the
/// grip, removes them (asking first, then Undo) and offers Delete split.
struct SplitScreen: View {
    @Environment(AppModel.self) private var model
    let splitId: String
    @State private var editingOn = false
    @State private var name = ""

    var body: some View {
        if let split = model.training.splits.first(where: { $0.id == splitId }) {
            // Its workout is on: the split follows the workout, so changes belong there (here they'd be undone).
            let live = model.training.active?.splitId == split.id
            let editing = editingOn && !live
            let last = model.training.latestSession(of: splitId)
            let unit = model.training.settings.unit
            DeepPage {
                TitleBar(title: split.name, subtitle: split.summary) {
                    if !live { Button(editing ? "Done" : "Edit") { toggleEditing(split) }.buttonStyle(SecondaryStyle(hug: true)) }
                }
                if editing {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("Split name").type(.t14).foregroundStyle(Palette.muted)
                        Field(placeholder: "Split name", text: $name, label: "Split name") { rename(split) }
                    }
                    .padding(.top, Space.s4)
                }
                Group {
                    if split.exercises.isEmpty {
                        Text("No exercises yet. Add the first one.").type(.t14).foregroundStyle(Palette.muted)
                    } else if editing {
                        ArrangeList(items: split.exercises, name: \.name, onMove: { from, to in
                            model.update { $0.edit(splitId) { $0.exercises = $0.exercises.moved(from, to: to) } }
                        }) { exercise in
                            names(exercise)
                        } end: { exercise in
                            RoundButton(icon: .trash, label: "Remove \(exercise.name)") { remove(exercise) }
                        }
                    } else {
                        VStack(spacing: Space.s3) {
                            ForEach(Array(split.exercises.enumerated()), id: \.element.id) { index, exercise in
                                HStack(spacing: Space.s3) {
                                    Text("\(index + 1)").type(.t16).monospacedDigit().foregroundStyle(Palette.text)
                                        .frame(width: Size.tile, height: Size.tile).raised(.control, .inner)
                                    names(exercise).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(topSet(exercise, last, unit)).type(.t14).monospacedDigit().foregroundStyle(Palette.text).lineLimit(1)
                                }
                                .pad()
                                .raised()
                            }
                        }
                    }
                }
                .padding(.top, Space.s4)
                if live {
                    Text("This split’s workout is on. Change its exercises in the workout; the split keeps them.")
                        .type(.t14).foregroundStyle(Palette.muted).padding(.top, Space.s3)
                } else {
                    Button {
                        model.present(ExercisePicker { name in model.update { $0.edit(splitId) { $0.exercises.append(Exercise.new(named: name)) } } }, tall: true)
                    } label: { Label { Text("Add exercise") } icon: { Icon.plus.image(IconSize.medium) } }
                    .buttonStyle(SecondaryStyle()).padding(.top, Space.s3)
                }
                if editing {
                    Button("Delete split") { model.deleteSplit(split) }.buttonStyle(SecondaryStyle(danger: true)).padding(.top, Space.s6)
                } else if let last, let finished = last.finishedAt {
                    HStack(spacing: Space.s3) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Last time").type(.t14).foregroundStyle(Palette.muted)
                            Text(Date(timeIntervalSince1970: Double(finished) / 1000).formatted(.gregorian.weekday(.wide).month(.abbreviated).day()))
                                .type(.t16).foregroundStyle(Palette.text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(last.minutes) min")
                            Text("\(weight(last.volume, unit)) \(unit.rawValue)")
                        }
                        .type(.t14).monospacedDigit().foregroundStyle(Palette.muted)
                    }
                    .pad()
                    .raised()
                    .padding(.top, Space.s6)
                }
                // Room for the dock, so the last card scrolls clear of it.
                if !editing { Color.clear.frame(height: Size.primary + Space.s4 - homeIndicator) }
            }
            .overlay(alignment: .bottom) {
                if !editing {
                    Button { if model.training.active == nil { model.start(split) } else { model.workoutOpen = true } } label: {
                        Label { Text(model.training.active == nil ? "Start workout" : "Workout in progress") } icon: { Icon.play.image(IconSize.small) }
                    }
                    .buttonStyle(PrimaryStyle())
                    .disabled(split.exercises.isEmpty)
                    .padding(.horizontal, Space.s4)
                    .frame(maxWidth: Size.column)
                    .floatingBottom()
                }
            }
            .sensoryFeedback(.selection, trigger: split.exercises.map(\.id))
        } else {
            DeepPage { TitleBar(title: "Split", subtitle: "This split no longer exists.") }
        }
    }

    private func names(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(exercise.name).type(.t16).foregroundStyle(Palette.text)
            Text(count(exercise.setCount, "set")).type(.t14).foregroundStyle(Palette.muted)
        }
    }

    /// Last time's best set of this exercise in this split (by id or name), or New.
    private func topSet(_ exercise: Exercise, _ last: Session?, _ unit: TrackCore.Settings.Unit) -> String {
        let done = last?.exercises.first { $0.id == exercise.id || $0.name == exercise.name }?.sets.filter { $0.done && $0.isValid } ?? []
        guard let best = done.max(by: { ($0.kg ?? 0, $0.reps ?? 0) < ($1.kg ?? 0, $1.reps ?? 0) }) else { return "New" }
        return "\(TrainingSet.display(kg: best.kg ?? 0, unit: unit)) \(unit.rawValue) × \(best.reps ?? 0)"
    }

    private func toggleEditing(_ split: Split) {
        if editingOn { rename(split) } else { name = split.name }
        editingOn.toggle()
    }

    private func rename(_ split: Split) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Limits.name))
        if !trimmed.isEmpty, trimmed != split.name { model.update { $0.edit(splitId) { $0.name = trimmed } } }
    }

    /// Asks first, then offers Undo, as every delete does.
    private func remove(_ exercise: Exercise) {
        model.confirm = Confirm(title: "Remove \(exercise.name)?", message: "Past workouts keep it.", label: "Remove", destructive: true) {
            guard let index = model.training.splits.first(where: { $0.id == splitId })?.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
            model.update { $0.edit(splitId) { $0.exercises.remove(at: index) } }
            model.show("Exercise removed.") {
                guard let owner = model.training.splits.first(where: { $0.id == splitId }), !owner.exercises.contains(where: { $0.id == exercise.id }) else { return }
                model.update { $0.edit(splitId) { $0.exercises.insert(exercise, at: min(index, $0.exercises.count)) } }
            }
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
