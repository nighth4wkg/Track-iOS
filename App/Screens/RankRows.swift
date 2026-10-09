import SwiftUI
import TrackCore

/// A muscle: its rank, a bar toward the next, and (tapped open) the lift it's ranked on, what reaches the next, and the
/// exercises counting toward it.
struct MuscleRow: View {
    let rank: MuscleRank
    let unit: TrackCore.Settings.Unit
    let names: [CountedName]
    @State private var open = false

    var body: some View {
        let color = rank.best == nil ? Palette.muted : Palette.ranks[rank.rank]
        let text = rank.best == nil ? Palette.muted : Palette.rankText[rank.rank]
        VStack(alignment: .leading, spacing: 10) {
            // The header is the row's button; what opens under it (the exercise chips) is outside it.
            Button { withAnimation(.smooth(duration: Motion.standard)) { open.toggle() } } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(rank.muscle.rawValue).font(.headline).foregroundStyle(Palette.text)
                        Spacer()
                        Text(rank.best == nil ? "Unranked" : rank.name).font(.subheadline.weight(.bold)).foregroundStyle(text)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
                            .scaleEffect(y: open ? -1 : 1)
                    }
                    RankBar(progress: rank.progress, color: color)
                    Text(rank.best == nil ? "Log a \(rank.muscle.rawValue.lowercased()) lift to rank it" : toGo(rank.rank, rank.progress))
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "Open" : "Closed")
            .sensoryFeedback(.selection, trigger: open)
            if open {
                VStack(alignment: .leading, spacing: 12) {
                    if let best = rank.best {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Best: \(best.exercise), \(liftWeight(best.kg, best.kind, unit)) × \(best.reps)")
                            if let next = rank.next { Text("Next: \(liftWeight(next.kg, best.kind, unit, target: true)) × \(next.reps)") }
                        }
                        .font(.footnote).foregroundStyle(Palette.text)
                    }
                    if !names.isEmpty { RankCounts(label: "Counts here", rows: names) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }
}

/// Exercises as glass chips (the website's rank-counts.tsx); tapping one opens the menu of where it counts: automatic,
/// a rank group, or nowhere.
struct RankCounts: View {
    @Environment(AppModel.self) private var model
    let label: String
    let rows: [CountedName]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
            FlowLayout(spacing: 8) { ForEach(rows, id: \.key) { chip($0) } }
        }
    }

    private func chip(_ row: CountedName) -> some View {
        let current = row.chosen ? row.groups.first ?? LiftTable.none : ""
        let options = [("", "Automatic: \(row.auto.isEmpty ? "not counted" : row.auto.joined(separator: ", "))")]
            + LiftTable.groups.map { ($0, $0) } + [(LiftTable.none, "Doesn't count")]
        return Menu {
            ForEach(options.indices, id: \.self) { index in
                let (value, title) = options[index]
                Button { choose(row, value) } label: {
                    if value == current { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            Text(row.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text).multilineTextAlignment(.leading)
                .padding(.horizontal, 16).frame(minHeight: 44).glass(radius: 22, fill: Palette.control, lifted: false)
        }
        .accessibilityLabel("\(row.name) counts for")
        .accessibilityValue(options.first { $0.0 == current }?.1 ?? "")
    }

    /// Picking the one group it counts toward on its own is automatic: nothing to save.
    private func choose(_ row: CountedName, _ value: String) {
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
    }
}
