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
            VStack(spacing: 0) {
                header(current, exercises: exercises.count, unit: unit)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        note(current)
                        ForEach(exercises) { exercise in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(exercise.name).font(.body.weight(.semibold)).foregroundStyle(Palette.text)
                                setRow("Set", "Weight (\(unit.rawValue))", "Reps", "RIR")
                                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                                    setRow("\(index + 1)" + (set.side.map { $0 == .left ? " L" : " R" } ?? ""),
                                           TrainingSet.display(kg: set.kg, unit: unit), "\(set.reps ?? 0)", "\(set.rir ?? 0)", numbers: true)
                                }
                            }
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass()
                        }
                    }
                    .padding(16)
                }
                .background(Palette.background.opacity(0.32))
            }
            .background(Backdrop())
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 16) {
                    Button { model.deleteWorkout(current) } label: {
                        Label("Delete", systemImage: "trash").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).frame(minHeight: 44).background(Capsule().fill(Palette.danger))
                    }
                    .buttonStyle(PressStyle())
                    Spacer()
                    // While another workout is on, it says why instead of doing nothing.
                    Button { model.training.active == nil ? model.repeatWorkout(current) : model.show("Finish or discard your current workout first.") } label: {
                        Label("Repeat workout", systemImage: "play").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.primaryText)
                            .padding(.horizontal, 16).frame(minHeight: 44).background(Capsule().fill(Palette.primary))
                    }
                    .buttonStyle(PressStyle()).opacity(model.training.active != nil ? 0.45 : 1)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(.bar)
                .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// The website's header: the name over the date, then Exercises · Sets · Volume as plain figures (volume in the
    /// accent), over a hairline.
    private func header(_ current: Session, exercises: Int, unit: TrackCore.Settings.Unit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(current.name).font(.title2.weight(.bold)).foregroundStyle(Palette.text)
                Spacer()
                GlassCircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            Text(Date(timeIntervalSince1970: Double(current.finishedAt ?? current.startedAt) / 1000)
                .formatted(.gregorian.weekday(.abbreviated).month(.abbreviated).day().year()))
                .font(.subheadline).foregroundStyle(Palette.muted)
            HStack(alignment: .top, spacing: 16) {
                stat("Exercises", "\(exercises)")
                stat("Sets", "\(current.completedSets.count)")
                stat("Volume", weight(current.volume, unit), small: unit.rawValue, accent: true).frame(minWidth: 120)
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private func stat(_ label: String, _ value: String, small: String? = nil, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(accent ? Palette.accent : Palette.text)
                if let small { Text(small).font(.caption).foregroundStyle(Palette.muted) }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One line of the sets table, as the website's: Set on the left, the numbers right-aligned, RIR muted.
    private func setRow(_ set: String, _ kg: String, _ reps: String, _ rir: String, numbers: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(set).foregroundStyle(Palette.muted).frame(width: 44, alignment: .leading)
            Text(kg).frame(minWidth: 64, maxWidth: .infinity, alignment: .trailing)
            Text(reps).frame(maxWidth: .infinity, alignment: .trailing)
            Text(rir).foregroundStyle(Palette.muted).fontWeight(.regular).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(numbers ? .body.weight(.semibold) : .caption)
        .monospacedDigit()
        .foregroundStyle(numbers ? Palette.text : Palette.muted)
        .frame(minHeight: numbers ? 32 : 20)
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
