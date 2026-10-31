import SwiftUI
import TrackCore

/// A finished workout (the PWA's Session): its name over the day and minutes, Volume · Sets · Avg RIR tiles, each
/// exercise (tap to see its sets), the note (saved when you leave it, or tap its Done), then Repeat workout and Delete
/// workout.
struct SessionScreen: View {
    @Environment(AppModel.self) private var model
    let sessionId: String
    @State private var opened: String?
    @State private var note = ""
    @FocusState private var typing: Bool

    var body: some View {
        if let current = model.training.sessions.first(where: { $0.id == sessionId }) {
            let unit = model.training.settings.unit
            let sets = current.completedSets
            let rir = sets.isEmpty ? 0 : Double(sets.reduce(0) { $0 + ($1.rir ?? 0) }) / Double(sets.count)
            let day = Date(timeIntervalSince1970: Double(current.finishedAt ?? current.startedAt) / 1000)
            DeepPage {
                TitleBar(title: current.name, subtitle: day.formatted(.gregorian.weekday(.wide).month(.abbreviated).day()) + dot + "\(current.minutes) min")
                HStack(spacing: Space.s3) {
                    tile("Volume", weight(current.volume, unit), unit.rawValue)
                    tile("Sets", "\(current.loggedCount)")
                    tile("Avg RIR", rir.formatted(.number.precision(.fractionLength(1))))
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s4)
                Text("Exercises").type(.t20).foregroundStyle(Palette.text).padding(.top, Space.s6).accessibilityAddTraits(.isHeader)
                LazyVStack(spacing: Space.s3) {
                    ForEach(current.exercises) { exercise in card(exercise, unit: unit) }
                }
                .padding(.top, Space.s2)
                noteCard(current).padding(.top, Space.s6)
                VStack(spacing: Space.s3) {
                    Button { repeatWorkout(current) } label: { Label { Text("Repeat workout") } icon: { Icon.play.image(IconSize.medium) } }
                        .buttonStyle(PrimaryStyle())
                    Button("Delete workout") { model.deleteWorkout(current) }.buttonStyle(SecondaryStyle(danger: true))
                }
                .padding(.top, Space.s6)
            }
            .onAppear { note = current.notes ?? "" }
            .onChange(of: typing) { _, now in if !now { save(current) } }
            .onDisappear { save(current) }
        } else {
            DeepPage { TitleBar(title: "Workout", subtitle: "This workout was deleted.") }
        }
    }

    /// Done shows while typing (as the PWA's), so leaving the note, and saving it, is a tap, not a guess.
    private func noteCard(_ current: Session) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                Text("Note").foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                if typing {
                    Button("Done") { typing = false }.fontWeight(.semibold).foregroundStyle(Palette.accent)
                        .buttonStyle(.plain).contentShape(Rectangle().inset(by: -Space.s3))
                }
            }
            .type(.t14)
            TextField("", text: $note, prompt: Text("How did it go?").foregroundStyle(Palette.placeholder), axis: .vertical)
                .autocorrectionDisabled() // as every field (Field): no suggestion bar to build
                .type(.t14).foregroundStyle(Palette.text).lineLimit(2...6)
                .focused($typing)
                .onChange(of: note) { _, value in if value.count > Limits.notes { note = String(value.prefix(Limits.notes)) } }
        }
        .pad()
        .frame(maxWidth: .infinity, alignment: .leading)
        .raised()
        .contentShape(Rectangle())
        .onTapGesture { typing = true }
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    (open ? Icon.up : Icon.down).image(IconSize.medium).foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                .frame(minHeight: Size.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowStyle())
            .accessibilityValue(open ? "Open" : "Closed")
            if open {
                VStack(spacing: Space.s2) {
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        HStack(spacing: Space.s3) {
                            Text(labels[index]).foregroundStyle(Palette.muted).frame(width: Space.s6)
                            Text(setText(set, unit)).foregroundStyle(Palette.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("RIR \(set.rir ?? 0)").foregroundStyle(Palette.muted)
                        }
                        .type(.t14).monospacedDigit()
                    }
                }
                .more()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(Corner.card.shape)
        .raised()
    }

    private func tile(_ label: String, _ value: String, _ unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).type(.t14).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                Text(value).type(.t20).monospacedDigit().foregroundStyle(Palette.text)
                if let unit { Text(unit).type(.t14).foregroundStyle(Palette.muted) }
            }
            .lineLimit(1).minimumScaleFactor(Shrink.figure)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .raised()
    }

    /// While another workout is on, it says why instead of doing nothing.
    private func repeatWorkout(_ current: Session) {
        if model.training.active == nil { model.repeatWorkout(current) } else { model.problem(TrainingError.activeWorkout.localizedDescription) }
    }

    private func save(_ current: Session) {
        let text = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Limits.notes))
        let notes: String? = text.isEmpty ? nil : text
        guard model.training.sessions.contains(where: { $0.id == current.id }),
              notes != (model.training.sessions.first { $0.id == current.id }?.notes) else { return }
        model.update { training in
            guard let index = training.sessions.firstIndex(where: { $0.id == current.id }) else { return }
            training.sessions[index].notes = notes
        }
        model.show("Session note saved")
    }
}
