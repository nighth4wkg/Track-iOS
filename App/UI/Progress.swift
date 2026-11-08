import SwiftUI
import TrackCore

/// Progress (the PWA's): pick a period (D W M) and a measure; see it against the same moment of the last period, bar
/// by bar, then streak, level and badges, and every exercise trained, sorted Recent, Best or Gained (tap one for its
/// page).
struct ProgressScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tabTraining) private var training
    @AppStorage("track.volumePeriod") private var period = Period.week
    @AppStorage("track.measure") private var tally = Tally.volume
    @State private var order = Order.recent
    @State private var all = false
    /// Exercises listed before Show all.
    private static let shown = 5
    enum Order: String, CaseIterable { case recent = "Recent", best = "Best", gained = "Gained" }

    var body: some View {
        let now = nowMillis()
        let lifts = model.derived("lifts", of: training.sessions) { $0.trainedLifts }
        TabPage {
            TabHead(title: "Progress") {
                Seg(label: "Period", options: Period.allCases.map { (value: $0, text: $0.name) }, value: $period, short: true)
            }
            Seg(label: "Measure", options: Tally.allCases.map { (value: $0, text: $0.rawValue) }, value: $tally).padding(.top, Space.s4)
            chart(training, now: now).padding(.top, Space.s3)
            HStack(spacing: Space.s3) {
                StatTile(label: "Streak", value: "\(model.derived("streak", of: training.sessions, at: dayKey(now)) { $0.weeklyStreak(at: now) })", unit: "wk")
                let level = model.derived("xp", of: training.sessions) { Experience.progress(of: $0) }.level
                Button { model.present(XpHelp()) } label: { StatTile(label: "Level", value: "\(level)") }
                    .buttonStyle(CardStyle()).readies { model.ready(XpHelp()) }.accessibilityLabel("Level \(level). How XP works")
                let earned = model.derived("award count", of: training.sessions) { $0.questAwards.count }
                Button { model.present(QuestList(), tall: true) } label: { StatTile(label: "Badges", value: "\(earned)", unit: "/\(Quest.all.count)", tight: true) }
                    .buttonStyle(CardStyle()).readies { model.ready(QuestList(), tall: true) }.accessibilityLabel("Badges: \(earned) of \(Quest.all.count). Show all")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Space.s3)
            if !lifts.isEmpty { exercises(lifts, now: now) }
        }
    }

    /// Exercises: the count trained, the sort, then a card per exercise (its graph page) and Show all. A sort swaps the
    /// list whole, as History's filters do: glided, rows slid through each other (the PWA's lesson).
    private func exercises(_ lifts: [TrainedLift], now: Int) -> some View {
        let unit = training.settings.unit
        let sorted = lifts.sorted { a, b in
            switch order {
            case .recent: a.last == b.last ? a.name < b.name : a.last > b.last
            case .best: a.kg == b.kg ? a.name < b.name : a.kg > b.kg
            case .gained: a.gained == b.gained ? a.name < b.name : a.gained > b.gained
            }
        }
        let list = all ? sorted : Array(sorted.prefix(Self.shown))
        // A row stays as it is only where the same exercise stays on the same spot; anywhere else it's swapped.
        let rows = list.indices.map { (key: "\(list[$0].name)\u{0}\($0)", lift: list[$0]) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text("Exercises").type(.t20).foregroundStyle(Palette.text).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("\(lifts.count) trained").type(.t14).monospacedDigit().foregroundStyle(Palette.muted)
            }
            Seg(label: "Sort exercises", options: Order.allCases.map { (value: $0, text: $0.rawValue) }, value: $order, moves: true)
                .padding(.top, Space.s2)
            VStack(spacing: Space.s3) {
                ForEach(rows, id: \.key) { item in
                    Button { model.open(.lift(item.lift.name)) } label: { row(item.lift, unit: unit, now: now) }
                        .buttonStyle(CardStyle())
                        .readies { model.ready(.lift(item.lift.name)) }
                        .transition(.swap)
                }
                if !all && lifts.count > Self.shown {
                    Button("Show all \(lifts.count)") { Motion.tap { all = true } }.buttonStyle(SecondaryStyle()).transition(.swap)
                }
            }
            .padding(.top, Space.s2)
        }
        .padding(.top, Space.s6)
    }

    private func row(_ lift: TrainedLift, unit: TrackCore.Settings.Unit, now: Int) -> some View {
        let when = ago(lift.last, now: now)
        let gained = order == .gained && lift.gained >= 1 ? dot + "+\(weight(lift.gained, unit)) \(unit.rawValue)" : ""
        // Sorted by gain, the gain says it: both crowded a 320-wide row onto a second line.
        let best = lift.record && order != .gained
        return HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 0) {
                Text(lift.name).type(.t16).foregroundStyle(Palette.text).multilineTextAlignment(.leading)
                Text("\(when.prefix(1).uppercased() + when.dropFirst() + gained)\(best ? dot : "")\(Text(best ? "New best" : "").foregroundStyle(Palette.accent))")
                    .type(.t12).monospacedDigit().foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(lift.kg > 0 ? "\(weight(lift.kg, unit)) \(unit.rawValue)" : "Bodyweight").type(.t14).monospacedDigit().foregroundStyle(Palette.text)
            Icon.next.image(IconSize.small).foregroundStyle(Palette.muted)
        }
        .pad().raised().contentShape(Rectangle())
    }

    private func chart(_ training: Training, now: Int) -> some View {
        let unit = training.settings.unit
        let result = model.derived("tally", of: training.sessions, at: "\(tally) \(period) \(minuteStamp(now))") { $0.change(of: tally, per: period, at: now) }
        let bars = model.derived("bars", of: training.sessions, at: "\(tally) \(period) \(minuteStamp(now))") { $0.bars(of: tally, per: period, at: now) }
        let top = max(1, bars.flatMap { [$0.now, $0.last] }.max() ?? 1)
        let note = result.value == 0 ? "Nothing logged \(period.now) yet" : result.change.map { "\($0 >= 0 ? "+" : "")\($0)% vs \(period.last)" } ?? "Nothing \(period.last) to compare"
        let tint = result.value == 0 ? Palette.muted : result.change.map { $0 >= 0 ? Palette.accent : Palette.danger } ?? Palette.muted
        let columns = max(1, bars.count)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(tally.rawValue) \(period.now)").type(.t14).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                Text(tally == .volume ? weight(result.value, unit) : Int(result.value).formatted()).type(.t28).monospacedDigit()
                Text(tally == .volume ? unit.rawValue : tally == .time ? "min" : tally.rawValue.lowercased()).type(.t14).foregroundStyle(Palette.muted)
            }
            .foregroundStyle(Palette.text)
            .padding(.top, Space.s2)
            Text(note).type(.t14).fontWeight(.semibold).foregroundStyle(tint)
            Cells(columns: columns) {
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
            Cells(columns: columns) {
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
        HStack(spacing: Gap.key) {
            RoundedRectangle(cornerRadius: Radius.key).fill(color).frame(width: Space.s2, height: Space.s2)
            Text(text).type(.t12).foregroundStyle(Palette.muted)
        }
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
    private static let rules = [
        ("First set of the day", "+\(Experience.dailyStart) XP", "Starts each training day."),
        ("Each extra set", "+\(Experience.perSet) XP", "Up to \(Experience.dailyCap) XP a day. L + R is one set."),
        ("Achievements", "Bonus XP", "Paid once, on top of the daily limit."),
        ("Levels", "\(Experience.requirement(for: 1))–\(Experience.maxRequirement) XP",
         "+\(Experience.requirement(for: 2) - Experience.requirement(for: 1)) XP per level."),
        ("Rest days", "No loss", "Resting never costs XP."),
    ]

    var body: some View {
        let level = model.derived("xp") { Experience.progress(of: $0) }
        let latest = model.derived("latest reward") { Experience.rewards(of: $0).last }
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
        let _ = Sampler.note("badges body")
        let sessions = model.training.sessions
        let awards = model.derived("awards") { $0.questAwards }
        SheetFrame(title: "Achievements") {
            Text("\(awards.count) of \(Quest.all.count) completed. Achievement XP is paid once, outside the \(Experience.dailyCap) XP daily training limit.")
                .type(.t14).foregroundStyle(Palette.muted).padding(.top, Space.s2)
            Group { if AB.oldWay {
                RowCard { ForEach(Quest.all) { row($0, awards[$0.id], sessions) } }
            } else {
                // Only the rows on screen are built (all 24 cost the sheet's first frames ~45 ms: build 124).
                LazyVStack(spacing: 0) {
                    ForEach(Array(Quest.all.enumerated()), id: \.element.id) { index, quest in
                        row(quest, awards[quest.id], sessions)
                            .overlay(alignment: .top) { if index > 0 { Palette.line.frame(height: Size.hairline) } }
                    }
                }
                .clipShape(Corner.card.shape)
                .raised()
            } }
            .padding(.top, Space.s4)
        }
    }

    private func row(_ quest: Quest, _ award: (sessionId: String, earnedAt: Int)?, _ sessions: [Session]) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: (award == nil ? Icon.badge : Icon.check).rawValue).font(.system(size: IconSize.medium, weight: .bold))
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
