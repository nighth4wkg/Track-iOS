import SwiftUI
import TrackCore

/// "How XP works", as the website's explainer: the five rules, then what the latest workout earned.
struct XpHelp: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let rules = [
        ("First set of the day", "+\(Experience.dailyStart) XP", "Starts each training day."),
        ("Each extra set", "+\(Experience.perSet) XP", "Up to \(Experience.dailyStart + Experience.perSet * Experience.dailySetCap) XP a day from training."),
        ("Achievements", "Bonus XP", "Paid once, on top of the daily limit."),
        ("Levels", "100–300 XP", "Each level needs 50 XP more, up to 300."),
        ("Rest days", "No loss", "XP never drops for resting. Deleting a workout removes its XP."),
    ]

    var body: some View {
        let latestReward = Experience.rewards(of: model.training.sessions).last
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Progress that grows with your training.").font(.subheadline).foregroundStyle(Palette.muted)
                    GlassList {
                        ForEach(rules.indices, id: \.self) { index in row(rules[index].0, rules[index].1, rules[index].2) }
                        if let (latest, training) = latestReward {
                            let quest = (latest.questAwards ?? []).reduce(0) { $0 + $1.xp }
                            row("Latest workout", "+\(training + quest) XP", "\(training) training + \(quest) achievements")
                        }
                    }
                }
                .padding(16)
            }
            .background(Backdrop())
            .navigationTitle("How XP works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Palette.text) }.accessibilityLabel("Close")
                }
            }
        }
    }

    private func row(_ rule: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(rule).font(.headline).foregroundStyle(Palette.text)
                Spacer()
                Text(value).font(.headline).monospacedDigit().foregroundStyle(Palette.accent)
            }
            Text(detail).font(.subheadline).foregroundStyle(Palette.muted)
        }
    }
}

/// Every achievement, as the website's list: done or not, what it asks, its difficulty and XP, and the workout that
/// earned it.
struct QuestList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let sessions = model.training.sessions
        let awards = sessions.questAwards
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(awards.count) of \(Quest.all.count) completed · Quest XP is awarded once, outside the \(Experience.dailyStart + Experience.perSet * Experience.dailySetCap) XP daily training cap.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    GlassList {
                        ForEach(Array(Quest.all.enumerated()), id: \.element.id) { index, quest in
                            let award = awards[quest.id]
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: award == nil ? "rosette" : "checkmark").font(.body.weight(.bold))
                                    .foregroundStyle(award == nil ? Palette.muted : Palette.primaryText)
                                    .frame(width: 40, height: 40)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(award == nil ? Palette.control : Palette.primary))
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(quest.title).font(.headline).foregroundStyle(Palette.text)
                                        Spacer()
                                        Text("\(award == nil ? "" : "+")\(quest.xp) XP").font(.subheadline.weight(.bold))
                                            .foregroundStyle(award == nil ? Palette.muted : Palette.accent)
                                    }
                                    Text(quest.description).font(.subheadline).foregroundStyle(Palette.muted)
                                    Text("\(award == nil ? "Incomplete" : "Completed") · \(quest.difficulty) · Level \(index + 1)")
                                        .font(.caption).foregroundStyle(Palette.muted)
                                    if let award, let session = sessions.first(where: { $0.id == award.sessionId }) {
                                        Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { model.history = session } } label: {
                                            Label("View earning workout", systemImage: "arrow.up.right").labelStyle(TrailingIcon())
                                        }
                                        .font(.caption.weight(.semibold)).foregroundStyle(Palette.accent).padding(.top, 2)
                                    }
                                }
                            }
                            .opacity(award == nil ? 0.75 : 1)
                        }
                    }
                }
                .padding(16)
            }
            .background(Backdrop())
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Palette.text) }.accessibilityLabel("Close")
                }
            }
        }
    }
}
