import SwiftUI
import TrackCore

/// Progress, as the PWA's: pick a period (D W M) and a measure; see it against the same moment of the last period,
/// bar by bar, then streak, level and badges, and your heaviest lifts (tap one for its page).
struct ProgressPage: View {
    @Environment(AppModel.self) private var model
    @State private var xpHelp = false
    @State private var quests = false
    @State private var lift: String?
    @AppStorage("track.volumePeriod") private var period = Period.week
    @AppStorage("track.measure") private var tally = Tally.volume

    var body: some View {
        let training = model.training
        let now = nowMillis()
        let records = model.derived("records") { Array($0.personalRecords.prefix(3)) }
        Page(title: "Progress", accessory: AnyView(Seg(label: "Period", options: Period.allCases.map { (value: $0, text: $0.name) }, value: $period, short: true))) {
            VStack(alignment: .leading, spacing: 0) {
                Seg(label: "Measure", options: Tally.allCases.map { (value: $0, text: $0.rawValue) }, value: $tally)
                chart(training, now: now).padding(.top, Space.s3)
                HStack(spacing: Space.s3) {
                    tile("Streak", "\(model.derived("streak \(dayKey(now))") { $0.weeklyStreak(at: now) })", unit: "wk")
                    let level = model.derived("xp") { Experience.progress(of: $0) }.level
                    Button { xpHelp = true } label: { tile("Level", "\(level)") }
                        .buttonStyle(PressStyle()).accessibilityLabel("Level \(level). How XP works")
                    let earned = model.derived("award count") { $0.questAwards.count }
                    Button { quests = true } label: { tile("Badges", "\(earned)", unit: "/\(Quest.all.count)", tight: true) }
                        .buttonStyle(PressStyle()).accessibilityLabel("\(earned) of \(Quest.all.count) achievements. Show all")
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s3)
                if !records.isEmpty {
                    Text("Personal records").type(.t20).foregroundStyle(Palette.text).padding(.top, Space.s6)
                    VStack(spacing: Space.s3) {
                        ForEach(records, id: \.name) { record in
                            Button { lift = record.name } label: {
                                HStack(spacing: Space.s3) {
                                    Text(record.name).type(.t16).foregroundStyle(Palette.text).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text("\(weight(record.kg, training.settings.unit)) \(training.settings.unit.rawValue)").type(.t14).monospacedDigit().foregroundStyle(Palette.text)
                                    Image(systemName: "chevron.right").font(.system(size: IconSize.small, weight: .semibold)).foregroundStyle(Palette.muted)
                                }
                                .padding(Space.s4).raised().contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .padding(.top, Space.s2)
                }
            }
            .navigationDestination(item: $lift) { LiftPage(name: $0) }
        }
        .sheet(isPresented: $xpHelp) { XpHelp().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $quests) { QuestList().trackOverlays() }
    }

    private func chart(_ training: Training, now: Int) -> some View {
        let unit = training.settings.unit
        let result = model.derived("tally \(tally) \(period) \(now / 60_000)") { $0.change(of: tally, per: period, at: now) }
        let bars = model.derived("bars \(tally) \(period) \(now / 60_000)") { $0.bars(of: tally, per: period, at: now) }
        let top = max(1, bars.flatMap { [$0.now, $0.last] }.max() ?? 1)
        let note = result.value == 0 ? "Nothing logged \(period.now) yet" : result.change.map { "\($0 >= 0 ? "+" : "")\($0)% vs \(period.last)" } ?? "Nothing \(period.last) to compare"
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: bars.count)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(tally.rawValue) \(period.now)").type(.t14).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                Text(tally == .volume ? weight(result.value, unit) : Int(result.value).formatted()).type(.t28).monospacedDigit().contentTransition(.numericText())
                Text(tally == .volume ? unit.rawValue : tally == .time ? "min" : tally.rawValue.lowercased()).type(.t14).foregroundStyle(Palette.muted)
            }
            .foregroundStyle(Palette.text)
            .padding(.top, Space.s2)
            Text(note).type(.t14).fontWeight(.semibold)
                .foregroundStyle(result.value == 0 || result.change == nil ? Palette.muted : result.change! >= 0 ? Palette.accent : Palette.danger)
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    HStack(alignment: .bottom, spacing: Space.s1) {
                        column(bar.last / top, fill: AnyShapeStyle(Palette.previous), always: true)
                        column(bar.now / top, fill: AnyShapeStyle(LinearGradient(colors: Surface.green.shade, startPoint: .top, endPoint: .bottom)), always: false)
                    }
                    .frame(height: Size.chart, alignment: .bottom)
                }
            }
            .padding(.top, Space.s4)
            .animation(.smooth(duration: Motion.standard), value: bars.map(\.now) + bars.map(\.last))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(tally.rawValue) by \(period == .month ? "week" : "day"), against the period before")
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    Text(bar.label).type(.t12).foregroundStyle(bar.today ? Palette.text : Palette.muted)
                }
            }
            .padding(.top, Space.s2)
            .accessibilityHidden(true)
            HStack(spacing: Space.s4) {
                key(period.now.prefix(1).uppercased() + period.now.dropFirst(), Palette.accent)
                key(period.last.prefix(1).uppercased() + period.last.dropFirst(), Palette.previous)
            }
            .padding(.top, Space.s3)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raised()
    }

    /// One bar: at least a sliver while it has anything (the last period's always shows).
    private func column(_ share: Double, fill: AnyShapeStyle, always: Bool) -> some View {
        Corner.small.shape.fill(fill)
            .frame(width: Size.chartBar, height: share > 0 || always ? max(Space.s1, Size.chart * share) : 0)
    }

    private func key(_ text: String, _ color: Color) -> some View {
        HStack(spacing: Space.s1) {
            RoundedRectangle(cornerRadius: Radius.small / 2).fill(color).frame(width: Space.s2, height: Space.s2)
            Text(text).type(.t12).foregroundStyle(Palette.muted)
        }
    }

    private func tile(_ label: String, _ value: String, unit: String? = nil, tight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).type(.t14).foregroundStyle(Palette.muted).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: tight ? 0 : Space.s1) {
                Text(value).type(.t20).monospacedDigit().foregroundStyle(Palette.text)
                if let unit { Text(unit).type(.t14).foregroundStyle(Palette.muted) }
            }
            .lineLimit(1)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .raised()
    }
}

extension Period {
    var name: String { self == .day ? "Day" : self == .week ? "Week" : "Month" }
    /// "today", "this week", "this month".
    var now: String { self == .day ? "today" : "this \(name.lowercased())" }
    var last: String { self == .day ? "yesterday" : "last \(name.lowercased())" }
}
