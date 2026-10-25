import SwiftUI
import TrackCore

/// Rank (the PWA's): each muscle ranked from its best lift relative to bodyweight, the overall rank (the average place
/// on the ladder) and the closest win. Asks for bodyweight first; the bodyweight button changes it.
struct RankScreen: View {
    @Environment(AppModel.self) private var model
    @State private var opened: Muscle?

    var body: some View {
        let training = model.training
        let unit = training.settings.unit
        let bodyweight = training.settings.bodyweight
        TabPage {
            TabHead(title: "Rank") {
                if let bodyweight {
                    let text = "\(TrainingSet.display(kg: bodyweight, unit: unit)) \(unit.rawValue)"
                    Button(text) {
                        model.present(SheetFrame(title: "Bodyweight", closeLabel: "Cancel") { BodyweightForm(closes: true).padding(.top, Space.s3) })
                    }
                    .buttonStyle(SecondaryStyle(hug: true)).monospacedDigit()
                    .accessibilityLabel("Bodyweight \(text), edit")
                }
            }
            if let bodyweight {
                let choices = training.settings.lifts ?? [:]
                let signature = choices.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
                let ranks = model.derived("ranks \(bodyweight) \(signature)") { $0.muscleRanks(bodyweight: bodyweight, choices: choices) }
                let counted = model.derived("counted \(signature)") { $0.countedNames(choices: choices) }
                // Apart only when it needs you: names Track doesn't know, and ones you chose not to count.
                let uncounted = counted.filter { $0.groups.isEmpty && (!$0.known || $0.chosen) }
                OverallCard(ranks: ranks, unit: unit).padding(.top, Space.s4)
                Text("Muscles").type(.t20).foregroundStyle(Palette.text).padding(.top, Space.s6).accessibilityAddTraits(.isHeader)
                VStack(spacing: Space.s3) {
                    ForEach(ranks, id: \.muscle) { rank in
                        MuscleRow(rank: rank, unit: unit, names: counted.filter { $0.groups.contains(rank.muscle.rawValue) }, opened: $opened)
                    }
                }
                .padding(.top, Space.s2)
                if !uncounted.isEmpty {
                    Chips(label: "Not counted", rows: uncounted).pad().frame(maxWidth: .infinity, alignment: .leading).raised().padding(.top, Space.s3)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Icon.rank.image().foregroundStyle(Palette.accent)
                        .frame(width: Size.tile, height: Size.tile).raised(.control, .inner).accessibilityHidden(true)
                    Text("Unlock your ranks").type(.t20).foregroundStyle(Palette.text).padding(.top, Space.s3)
                    Text("Ranks compare your best lifts with your bodyweight.").type(.t14).foregroundStyle(Palette.muted)
                    BodyweightForm(closes: false).padding(.top, Space.s4)
                }
                .pad()
                .frame(maxWidth: .infinity, alignment: .leading)
                .raised()
                .padding(.top, Space.s4)
            }
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
                Icon.rank.image(IconSize.emblem)
                    .foregroundStyle(ranked.isEmpty ? Palette.muted : Palette.ranks[overall])
                    .frame(width: Size.emblem, height: Size.emblem).raised(.control, .pill).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Overall").type(.t14).foregroundStyle(Palette.muted)
                    if ranked.isEmpty {
                        Text("Unranked").type(.t20).foregroundStyle(Palette.text)
                        Text("Log a lift to get ranked").type(.t14).foregroundStyle(Palette.muted)
                    } else {
                        Text(Ranks.names[overall]).type(.t28).foregroundStyle(Palette.ranks[overall])
                        Text(toGo(overall, part)).type(.t14).foregroundStyle(Palette.muted)
                        if ranked.count < ranks.count {
                            Text("Based on \(ranked.count) of \(ranks.count) muscles").type(.t12).foregroundStyle(Palette.muted)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The ladder: full below your rank, filling through yours (the top rank is full), empty above.
            HStack(spacing: Space.s1) {
                ForEach(Ranks.names.indices, id: \.self) { index in
                    Bar(value: ranked.isEmpty || index > overall ? 0 : index < overall ? 1 : part, color: Palette.ranks[index])
                }
            }
            .padding(.top, Space.s4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ranked.isEmpty ? "No ranked lifts yet" : "\(Ranks.names[overall]), \(Int((part * 100).rounded()))% to the next rank")
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
                .overlay(alignment: .top) { Palette.line.frame(height: 1) }
                .padding(.top, Space.s3)
            }
        }
        .pad()
        .frame(maxWidth: .infinity, alignment: .leading)
        .raised()
    }
}

/// A muscle on its own card: its name and rank, a bar toward the next, how far that is (or what to log); tapped open,
/// its best lift beside what reaches the next rank, and the exercises counting toward it. One open at a time.
private struct MuscleRow: View {
    let rank: MuscleRank
    let unit: TrackCore.Settings.Unit
    let names: [CountedName]
    @Binding var opened: Muscle?

    /// What to log to rank a muscle that has nothing yet.
    private static let hints: [Muscle: String] = [
        .chest: "Log a bench press", .back: "Log a row or pulldown", .shoulders: "Log an overhead press",
        .arms: "Log a curl or pushdown", .legs: "Log a squat or leg press",
    ]

