import SwiftUI
import TrackCore

/// Rank's "What counts" (the website's components/rank-lifts.tsx): each exercise you've logged, what it trains, and a
/// menu to choose what it counts as: a lift, "Doesn't count", or back to what its name says.
struct RankLifts: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    struct Row {
        let key: String
        let name: String
        let auto: Detection
        let found: Detection
        let choice: String?
        var unknown: Bool { if case .unknown = found { true } else { false } }
    }

    struct Pick: Identifiable {
        let id: String
        let lifts: [Lift]
    }

    /// Every lift to pick from, under the muscle it mainly trains.
    private static let picks: [Pick] = LiftTable.parts
        .map { part in Pick(id: part.part, lifts: LiftTable.lifts.filter { $0.part == part.part }) }.filter { !$0.lifts.isEmpty }

    /// One row per name (as keyed), names it doesn't know first: they're the ones to fix.
    static func rows(_ sessions: [Session], _ choices: [String: String]) -> [Row] {
        var names: [String: String] = [:]
        for session in sessions { for exercise in session.exercises { names[LiftTable.nameKey(exercise.name)] = exercise.name } }
        return names.map { key, name in
            Row(key: key, name: name, auto: LiftTable.detect(name), found: LiftTable.lift(for: name, choices: choices), choice: choices[key])
        }
        .sorted { ($0.unknown ? 0 : 1, $0.name.lowercased()) < ($1.unknown ? 0 : 1, $1.name.lowercased()) }
    }

    var body: some View {
        let choices = model.training.settings.lifts ?? [:]
        let signature = choices.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
        let rows = model.derived("lift rows \(signature)") { Self.rows($0, choices) }
        if !rows.isEmpty {
            let unknown = rows.filter(\.unknown).count
            GlassList {
                Button { withAnimation(.smooth(duration: Motion.standard)) { open.toggle() } } label: {
                    HStack {
                        Text("What counts").font(.headline).foregroundStyle(Palette.text)
                        Spacer()
                        Text(unknown > 0 ? "\(unknown) not recognised" : count(rows.count, "exercise"))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
                            .scaleEffect(y: open ? -1 : 1)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(open ? "Open" : "Closed")
                .sensoryFeedback(.selection, trigger: open)
                if open { ForEach(rows, id: \.key) { row in rowView(row) } }
            }
        }
    }

    private func rowView(_ row: Row) -> some View {
        let autoLabel: String
        switch row.auto {
        case .lift(let lift): autoLabel = lift.name
        case .ignore: autoLabel = "Not counted"
        case .unknown: autoLabel = "Choose"
        }
        let current = row.choice == "none" ? "Doesn't count" : row.choice.flatMap { LiftTable.lift(id: $0)?.name } ?? autoLabel
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.body.weight(.semibold)).foregroundStyle(Palette.text)
                Text(Self.describe(row.found, chosen: row.choice != nil)).font(.subheadline).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
            Menu {
                pick(autoLabel, on: row.choice == nil) { choose(row.key, nil) }
                ForEach(Self.picks) { group in
                    Section(group.id) {
                        ForEach(group.lifts, id: \.id) { lift in pick(lift.name, on: row.choice == lift.id) { choose(row.key, lift.id) } }
                    }
                }
                pick("Doesn't count", on: row.choice == "none") { choose(row.key, "none") }
            } label: {
                HStack(spacing: 6) {
                    Text(current).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                }
                .font(.body).foregroundStyle(Palette.muted)
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("\(row.name) counts as \(current)")
        }
        .transition(.opacity)
    }

    @ViewBuilder private func pick(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { if on { Label(label, systemImage: "checkmark") } else { Text(label) } }
    }

    /// What a name counts as, in a few words: its muscle and helpers, or why it doesn't count.
    static func describe(_ found: Detection, chosen: Bool) -> String {
        switch found {
        case .unknown: "Not recognised"
        case .ignore: chosen ? "Doesn't count" : "Not strength work"
        case .lift(let lift): ([lift.part] + lift.helps).joined(separator: ", ") + (lift.at == nil ? " · not ranked" : "")
        }
    }

    /// A name's choice: a lift id, "none", or nil to go back to what the name says.
    private func choose(_ key: String, _ choice: String?) {
        let lifts = model.training.settings.lifts ?? [:]
        if choice != nil, lifts[key] == nil, lifts.count >= Limits.liftChoices {
            model.show("You can choose for up to \(Limits.grouped(Limits.liftChoices)) exercises.")
            return
        }
        model.update { training in
            var lifts = training.settings.lifts ?? [:]
            lifts[key] = choice
            training.settings.lifts = lifts
        }
    }
}
