import SwiftUI
import TrackCore

extension Palette {
    /// Starter, Novice, Solid, Strong, Elite: vivid in both themes for bars and the medal (the website's dark-theme
    /// colours, which read clearly on the light glass too); text uses `rankText`, a shade deeper in light mode.
    static let ranks: [Color] = [Color(hex: 0x9AA3AB), Color(hex: 0x4E9EF0), Color(hex: 0x2FD27A), Color(hex: 0xA77CF7), Color(hex: 0xF2BE3B)]
    static let rankText: [Color] = [Color(light: 0x6B7680, dark: 0x9AA3AB), Color(light: 0x2A7FD6, dark: 0x5AA7EC),
                                    Color(light: 0x14A35A, dark: 0x48E58D), Color(light: 0x8A55EE, dark: 0xB287F5),
                                    Color(light: 0xC99212, dark: 0xF2C14E)]
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
                let ranks = model.derived("ranks \(bodyweight)") { $0.muscleRanks(bodyweight: bodyweight) }
                let ranked = ranks.filter { $0.best != nil }
                let score = ranked.isEmpty ? 0 : ranked.reduce(0) { $0 + Double($1.rank) + $1.progress } / Double(ranked.count)
                let overall = min(Ranks.names.count - 1, Int(score))
                overallCard(ranked.isEmpty ? nil : overall, progress: score - Double(overall), bodyweight: bodyweight, unit: unit,
                            basis: ranked.isEmpty || ranked.count == ranks.count ? nil : "Based on \(ranked.count) of \(count(ranks.count, "muscle"))")
                if let closest = ranked.filter({ $0.next != nil }).max(by: { $0.progress < $1.progress }), let next = closest.next, let best = closest.best {
                    // The rank up that's nearest, and the one lift that gets it.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nearest rank up").font(.subheadline).foregroundStyle(Palette.muted)
                        Text("\(closest.muscle.rawValue) → \(Ranks.names[closest.rank + 1])").font(.headline).foregroundStyle(Palette.rankText[closest.rank + 1])
                        Text("Lift \(loadable(next.kg, unit)) × \(next.reps) on \(best.exercise)")
                            .font(.subheadline).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16).glass()
                }
                GlassList { ForEach(ranks, id: \.muscle) { MuscleRow(rank: $0, unit: unit) } }
            } else {
                setup(unit: unit)
            }
        }
    }

    private func overallCard(_ overall: Int?, progress: Double, bodyweight: Double, unit: TrackCore.Settings.Unit, basis: String?) -> some View {
        let color = overall.map { Palette.ranks[$0] } ?? Palette.muted
        let text = overall.map { Palette.rankText[$0] } ?? Palette.muted
        return VStack(spacing: 8) {
            Image(systemName: "medal.fill").font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .glass(radius: 20, fill: .clear, lifted: false)
            Text("Overall").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 4)
            Text(overall.map { Ranks.names[$0] } ?? "Unranked").font(.largeTitle.weight(.bold)).foregroundStyle(text)
            Text(overall.map { toGo($0, progress) } ?? "Log a lift to get ranked").font(.subheadline).foregroundStyle(Palette.muted)
            if let basis { Text(basis).font(.caption).foregroundStyle(Palette.muted) }
            HStack(spacing: 6) {
                ForEach(Ranks.names.indices, id: \.self) { index in
                    VStack(spacing: 6) {
                        RankBar(progress: overall.map { index < $0 || index == Ranks.names.count - 1 && index == $0 ? 1 : index == $0 ? progress : 0 } ?? 0, color: Palette.ranks[index])
                        Text(Ranks.names[index]).font(.caption2.weight(index == overall ? .bold : .regular))
                            .foregroundStyle(index == overall ? Palette.rankText[index] : Palette.muted).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glass()
        .overlay(alignment: .topTrailing) {
            Button { editBodyweight(bodyweight, unit) } label: {
                Label("\(TrainingSet.display(kg: bodyweight, unit: unit)) \(unit.rawValue)", systemImage: "pencil")
                    .font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(Palette.text)
                    .padding(.horizontal, 10).frame(minHeight: 32).glass(radius: 16, fill: Palette.control, lifted: false)
            }
            .buttonStyle(PressStyle()).padding(14)
            .accessibilityLabel("Bodyweight \(TrainingSet.display(kg: bodyweight, unit: unit)) \(unit.rawValue). Change")
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

    /// Changing the bodyweight later, in Track's dialog.
    private func editBodyweight(_ bodyweight: Double, _ unit: TrackCore.Settings.Unit) {
        model.naming = Naming(title: "Your bodyweight", message: "Ranks compare your lifts with it.",
                              name: TrainingSet.display(kg: bodyweight, unit: unit), label: "Bodyweight (\(unit.rawValue))", placeholder: unit == .kg ? "e.g. 72" : "e.g. 160", number: true, action: "Save") { text in
            guard let kg = TrainingSet.kilograms(from: text, unit: unit), kg >= 20, kg <= 400 else {
                model.message = "Enter a bodyweight between \(unit == .kg ? "20 and 400 kg" : "44 and 880 lb")."
                return
            }
            withAnimation(.smooth) { model.update { $0.settings.bodyweight = kg } }
        }
    }

    private func save(_ unit: TrackCore.Settings.Unit) {
        guard let kg = TrainingSet.kilograms(from: bodyweightText, unit: unit), kg >= 20, kg <= 400 else { return }
        typing = false
        withAnimation(.smooth) { model.update { $0.settings.bodyweight = kg } }
    }
}

/// A target as weight you can load on a bar: up to the next 2.5 kg or 5 lb ("175 lb", not "174.17 lb").
private func loadable(_ kg: Double, _ unit: TrackCore.Settings.Unit) -> String {
    let step = TrainingSet.kilograms(from: unit == .kg ? "2.5" : "5", unit: unit) ?? 2.5
    return "\(TrainingSet.display(kg: (kg / step - 1e-9).rounded(.up) * step, unit: unit)) \(unit.rawValue)"
}

/// "5% left to Strong", or the top.
func toGo(_ rank: Int, _ progress: Double) -> String {
    rank >= Ranks.names.count - 1 ? "Top rank" : "\(max(1, Int(((1 - progress) * 100).rounded(.up))))% left to \(Ranks.names[rank + 1])"
}

/// A muscle: its rank, a bar toward the next, and (tapped open) the lift it's ranked on and what reaches the next.
private struct MuscleRow: View {
    let rank: MuscleRank
    let unit: TrackCore.Settings.Unit
    @State private var open = false

    var body: some View {
        let color = rank.best == nil ? Palette.muted : Palette.ranks[rank.rank]
        let text = rank.best == nil ? Palette.muted : Palette.rankText[rank.rank]
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
            if open, let best = rank.best {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Best: \(best.exercise), \(TrainingSet.display(kg: best.kg, unit: unit)) \(unit.rawValue) × \(best.reps)")
                    if let next = rank.next { Text("Next: \(loadable(next.kg, unit)) × \(next.reps)") }
                }
                .font(.footnote).foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.smooth(duration: 0.3)) { open.toggle() } }
        .accessibilityAddTraits(.isButton)
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