    var body: some View {
        let open = opened == rank.muscle
        let color = rank.best == nil ? Palette.muted : Palette.ranks[rank.rank]
        let opens = rank.best != nil || !names.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            Button { opened = open ? nil : rank.muscle } label: {
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack(spacing: Space.s2) {
                        Text(rank.muscle.rawValue).type(.t16).foregroundStyle(Palette.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(rank.best == nil ? "Unranked" : rank.name).type(.t14).fontWeight(.semibold).foregroundStyle(color)
                        if opens { (open ? Icon.up : Icon.down).image(IconSize.small).foregroundStyle(Palette.muted) }
                    }
                    Bar(value: rank.best == nil ? 0 : rank.progress, color: color)
                    Text(rank.best == nil ? Self.hints[rank.muscle] ?? "" : toGo(rank.rank, rank.progress)).type(.t14).foregroundStyle(Palette.muted)
                }
                .pad()
                .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowStyle())
            .disabled(!opens)
            .accessibilityLabel("\(rank.muscle.rawValue): \(rank.best == nil ? "Unranked" : rank.name)")
            .accessibilityValue(opens ? (open ? "Open" : "Closed") : "")
            .sensoryFeedback(.selection, trigger: open)
            if open {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if let best = rank.best {
                        // Two equal columns, as the PWA's grid2: Best keeps its half when there is no next rank.
                        HStack(alignment: .top, spacing: Space.s3) {
                            stat("Best", Palette.muted, "\(liftWeight(best.kg, best.kind, unit)) × \(best.reps)", best.exercise)
                            if let next = rank.next {
                                stat("For \(Ranks.names[rank.rank + 1])", Palette.ranks[rank.rank + 1], "\(liftWeight(next.kg, best.kind, unit, target: true)) × \(next.reps)", "Same lift, same reps")
                            } else {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                            }
                        }
                    }
                    if !names.isEmpty { Chips(label: "Counts here", rows: names) }
                }
                .padding(.vertical, Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Palette.line.frame(height: 1) }
                .padding(.horizontal, Space.s4)
            }
        }
        .clipShape(Corner.card.shape)
        .raised()
    }

    private func stat(_ label: String, _ color: Color, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).type(.t12).foregroundStyle(color)
            Text(value).type(.t16).monospacedDigit().foregroundStyle(Palette.text)
            Text(detail).type(.t12).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Exercises as chips; tapping one asks where it counts: automatically, one muscle, or nowhere.
private struct Chips: View {
    @Environment(AppModel.self) private var model
    let label: String
    let rows: [CountedName]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).type(.t12).foregroundStyle(Palette.muted)
            FlowLayout(spacing: Space.s2) {
                ForEach(rows, id: \.key) { row in
                    Button { model.present(CountsFor(row: row)) } label: {
                        Text(row.name).type(.t14).fontWeight(.semibold).foregroundStyle(Palette.text).multilineTextAlignment(.leading)
                            .padding(.horizontal, Space.s3).padding(.vertical, Space.s1)
                            .frame(minHeight: Size.compact).raised(.control, .pill)
                    }
                    .buttonStyle(CardStyle())
                    .accessibilityLabel("\(row.name): choose where it counts")
                }
            }
        }
    }
}

/// Where an exercise counts, on a sheet: automatic (what its name says), one muscle, or nowhere.
private struct CountsFor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeSheet) private var close
    let row: CountedName

    var body: some View {
        let current = row.chosen ? row.groups.first ?? LiftTable.none : ""
        let options = [(value: "", text: "Automatic: \(row.auto.isEmpty ? "not counted" : row.auto.joined(separator: ", "))")]
            + LiftTable.groups.map { (value: $0, text: $0) } + [(value: LiftTable.none, text: "Doesn’t count")]
        SheetFrame(title: row.name, subtitle: "Counts toward") {
            RowCard {
                ForEach(options, id: \.value) { option in
                    Button { choose(option.value) } label: {
                        Row(title: option.text) {
                            if option.value == current { Icon.check.image(IconSize.medium).foregroundStyle(Palette.accent) }
                        }
                    }
                    .buttonStyle(RowStyle())
                    .accessibilityAddTraits(option.value == current ? .isSelected : [])
                }
            }
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
        close()
    }
}

/// Bodyweight: the field full width and Save under it. On a sheet, saving closes it.
struct BodyweightForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeSheet) private var close
    let closes: Bool
    @State private var text = ""

    var body: some View {
        let unit = model.training.settings.unit
        let kg = TrainingSet.kilograms(from: text, unit: unit).flatMap { Limits.bodyweight.contains($0) ? $0 : nil }
        let save = {
            guard let kg else { return }
            model.update { $0.settings.bodyweight = kg }
            if closes { close() }
        }
        VStack(alignment: .leading, spacing: Space.s4) {
            Field(placeholder: "Bodyweight in \(unit.rawValue)", text: $text, label: "Your bodyweight in \(unit.rawValue)", keyboard: .decimalPad, submit: save)
            if kg == nil, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Enter \(Limits.wholeRange(Limits.bodyweight, unit)).").type(.t14).foregroundStyle(Palette.danger)
            }
            Button("Save", action: save).buttonStyle(PrimaryStyle()).disabled(kg == nil)
        }
        .onAppear { text = model.training.settings.bodyweight.map { TrainingSet.display(kg: $0, unit: unit) } ?? "" }
    }
}

/// A set's weight as it reads for its lift: "80 kg", or on bodyweight lifts "Bodyweight", "BW + 20 kg", "BW − 20 kg".
/// A target is weight you can load: to the next 2.5 kg or 5 lb, never short of the goal (assistance rounds down).
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

/// Chips in rows, wrapping to the next row when one doesn't fit.
struct FlowLayout: Layout {
    var spacing = Space.s2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing; line = max(line, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; line = max(line, size.height)
        }
    }
}
