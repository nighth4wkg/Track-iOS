import SwiftUI
import TrackCore

extension Palette {
    /// Starter, Novice, Solid, Strong, Elite, as the PWA's --rank-0 to --rank-4: bars, the emblem and their text.
    static let ranks: [Color] = [Color(hex: 0xA9B0B6), Color(hex: 0x5AA7EC), Color(hex: 0x4CC38A), Color(hex: 0xE8A93A), Color(hex: 0xB287F5)]
}

/// Rank, as the PWA's: each muscle ranked from its best lift relative to bodyweight, the overall rank (the average
/// place on the ladder) and the closest win. Asks for bodyweight first; the bodyweight button changes it.
struct RankPage: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false
    @State private var opened: Muscle?

    var body: some View {
        let training = model.training
        let unit = training.settings.unit
        let bodyweight = training.settings.bodyweight
        Page(title: "Rank", accessory: bodyweight.map { kg in
            AnyView(Button("\(TrainingSet.display(kg: kg, unit: unit)) \(unit.rawValue)") { editing = true }
                .buttonStyle(SecondaryButtonStyle(hug: true)).monospacedDigit()
                .accessibilityLabel("Bodyweight \(TrainingSet.display(kg: kg, unit: unit)) \(unit.rawValue), edit"))
        }) {
            if let bodyweight {
                let choices = training.settings.lifts ?? [:]
                let signature = choices.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
                let ranks = model.derived("ranks \(bodyweight) \(signature)") { $0.muscleRanks(bodyweight: bodyweight, choices: choices) }
                let counted = model.derived("counted \(signature)") { $0.countedNames(choices: choices) }
                VStack(alignment: .leading, spacing: 0) {
                    OverallCard(ranks: ranks, unit: unit)
                    Text("Muscles").type(.t20).foregroundStyle(Palette.text).padding(.top, Space.s6)
                    VStack(spacing: Space.s3) {
                        ForEach(ranks, id: \.muscle) { rank in
                            MuscleRow(rank: rank, unit: unit, names: counted.filter { $0.groups.contains(rank.muscle.rawValue) }, opened: $opened)
                        }
                        // Apart only when it needs you: names Track doesn't know, and ones you chose not to count.
                        let uncounted = counted.filter { $0.groups.isEmpty && (!$0.known || $0.chosen) }
                        if !uncounted.isEmpty {
                            RankCounts(label: "Not counted", rows: uncounted).padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).raised()
                        }
                    }
                    .padding(.top, Space.s2)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "rosette").font(.system(size: IconSize.regular, weight: .semibold)).foregroundStyle(Palette.accent)
                        .frame(width: Size.tile, height: Size.tile).raised(.control, .inner).accessibilityHidden(true)
                    Text("Unlock your ranks").type(.t20).foregroundStyle(Palette.text).padding(.top, Space.s3)
                    Text("Ranks compare your best lifts with your bodyweight.").type(.t14).foregroundStyle(Palette.muted)
                    BodyweightForm {}.padding(.top, Space.s4)
                }
                .padding(Space.s4)
                .raised()
            }
        }
        .sheet(isPresented: $editing) {
            SheetFrame(title: "Bodyweight", closeLabel: "Cancel") { BodyweightForm { editing = false }.padding(.top, Space.s3) }
        }
    }
}

/// The overall rank: the emblem in its colour beside the rank and how far to the next, the ladder of five bars, and
/// the closest win with the lift that gets it.
private struct OverallCard: View {
    let ranks: [MuscleRank]
    let unit: TrackCore.Settings.Unit

