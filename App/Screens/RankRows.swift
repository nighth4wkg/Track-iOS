import SwiftUI
import TrackCore

/// A muscle on its own card, as the PWA's: its name and rank, a bar toward the next, how far that is (or what to log);
/// tapped open, its best lift beside what reaches the next rank, and the exercises counting toward it.
struct MuscleRow: View {
    let rank: MuscleRank
    let unit: TrackCore.Settings.Unit
    let names: [CountedName]
    @State private var open = false

    /// What to log to rank a muscle that has nothing yet.
    private static let hints: [Muscle: String] = [
        .chest: "Log a bench press", .back: "Log a row or pulldown", .shoulders: "Log an overhead press",
        .arms: "Log a curl or pushdown", .legs: "Log a squat or leg press",
    ]

    var body: some View {
        let color = rank.best == nil ? Palette.muted : Palette.ranks[rank.rank]
        let opens = rank.best != nil || !names.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.smooth(duration: Motion.standard)) { open.toggle() } } label: {
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack(spacing: Space.s2) {
                        Text(rank.muscle.rawValue).type(.t16).foregroundStyle(Palette.text).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(rank.best == nil ? "Unranked" : rank.name).type(.t14).fontWeight(.semibold).foregroundStyle(color)
                        if opens {
                            Image(systemName: "chevron.down").font(.system(size: IconSize.small, weight: .semibold)).foregroundStyle(Palette.muted)
                                .rotationEffect(.degrees(open ? 180 : 0))
                        }
                    }
                    RankBar(progress: rank.best == nil ? 0 : rank.progress, color: color)
                    Text(rank.best == nil ? Self.hints[rank.muscle] ?? "" : toGo(rank.rank, rank.progress)).type(.t14).foregroundStyle(Palette.muted).lineLimit(1)
                }
                .padding(Space.s4)
                .frame(minHeight: Size.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!opens)
            .accessibilityLabel("\(rank.muscle.rawValue): \(rank.best == nil ? "Unranked" : rank.name)")
            .accessibilityValue(opens ? (open ? "Open" : "Closed") : "")
            .sensoryFeedback(.selection, trigger: open)
            if open {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if let best = rank.best {
                        HStack(alignment: .top, spacing: Space.s3) {
                            stat("Best", Palette.muted, "\(liftWeight(best.kg, best.kind, unit)) × \(best.reps)", best.exercise)
                            if let next = rank.next {
                                stat("For \(Ranks.names[rank.rank + 1])", Palette.ranks[rank.rank + 1], "\(liftWeight(next.kg, best.kind, unit, target: true)) × \(next.reps)", "Same lift, same reps")
                            }
                        }
                    }
                    if !names.isEmpty { RankCounts(label: "Counts here", rows: names) }
                }
                .padding(.vertical, Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Palette.hairline.frame(height: 1) }
                .padding(.horizontal, Space.s4)
                .transition(.opacity)
            }
        }
        .raised()
    }

    private func stat(_ label: String, _ color: Color, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).type(.t12).foregroundStyle(color)
            Text(value).type(.t16).monospacedDigit().foregroundStyle(Palette.text)
            Text(detail).type(.t12).foregroundStyle(Palette.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Exercises as chips (the PWA's Chips); tapping one opens where it counts: automatically, one muscle, or nowhere.
struct RankCounts: View {
    let label: String
    let rows: [CountedName]
    @State private var choosing: CountedName?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).type(.t12).foregroundStyle(Palette.muted)
            FlowLayout(spacing: Space.s2) {
                ForEach(rows, id: \.key) { row in
                    Button { choosing = row } label: {
                        Text(row.name).type(.t14).fontWeight(.semibold).foregroundStyle(Palette.text).multilineTextAlignment(.leading)
                            .padding(.horizontal, Space.s3).padding(.vertical, Space.s1)
                            .frame(minHeight: Size.compact).raised(.control, .pill)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("\(row.name): choose where it counts")
                }
            }
        }
        .sheet(item: $choosing) { CountsFor(row: $0) }
    }
}

extension CountedName: Identifiable {
    public var id: String { key }
}

/// Where an exercise counts, on a sheet: automatic (what its name says), one muscle, or nowhere.
private struct CountsFor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let row: CountedName

    var body: some View {
        let current = row.chosen ? row.groups.first ?? LiftTable.none : ""
        let options = [(value: "", text: "Automatic: \(row.auto.isEmpty ? "not counted" : row.auto.joined(separator: ", "))")]
            + LiftTable.groups.map { (value: $0, text: $0) } + [(value: LiftTable.none, text: "Doesn’t count")]
        SheetFrame(title: row.name, subtitle: "Counts toward") {
            VStack(spacing: 0) {
                ForEach(options, id: \.value) { option in
                    Button { choose(option.value) } label: {
                        HStack(spacing: Space.s3) {
                            Text(option.text).type(.t16).foregroundStyle(Palette.text).lineLimit(1)
                            Spacer(minLength: 0)
                            if option.value == current {
                                Image(systemName: "checkmark").font(.system(size: IconSize.medium, weight: .semibold)).foregroundStyle(Palette.accent)
                            }
                        }
                        .padding(Space.s4).frame(minHeight: Size.row).contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityAddTraits(option.value == current ? .isSelected : [])
                    .overlay(alignment: .top) { if option.value != options[0].value { Palette.hairline.frame(height: 1) } }
                }
            }
            .raised()
            .padding(.top, Space.s3)
        }
    }

    /// Picking the one muscle it counts toward on its own is automatic: nothing to save.
    private func choose(_ value: String) {
        let choice: String? = value.isEmpty || row.auto == [value] ? nil : value
        let lifts = model.training.settings.lifts ?? [:]
        if choice != nil, lifts[row.key] == nil, lifts.count >= Limits.liftChoices {
            model.show("You can move up to \(Limits.grouped(Limits.liftChoices)) exercises.")
            return
        }
        model.update { training in
            var lifts = training.settings.lifts ?? [:]
            lifts[row.key] = choice
            training.settings.lifts = lifts
        }
        dismiss()
    }
}
