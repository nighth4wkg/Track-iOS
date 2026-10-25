import SwiftUI
import TrackCore

/// Progress (the PWA's): pick a period (D W M) and a measure; see it against the same moment of the last period, bar
/// by bar, then streak, level and badges, and your heaviest lifts (tap one for its page).
struct ProgressScreen: View {
    @Environment(AppModel.self) private var model
    @AppStorage("track.volumePeriod") private var period = Period.week
    @AppStorage("track.measure") private var tally = Tally.volume

    var body: some View {
        let training = model.training
        let now = nowMillis()
        let records = model.derived("records") { Array($0.personalRecords.prefix(3)) }
        TabPage {
            TabHead(title: "Progress") {
                Seg(label: "Period", options: Period.allCases.map { (value: $0, text: $0.name) }, value: $period, short: true)
            }
            Seg(label: "Measure", options: Tally.allCases.map { (value: $0, text: $0.rawValue) }, value: $tally).padding(.top, Space.s4)
            chart(training, now: now).padding(.top, Space.s3)
            HStack(spacing: Space.s3) {
                tile("Streak", "\(model.derived("streak \(dayKey(now))") { $0.weeklyStreak(at: now) })", unit: "wk")
                let level = model.derived("xp") { Experience.progress(of: $0) }.level
                Button { model.present(XpHelp()) } label: { tile("Level", "\(level)") }
                    .buttonStyle(CardStyle()).accessibilityLabel("Level \(level). How XP works")
                let earned = model.derived("award count") { $0.questAwards.count }
                Button { model.present(QuestList(), tall: true) } label: { tile("Badges", "\(earned)", unit: "/\(Quest.all.count)", tight: true) }
                    .buttonStyle(CardStyle()).accessibilityLabel("\(earned) of \(Quest.all.count) achievements. Show all")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Space.s3)
            if !records.isEmpty {
                Text("Personal records").type(.t20).foregroundStyle(Palette.text).padding(.top, Space.s6).accessibilityAddTraits(.isHeader)
                VStack(spacing: Space.s3) {
                    ForEach(records, id: \.name) { record in
                        Button { model.open(.lift(record.name)) } label: {
                            HStack(spacing: Space.s3) {
                                Text(record.name).type(.t16).foregroundStyle(Palette.text).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(weight(record.kg, training.settings.unit)) \(training.settings.unit.rawValue)").type(.t14).monospacedDigit().foregroundStyle(Palette.text)
                                Icon.next.image(IconSize.small).foregroundStyle(Palette.muted)
                            }
                            .pad().raised().contentShape(Rectangle())
                        }
                        .buttonStyle(CardStyle())
                    }
                }
                .padding(.top, Space.s2)
            }
        }
    }

    private func chart(_ training: Training, now: Int) -> some View {
        let unit = training.settings.unit
        let result = model.derived("tally \(tally) \(period) \(now / 60_000)") { $0.change(of: tally, per: period, at: now) }
        let bars = model.derived("bars \(tally) \(period) \(now / 60_000)") { $0.bars(of: tally, per: period, at: now) }
        let top = max(1, bars.flatMap { [$0.now, $0.last] }.max() ?? 1)
        let note = result.value == 0 ? "Nothing logged \(period.now) yet" : result.change.map { "\($0 >= 0 ? "+" : "")\($0)% vs \(period.last)" } ?? "Nothing \(period.last) to compare"
        let tint = result.value == 0 ? Palette.muted : result.change.map { $0 >= 0 ? Palette.accent : Palette.danger } ?? Palette.muted
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: max(1, bars.count))
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(tally.rawValue) \(period.now)").type(.t14).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                Text(tally == .volume ? weight(result.value, unit) : Int(result.value).formatted()).type(.t28).monospacedDigit()
                Text(tally == .volume ? unit.rawValue : tally == .time ? "min" : tally.rawValue.lowercased()).type(.t14).foregroundStyle(Palette.muted)
            }
            .foregroundStyle(Palette.text)
            .padding(.top, Space.s2)
            Text(note).type(.t14).fontWeight(.semibold).foregroundStyle(tint)
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
        .pad()
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

