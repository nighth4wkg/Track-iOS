import SwiftUI
import TrackCore

extension Palette {
    /// Starter, Novice, Solid, Strong, Elite (app/styles/ranks.css).
    static let ranks: [Color] = [Color(light: 0x5F6A73, dark: 0x9AA3AB), Color(light: 0x1F6FBF, dark: 0x5AA7EC), accent,
                                 Color(light: 0x7447C9, dark: 0xB287F5), Color(light: 0x8A6A00, dark: 0xE8C35A)]
}

/// Rank: each muscle ranked from its strongest lift relative to bodyweight, the overall rank (the average place on
/// the ladder), and the closest win with the weight that gets it. Asks for bodyweight first.
struct RankPage: View {
    @Environment(AppModel.self) private var model
    @Binding var settingsOpen: Bool
    @State private var bodyweightText = ""
    @FocusState private var typing: Bool

    var body: some View {
        let training = model.training
        let unit = training.settings.unit
        Page(title: "Rank", settingsOpen: $settingsOpen) {
            if let bodyweight = training.settings.bodyweight {
                let ranks = training.sessions.muscleRanks(bodyweight: bodyweight)
                let ranked = ranks.filter { $0.best != nil }
                let score = ranked.isEmpty ? 0 : ranked.reduce(0) { $0 + Double($1.rank) + $1.progress } / Double(ranked.count)
                let overall = min(Ranks.names.count - 1, Int(score))
                Section { overallCard(ranked.isEmpty ? nil : overall, progress: score - Double(overall), bodyweight: bodyweight, unit: unit).bareRow() }
                if let closest = ranked.filter({ $0.next != nil }).max(by: { $0.progress < $1.progress }), let next = closest.next, let best = closest.best {
                    Section {
                        ListRow(icon: "scope", title: "Closest win: \(closest.muscle.rawValue) → \(Ranks.names[closest.rank + 1])",
                                detail: "\(TrainingSet.display(kg: next.kg, unit: unit)) \(unit.rawValue) × \(next.reps) on \(best.exercise) gets you there") { EmptyView() }
                            .glassRow()
                    }
                }
                Section { ForEach(ranks, id: \.muscle) { MuscleRow(rank: $0, unit: unit).glassRow() } }
            } else {
                Section { setup(unit: unit).bareRow() }
            }
        }
    }

    private func overallCard(_ overall: Int?, progress: Double, bodyweight: Double, unit: TrackCore.Settings.Unit) -> some View {
        let color = overall.map { Palette.ranks[$0] } ?? Palette.muted
        return VStack(spacing: 8) {
            Image(systemName: "medal.fill").font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(color.opacity(0.85)))
                .glass(radius: 20, fill: .clear, lifted: false)
            Text("Overall").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 4)
            Text(overall.map { Ranks.names[$0] } ?? "Unranked").font(.largeTitle.weight(.bold)).foregroundStyle(color)
            Text(overall.map { toGo($0, progress) } ?? "Log a lift to get ranked").font(.subheadline).foregroundStyle(Palette.muted)
            HStack(spacing: 6) {
                ForEach(Ranks.names.indices, id: \.self) { index in
                    VStack(spacing: 6) {
                        RankBar(progress: overall.map { index < $0 ? 1 : index == $0 ? progress : 0 } ?? 0, color: Palette.ranks[index])
                        Text(Ranks.names[index]).font(.caption2.weight(index == overall ? .bold : .regular))
                            .foregroundStyle(index == overall ? Palette.ranks[index] : Palette.muted).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glass()
        .overlay(alignment: .topTrailing) {
            Chip(text: "\(TrainingSet.display(kg: bodyweight, unit: unit)) \(unit.rawValue)").padding(14)
        }
    }

    private func setup(unit: TrackCore.Settings.Unit) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "medal").font(.system(size: 30, weight: .semibold)).foregroundStyle(Palette.text)
                .frame(width: 64, height: 64).glass(radius: 18, fill: Palette.control, lifted: false)
            Text("Unlock your ranks").font(.title3.weight(.bold)).foregroundStyle(Palette.text)
            Text("Add your bodyweight to rank each muscle.").font(.subheadline).foregroundStyle(Palette.muted)
            HStack(spacing: 8) {
                TextField("Bodyweight", text: $bodyweightText).keyboardType(.decimalPad).focused($typing)
                    .font(.body.weight(.semibold)).multilineTextAlignment(.center)
                    .frame(minHeight: 48).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.input))
                Text(unit.rawValue).foregroundStyle(Palette.muted)
            }
            Button("Save") { save(unit) }.buttonStyle(PrimaryButtonStyle())
                .disabled(TrainingSet.kilograms(from: bodyweightText, unit: unit).map { $0 >= 20 && $0 <= 400 } != true)
        }
        .padding(24).frame(maxWidth: .infinity).glass()
    }

    private func save(_ unit: TrackCore.Settings.Unit) {
        guard let kg = TrainingSet.kilograms(from: bodyweightText, unit: unit), kg >= 20, kg <= 400 else { return }
        typing = false
        withAnimation(.smooth) { model.update { $0.settings.bodyweight = kg } }
    }
}

/// "5% left to Strong", or the top.
func toGo(_ rank: Int, _ progress: Double) -> String {
    rank >= Ranks.names.count - 1 ? "Top rank" : "\(Int(((1 - progress) * 100).rounded()))% left to \(Ranks.names[rank + 1])"
}

/// A muscle: its rank, a bar toward the next, and (tapped open) the lift it's ranked on and what reaches the next.
private struct MuscleRow: View {
    let rank: MuscleRank
    let unit: TrackCore.Settings.Unit
    @State private var open = false

    var body: some View {
        let color = rank.best == nil ? Palette.muted : Palette.ranks[rank.rank]
        Button { withAnimation(.smooth(duration: 0.3)) { open.toggle() } } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(rank.muscle.rawValue).font(.headline).foregroundStyle(Palette.text)
                    Spacer()
                    Text(rank.best == nil ? "Unranked" : rank.name).font(.subheadline.weight(.bold)).foregroundStyle(color)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Palette.muted).rotationEffect(.degrees(open ? 180 : 0))
                }
                RankBar(progress: rank.progress, color: color)
                Text(rank.best == nil ? "Log a \(rank.muscle.rawValue.lowercased()) lift to rank it" : toGo(rank.rank, rank.progress))
                    .font(.subheadline).foregroundStyle(Palette.muted)
                if open, let best = rank.best {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Best: \(best.exercise), \(TrainingSet.display(kg: best.kg, unit: unit)) \(unit.rawValue) × \(best.reps)")
                        if let next = rank.next { Text("Next: \(TrainingSet.display(kg: next.kg, unit: unit)) \(unit.rawValue) × \(next.reps)") }
                    }
                    .font(.footnote).foregroundStyle(Palette.text).transition(.opacity)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: open)
    }
}

/// A rank bar: the track with the rank's colour filled to its progress.
struct RankBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        Capsule().fill(Palette.input).frame(height: 8)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule().fill(color).frame(width: max(0, min(1, progress)) * geometry.size.width)
                }
            }
            .animation(.smooth(duration: 0.6), value: progress)
    }
}
