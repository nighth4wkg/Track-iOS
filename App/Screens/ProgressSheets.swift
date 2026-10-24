import SwiftUI
import TrackCore

/// "How XP works", as the PWA's: your level and its bar, the rules, then what the latest workout earned. Every number
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
                HStack {
                    Text("Level \(level.level)").type(.t16).foregroundStyle(Palette.text)
                    Spacer(minLength: Space.s2)
                    Text("\(level.current)/\(level.required) XP").type(.t14).monospacedDigit().foregroundStyle(Palette.muted)
                }
                RankBar(progress: Double(level.current) / Double(max(1, level.required)), color: Palette.accent)
                    .accessibilityLabel("Level \(level.level + 1) progress")
            }
            .padding(Space.s4)
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
                Text(rule).type(.t16).foregroundStyle(Palette.text)
                Spacer(minLength: 0)
                Text(value).type(.t14).monospacedDigit().foregroundStyle(Palette.accent)
            }
            Text(detail).type(.t14).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Every achievement, as the PWA's: how many are done, then each with a tile (✓ once done), what it asks, its XP and
/// difficulty, and the workout that earned it.
struct QuestList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let sessions = model.training.sessions
        let awards = sessions.questAwards
        let cap = Experience.dailyStart + Experience.perSet * Experience.dailySetCap
        SheetFrame(title: "Achievements", tall: true) {
            Text("\(awards.count) of \(Quest.all.count) completed. Achievement XP is paid once, outside the \(cap) XP daily training limit.")
                .type(.t14).foregroundStyle(Palette.muted).padding(.top, Space.s2)
            RowCard {
                ForEach(Quest.all) { quest in
                    let award = awards[quest.id]
                    HStack(alignment: .top, spacing: Space.s3) {
                        Image(systemName: award == nil ? "rosette" : "checkmark").font(.system(size: IconSize.medium, weight: .bold))
                            .foregroundStyle(award == nil ? Palette.muted : Palette.primaryText)
                            .frame(width: Size.tile, height: Size.tile)
                            .raised(award == nil ? .control : .green, .inner)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(quest.title).type(.t16).foregroundStyle(Palette.text)
                            Text(quest.description).type(.t14).foregroundStyle(Palette.muted)
                            Text("\(Text("\(award == nil ? "" : "+")\(quest.xp) XP").foregroundStyle(award == nil ? Palette.muted : Palette.accent)) · \(quest.difficulty)")
                                .type(.t12).foregroundStyle(Palette.muted)
                            if let award, let session = sessions.first(where: { $0.id == award.sessionId }) {
                                Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + Motion.sheetAway) { model.history = session } } label: {
                                    Label("View the workout", systemImage: "chevron.right").labelStyle(TrailingIcon())
                                        .type(.t14).foregroundStyle(Palette.accent)
                                        .frame(minHeight: Size.control).contentShape(Rectangle())
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                }
            }
            .padding(.top, Space.s4)
        }
    }
}