/// "How XP works" (the PWA's): your level and its bar, the rules, then what the latest workout earned. Every number
/// comes from the XP rules, so the text can't drift from them.
struct XpHelp: View {
    @Environment(AppModel.self) private var model
    private static let dailyCap = Experience.dailyStart + Experience.perSet * Experience.dailySetCap
    private static let rules = [
        ("First set of the day", "+\(Experience.dailyStart) XP", "Starts each training day."),
        ("Each extra set", "+\(Experience.perSet) XP", "Up to \(dailyCap) XP a day. L + R is one set."),
        ("Achievements", "Bonus XP", "Paid once, on top of the daily limit."),
        ("Levels", "\(Experience.requirement(for: 1))–\(Experience.maxRequirement) XP",
         "+\(Experience.requirement(for: 2) - Experience.requirement(for: 1)) XP per level."),
        ("Rest days", "No loss", "Resting never costs XP."),
    ]

    var body: some View {
        let sessions = model.training.sessions
        let level = Experience.progress(of: sessions)
        let latest = Experience.rewards(of: sessions).last
        SheetFrame(title: "How XP works") {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Text("Level \(level.level)").type(.t16).foregroundStyle(Palette.text).frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(level.current)/\(level.required) XP").type(.t14).monospacedDigit().foregroundStyle(Palette.muted)
                }
                Bar(value: Double(level.current) / Double(max(1, level.required))).accessibilityLabel("Level \(level.level + 1) progress")
            }
            .pad()
            .raised()
            .padding(.top, Space.s3)
            RowCard {
                ForEach(Self.rules, id: \.0) { rule in row(rule.0, rule.1, rule.2) }
                if let (session, training) = latest {
                    let bonus = (session.questAwards ?? []).reduce(0) { $0 + $1.xp }
                    row("Latest workout", "+\(training + bonus) XP", "\(training) training + \(bonus) achievements")
                }
            }
            .padding(.top, Space.s3)
        }
    }

    private func row(_ rule: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s3) {
                Text(rule).type(.t16).foregroundStyle(Palette.text).frame(maxWidth: .infinity, alignment: .leading)
                Text(value).type(.t14).monospacedDigit().foregroundStyle(Palette.accent)
            }
            Text(detail).type(.t14).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Every achievement (the PWA's): how many are done, then each with a tile (✓ once done), what it asks, its XP and
/// difficulty, and the workout that earned it.
struct QuestList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeSheet) private var close

    var body: some View {
        let sessions = model.training.sessions
        let awards = sessions.questAwards
        let cap = Experience.dailyStart + Experience.perSet * Experience.dailySetCap
        SheetFrame(title: "Achievements") {
            Text("\(awards.count) of \(Quest.all.count) completed. Achievement XP is paid once, outside the \(cap) XP daily training limit.")
                .type(.t14).foregroundStyle(Palette.muted).padding(.top, Space.s2)
            RowCard {
                ForEach(Quest.all) { quest in
                    let award = awards[quest.id]
                    HStack(alignment: .top, spacing: Space.s3) {
                        Image(systemName: award == nil ? "rosette" : Icon.check.rawValue).font(.system(size: IconSize.medium, weight: .bold))
                            .foregroundStyle(award == nil ? Palette.muted : Palette.onGreen)
                            .frame(width: Size.tile, height: Size.tile)
                            .raised(award == nil ? .control : .green, .inner)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(quest.title).type(.t16).foregroundStyle(Palette.text)
                            Text(quest.description).type(.t14).foregroundStyle(Palette.muted)
                            Text("\(Text("\(award == nil ? "" : "+")\(quest.xp) XP").foregroundStyle(award == nil ? Palette.muted : Palette.accent))\(dot)\(quest.difficulty)")
                                .type(.t12).foregroundStyle(Palette.muted)
                            if let award, sessions.contains(where: { $0.id == award.sessionId }) {
                                Button { close(); model.open(.session(award.sessionId)) } label: {
                                    HStack(spacing: Space.s1) { Text("View the workout"); Icon.next.image(IconSize.small) }
                                        .type(.t14).foregroundStyle(Palette.accent)
                                        .frame(minHeight: Size.control).contentShape(Rectangle())
                                }
                                .buttonStyle(CardStyle())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                }
            }
            .padding(.top, Space.s4)
        }
    }
}
