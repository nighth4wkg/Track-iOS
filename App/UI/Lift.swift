import SwiftUI
import TrackCore

/// One exercise over time (the PWA's Lift): its estimated one-rep max by day, week or month as a line, the best set
/// and last session's volume, then its three latest workouts.
struct LiftScreen: View {
    @Environment(AppModel.self) private var model
    let name: String
    @State private var period = Period.week

    var body: some View {
        let training = model.training
        let unit = training.settings.unit
        let entries = model.derived("lift \(name)") { $0.entries(of: name) }
        let group = LiftTable.ranking(for: name, choices: training.settings.lifts ?? [:])?.groups.first ?? "Exercise"
        DeepPage {
            TitleBar(title: name, subtitle: group + dot + count(entries.count, "workout"))
            Seg(label: "Period", options: Period.allCases.map { (value: $0, text: $0.name) }, value: $period, short: true)
                .padding(.top, Space.s4)
            if entries.isEmpty {
                Text("Log this exercise in a workout to see its progress.").type(.t14).foregroundStyle(Palette.muted).padding(.top, Space.s4)
            } else {
                let points = model.derived("lift points \(name)", at: period) { $0.oneRepMaxes(of: name, per: period) }
                trend(points, unit: unit).padding(.top, Space.s4)
                HStack(spacing: Space.s3) {
                    tile("Best set", setText(Self.top(entries.flatMap(\.sets)), unit))
                    tile("Last session", weight(entries[0].sets.reduce(0) { $0 + ($1.kg ?? 0) * Double($1.reps ?? 0) }, unit), unit: unit.rawValue)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s3)
                Text("Recent sessions").type(.t20).foregroundStyle(Palette.text).padding(.top, Space.s6).accessibilityAddTraits(.isHeader)
                VStack(spacing: Space.s3) {
                    ForEach(entries.prefix(3), id: \.session.id) { entry in
                        HStack(spacing: Space.s3) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(Date(timeIntervalSince1970: Double(entry.session.finishedAt ?? 0) / 1000).formatted(.gregorian.weekday(.wide).month(.abbreviated).day()))
                                    .type(.t16).foregroundStyle(Palette.text)
                                // L+R is one set, as everywhere else.
                                Text(count(Exercise.groups(entry.sets).count, "set")).type(.t14).foregroundStyle(Palette.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(setText(Self.top(entry.sets), unit)).type(.t14).monospacedDigit().foregroundStyle(Palette.text)
                        }
                        .pad()
                        .raised()
                    }
                }
                .padding(.top, Space.s2)
            }
        }
    }

    private func trend(_ points: [(at: Int, value: Double)], unit: TrackCore.Settings.Unit) -> some View {
        let gain = points.count > 1 ? (points.last?.value ?? 0) - points[0].value : nil
        let latest = points.last?.value ?? 0
        let label = { (at: Int) in
            Date(timeIntervalSince1970: Double(at) / 1000).formatted(period == .month ? .gregorian.month(.abbreviated).year(.twoDigits) : .gregorian.month(.abbreviated).day())
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text("Estimated 1RM").type(.t14).foregroundStyle(Palette.muted)
            Text("\(weight(latest.rounded(), unit)) \(unit.rawValue)").type(.t28).monospacedDigit().foregroundStyle(Palette.text).padding(.top, Space.s2)
            Text(gain.map { "\($0 >= 0 ? "+" : "")\(weight($0.rounded(), unit)) \(unit.rawValue) over \(count(periods(from: points[0].at, to: points.last?.at ?? 0, period), period.name.lowercased()))" } ?? "One point so far")
                .type(.t14).fontWeight(.semibold).foregroundStyle(gain.map { $0 >= 0 ? Palette.accent : Palette.danger } ?? Palette.muted)
            TrendLine(values: points.map(\.value)).frame(height: Size.chart).padding(.top, Space.s4)
                .accessibilityLabel("Estimated one-rep max over time")
            if let first = points.first, let last = points.last {
                HStack {
                    Text(label(first.at)).foregroundStyle(Palette.muted)
                    Spacer()
                    Text(label(last.at)).foregroundStyle(Palette.text)
                }
                .type(.t12)
                .padding(.top, Space.s2)
            }
        }
        .pad()
        .frame(maxWidth: .infinity, alignment: .leading)
        .raised()
    }

    private func tile(_ label: String, _ value: String, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).type(.t14).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                Text(value).type(.t20).monospacedDigit().foregroundStyle(Palette.text)
                if let unit { Text(unit).type(.t14).foregroundStyle(Palette.muted) }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .pad()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .raised()
    }

    /// The heaviest set, then the most reps.
    private static func top(_ sets: [TrainingSet]) -> TrainingSet? {
        sets.max { ($0.kg ?? 0, $0.reps ?? 0) < ($1.kg ?? 0, $1.reps ?? 0) }
    }

    /// "80 kg × 8"
    private func setText(_ set: TrainingSet?, _ unit: TrackCore.Settings.Unit) -> String {
        guard let set else { return "–" }
        return "\(weight(set.kg ?? 0, unit)) \(unit.rawValue) × \(set.reps ?? 0)"
    }
}

/// The one-rep max line over three faint guides, as the PWA's SVG (its 120-high box: guides at 20, 60 and 100, the
/// line between 10 and 110, 2 kg of room above and below, a 3-wide stroke); one point sits centred.
private struct TrendLine: View {
    let values: [Double]
    private static let room = 2.0, stroke: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            for share in [1.0 / 6, 0.5, 5.0 / 6] {
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: size.height * share)); $0.addLine(to: CGPoint(x: size.width, y: size.height * share)) },
                               with: .color(Palette.line), lineWidth: 1)
            }
            let low = (values.min() ?? 0) - Self.room, high = (values.max() ?? 0) + Self.room
            let points = values.enumerated().map { index, value in
                CGPoint(x: values.count == 1 ? size.width / 2 : size.width * CGFloat(index) / CGFloat(values.count - 1),
                        y: size.height * (11 - CGFloat((value - low) / max(1, high - low)) * 10) / 12)
            }
            var line = Path()
            line.addLines(points)
            if points.count == 1, let point = points.first { line.addEllipse(in: CGRect(origin: point, size: .zero).insetBy(dx: -Self.stroke / 2, dy: -Self.stroke / 2)) }
            context.stroke(line, with: .color(Palette.accent), style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round, lineJoin: .round))
        }
    }
}