    var body: some View {
        let ranked = ranks.filter { $0.best != nil }
        let top = Ranks.names.count - 1
        let score = ranked.isEmpty ? 0 : ranked.reduce(0) { $0 + min(Double(top), Double($1.rank) + $1.progress) } / Double(ranked.count)
        let overall = min(top, Int(score))
        let part = overall == top ? 1 : score - Double(overall)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s4) {
                Image(systemName: "rosette").font(.system(size: IconSize.emblem, weight: .semibold))
                    .foregroundStyle(ranked.isEmpty ? Palette.muted : Palette.ranks[overall])
                    .frame(width: Size.emblem, height: Size.emblem).raised(.control, .circle).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Overall").type(.t14).foregroundStyle(Palette.muted)
                    if ranked.isEmpty {
                        Text("Unranked").type(.t20).foregroundStyle(Palette.text)
                        Text("Log a lift to get ranked").type(.t14).foregroundStyle(Palette.muted)
                    } else {
                        Text(Ranks.names[overall]).type(.t28).foregroundStyle(Palette.ranks[overall])
                        Text(toGo(overall, part)).type(.t14).foregroundStyle(Palette.muted).lineLimit(1)
                        if ranked.count < ranks.count {
                            Text("Based on \(ranked.count) of \(ranks.count) muscles").type(.t12).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                    }
                }
            }
            // The ladder: full below your rank, filling through yours (the top rank is full), empty above.
            HStack(spacing: Space.s1) {
                ForEach(Ranks.names.indices, id: \.self) { index in
                    RankBar(progress: ranked.isEmpty || index > overall ? 0 : index < overall ? 1 : part, color: Palette.ranks[index])
                }
            }
            .padding(.top, Space.s4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ranked.isEmpty ? "No ranked lifts yet" : "\(Ranks.names[overall]), \(Int(part * 100))% to the next rank")
            HStack(spacing: Space.s1) {
                ForEach(Ranks.names.indices, id: \.self) { index in
                    Text(Ranks.names[index]).type(.t12).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(!ranked.isEmpty && index == overall ? Palette.ranks[index] : Palette.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, Space.s2)
            .accessibilityHidden(true)
            if let win = ranked.filter({ $0.next != nil }).max(by: { $0.progress < $1.progress }), let next = win.next, let best = win.best {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Closest win: \(win.muscle.rawValue) to \(Ranks.names[win.rank + 1])").type(.t14).foregroundStyle(Palette.muted)
                    Text("\(liftWeight(next.kg, best.kind, unit, target: true)) × \(next.reps) on \(best.exercise)").type(.t16).foregroundStyle(Palette.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Space.s3)
                .overlay(alignment: .top) { Palette.hairline.frame(height: 1) }
                .padding(.top, Space.s3)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raised()
    }
}

/// Bodyweight, as the PWA's form: the field full width and Save under it.
struct BodyweightForm: View {
    @Environment(AppModel.self) private var model
    let done: () -> Void
    @State private var text = ""

    var body: some View {
        let unit = model.training.settings.unit
        let kg = TrainingSet.kilograms(from: text, unit: unit).flatMap { Limits.bodyweight.contains($0) ? $0 : nil }
        let save = {
            guard let kg else { return }
            model.update { $0.settings.bodyweight = kg }
            done()
        }
        VStack(alignment: .leading, spacing: Space.s4) {
            Field(placeholder: "Bodyweight in \(unit.rawValue)", text: $text, label: "Your bodyweight in \(unit.rawValue)", keyboard: .decimalPad, submit: save)
            if kg == nil, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Enter \(Limits.wholeRange(Limits.bodyweight, unit)).").type(.t14).foregroundStyle(Palette.danger)
            }
            Button("Save", action: save).buttonStyle(PrimaryButtonStyle()).disabled(kg == nil)
        }
        .onAppear { text = model.training.settings.bodyweight.map { TrainingSet.display(kg: $0, unit: unit) } ?? "" }
    }
}

/// A set's weight as it reads for its lift (the website's rank-format.ts): "80 kg", or on bodyweight lifts "Bodyweight",
/// "BW + 20 kg", "BW − 20 kg". A target is weight you can load: to the next 2.5 kg or 5 lb ("175 lb", not "174.17 lb"),
/// never short of the goal (assistance rounds down).
func liftWeight(_ kg: Double, _ kind: LoadKind, _ unit: TrackCore.Settings.Unit, target: Bool = false) -> String {
    let step = TrainingSet.kilograms(from: unit == .kg ? "2.5" : "5", unit: unit) ?? 2.5
    let shown = !target ? kg : kind == .assisted ? (kg / step + 1e-9).rounded(.down) * step : (kg / step - 1e-9).rounded(.up) * step
    let value = "\(TrainingSet.display(kg: shown, unit: unit)) \(unit.rawValue)"
    if kind == .weight { return value }
    return shown <= 0 ? "Bodyweight" : "BW \(kind == .assisted ? "−" : "+") \(value)"
}

/// "8% left to Strong" (counting down keeps the goal close, never 0% short of it), "Just reached Strong", or the top.
func toGo(_ rank: Int, _ progress: Double) -> String {
    rank >= Ranks.names.count - 1 ? "Top rank"
        : progress < 0.01 ? "Just reached \(Ranks.names[rank])"
        : "\(max(1, Int(((1 - progress) * 100).rounded(.up))))% left to \(Ranks.names[rank + 1])"
}

/// A rank bar: the track with the rank's colour filled to its progress.
struct RankBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        Color.clear.frame(height: Size.bar).sunk(.pill)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule().fill(color).frame(width: max(0, min(1, progress)) * geometry.size.width)
                }
            }
            .clipShape(Capsule())
            .animation(.smooth(duration: Motion.slow), value: progress)
    }
}
