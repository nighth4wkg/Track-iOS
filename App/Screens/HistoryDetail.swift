import SwiftUI
import TrackCore

/// A finished workout, as the website's history dialog: its name and date, Exercises · Sets · Volume, the session
/// note (add or edit it), each exercise's logged sets as a table, then Delete and Repeat workout.
struct HistoryDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let session: Session
    @State private var noteOpen = false
    @State private var draft = ""

    var body: some View {
        let unit = model.training.settings.unit
        let current = model.training.sessions.first { $0.id == session.id } ?? session
        let exercises = current.exercises.map { exercise in
            var logged = exercise
            logged.sets = exercise.sets.filter { $0.done && $0.isValid }
            return logged
        }.filter { !$0.sets.isEmpty }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        stat("Exercises", "\(exercises.count)")
                        stat("Sets", "\(current.completedSets.count)")
                        stat("Volume", "\(weight(current.volume, unit)) \(unit.rawValue)")
                    }
                    note(current)
                    ForEach(exercises) { exercise in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(exercise.name).font(.headline).foregroundStyle(Palette.text)
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                                GridRow {
                                    Text("Set"); Text("Weight (\(unit.rawValue))"); Text("Reps"); Text("RIR")
                                }
                                .font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
                                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                                    GridRow {
                                        HStack(spacing: 4) {
                                            Text("\(index + 1)")
                                            if let side = set.side { Chip(text: side == .left ? "L" : "R") }
                                        }
                                        Text(TrainingSet.display(kg: set.kg, unit: unit))
                                        Text("\(set.reps ?? 0)")
                                        Text("\(set.rir ?? 0)")
                                    }
                                    .font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.text)
                                }
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass()
                    }
                }
                .padding(16)
            }
            .background(Backdrop())
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button { model.deleteWorkout(current) } label: { Label("Delete", systemImage: "trash") }
                        .font(.headline).foregroundStyle(Palette.danger).frame(minWidth: 96, minHeight: 50).buttonStyle(PressStyle())
                    Button { model.repeatWorkout(current) } label: { Label("Repeat workout", systemImage: "play") }
                        .buttonStyle(PrimaryButtonStyle()).disabled(model.training.active != nil)
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            .navigationTitle(current.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(current.name).font(.headline).foregroundStyle(Palette.text)
                        Text(Date(timeIntervalSince1970: Double(current.finishedAt ?? current.startedAt) / 1000)
                            .formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Palette.text) }.accessibilityLabel("Close")
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Palette.muted)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12).glass(radius: 16)
    }

    /// "Add a note" (or the note), opening a field with 500 characters, Cancel and Save note.
    private func note(_ current: Session) -> some View {
        let notes = current.notes ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                if !noteOpen { draft = notes }
                withAnimation(.smooth(duration: 0.3)) { noteOpen.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.pencil").foregroundStyle(Palette.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notes.isEmpty ? "Add a note" : "Session note").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                        if !notes.isEmpty, !noteOpen { Text(notes).font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1) }
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Palette.muted).scaleEffect(y: noteOpen ? -1 : 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            if noteOpen {
                TextField("How did this workout feel?", text: $draft, axis: .vertical)
                    .lineLimit(3...6).padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.input))
                    .onChange(of: draft) { _, value in if value.count > 500 { draft = String(value.prefix(500)) } }
                HStack {
                    Text("\(draft.count)/500").font(.caption).foregroundStyle(Palette.muted)
                    Spacer()
                    Button("Cancel") { withAnimation(.smooth) { noteOpen = false } }.foregroundStyle(Palette.text)
                    Button("Save note") {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.update { training in
                            guard let index = training.sessions.firstIndex(where: { $0.id == current.id }) else { return }
                            training.sessions[index].notes = text.isEmpty ? nil : text
                        }
                        withAnimation(.smooth) { noteOpen = false }
                    }
                    .fontWeight(.semibold).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines) == notes)
                }
                .font(.subheadline)
                .transition(.opacity)
            }
        }
        .padding(16).glass()
    }
}
