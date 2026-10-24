import SwiftUI
import TrackCore

/// A finished workout, as the PWA's: its name over the day and minutes, Volume · Sets · Avg RIR tiles, each exercise
/// (tap to see its sets), the note (saved when you leave it), then Repeat workout and Delete workout.
struct HistoryDetail: View {
    @Environment(AppModel.self) private var model
    let session: Session
    @State private var opened: String?
    @State private var note = ""
    @FocusState private var typing: Bool

    var body: some View {
        let unit = model.training.settings.unit
        let current = model.training.sessions.first { $0.id == session.id } ?? session
        let sets = current.completedSets
        let rir = sets.isEmpty ? 0 : Double(sets.reduce(0) { $0 + ($1.rir ?? 0) }) / Double(sets.count)
        let day = Date(timeIntervalSince1970: Double(current.finishedAt ?? current.startedAt) / 1000)
        SheetFrame(title: current.name, subtitle: "\(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) · \(current.minutes) min") {
            HStack(spacing: Space.s3) {
                tile("Volume", weight(current.volume, unit), unit.rawValue)
                tile("Sets", "\(current.loggedCount)")
                tile("Avg RIR", rir.formatted(.number.precision(.fractionLength(1))))
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Space.s4)
            Text("Exercises").type(.t20).foregroundStyle(Palette.text).padding(.top, Space.s6)
            // Lazy: only the cards on screen are built as the sheet opens (an 18-exercise day took 256 ms to its first
            // frame on an iPhone 16, 180 ms lazily).
            LazyVStack(spacing: Space.s3) {
                ForEach(current.exercises) { exercise in card(exercise, unit: unit) }
            }
            .padding(.top, Space.s2)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Note").type(.t14).foregroundStyle(Palette.muted)
                TextField("How did it go?", text: $note, axis: .vertical)
                    .type(.t14).foregroundStyle(Palette.text).lineLimit(2...6)
                    .focused($typing)
                    .onChange(of: note) { _, value in if value.count > Limits.notes { note = String(value.prefix(Limits.notes)) } }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .raised()
            .contentShape(Rectangle())
            .onTapGesture { typing = true }
            .padding(.top, Space.s6)
            VStack(spacing: Space.s3) {
                Button { repeatWorkout(current) } label: { Label("Repeat workout", systemImage: "play.fill") }.buttonStyle(PrimaryButtonStyle())
                Button("Delete workout") { model.deleteWorkout(current) }.buttonStyle(SecondaryButtonStyle(danger: true))
            }
            .padding(.top, Space.s6)
        }
        .onAppear { note = current.notes ?? "" }
        .onChange(of: typing) { _, now in if !now { save(current) } }
        .onDisappear { save(current) }
        .animation(.smooth(duration: Motion.standard), value: opened)
    }

    /// The exercise and its set count; open, a line per set: "1L", "60 kg × 8", "RIR 2".
    private func card(_ exercise: Exercise, unit: TrackCore.Settings.Unit) -> some View {
        let open = opened == exercise.id
        let labels = exercise.setLabels
        return VStack(alignment: .leading, spacing: 0) {
            Button { opened = open ? nil : exercise.id } label: {
                HStack(spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(exercise.name).type(.t16).foregroundStyle(Palette.text).multilineTextAlignment(.leading)
                        Text(count(exercise.setCount, "set")).type(.t14).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: IconSize.medium, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                .frame(minHeight: Size.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityValue(open ? "Open" : "Closed")
            if open {
                VStack(spacing: Space.s2) {
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        HStack(spacing: Space.s3) {
                            Text(labels[index]).foregroundStyle(Palette.muted).frame(width: Space.s6)
                            Text("\(TrainingSet.display(kg: set.kg ?? 0, unit: unit)) \(unit.rawValue) × \(set.reps ?? 0)").foregroundStyle(Palette.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("RIR \(set.rir ?? 0)").foregroundStyle(Palette.muted)
                        }
                        .type(.t14).monospacedDigit()
                    }
                }
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s3)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .raised()
        .clipped()
    }

    private func tile(_ label: String, _ value: String, _ unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).type(.t14).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                Text(value).type(.t20).monospacedDigit().foregroundStyle(Palette.text)
                if let unit { Text(unit).type(.t14).foregroundStyle(Palette.muted) }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .raised()
    }

    /// While another workout is on, it says why instead of doing nothing.
    private func repeatWorkout(_ current: Session) {
        if model.training.active == nil { model.repeatWorkout(current) } else { model.show("Finish or discard your current workout first.") }
    }

    private func save(_ current: Session) {
        let text = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Limits.notes))
        let notes: String? = text.isEmpty ? nil : text
        guard notes != (model.training.sessions.first { $0.id == current.id }?.notes) else { return }
        model.update { training in
            guard let index = training.sessions.firstIndex(where: { $0.id == current.id }) else { return }
            training.sessions[index].notes = notes
        }
        model.show("Session note saved")
    }
}
