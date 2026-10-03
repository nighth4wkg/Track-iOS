import SwiftUI
import TrackCore

/// The home screen's one answer to "what now?": this week's training days against the goal, the split trained
/// longest ago, and one prominent Start.
struct UpNextCard: View {
    @Environment(AppModel.self) private var model
    let training: Training
    let now: Int

    var body: some View {
        if let next = training.nextSplit {
            VStack(spacing: 16) {
                HStack(spacing: 20) {
                    WeekRing(done: training.sessions.trainingDays(inWeekOf: now).count, goal: training.settings.weeklyGoal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Up next").font(.subheadline).foregroundStyle(Palette.muted)
                        Text(next.split.name).font(.title2.weight(.bold)).foregroundStyle(Palette.text).lineLimit(1)
                        Text(next.split.summary).font(.subheadline).foregroundStyle(Palette.muted)
                        Text(lastDone(next.lastDone)).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                }
                Button { model.start(next.split) } label: { Label("Start workout", systemImage: "play") }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(20)
            .glass()
            .sensoryFeedback(.impact(weight: .medium), trigger: model.workoutOpen) { _, open in open }
        }
    }

    private func lastDone(_ last: Int?) -> String {
        guard let last else { return "Not done yet" }
        let days = (now - last) / 86_400_000
        return days < 1 ? "Done today" : days == 1 ? "Last done yesterday" : "Last done \(days) days ago"
    }
}

/// This week's volume against last week up to the same moment, and the achievement you're nearest.
struct HomeTiles: View {
    let training: Training
    let now: Int

    var body: some View {
        let week = training.sessions.weekVolumeChange(at: now)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Volume this week").font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(weight(week.volume, training.settings.unit)).font(.title2.weight(.bold)).monospacedDigit()
                    Text(training.settings.unit.rawValue).font(.subheadline).foregroundStyle(Palette.muted)
                }
                .foregroundStyle(Palette.text)
                if let change = week.change {
                    Text(change == 0 ? "Same as last week" : "\(change > 0 ? "▲" : "▼") \(abs(change))% vs last week")
                        .font(.footnote.weight(.semibold)).foregroundStyle(change > 0 ? Palette.accent : Palette.muted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading).padding(16).glass()
            if let next = training.sessions.nearestQuest() {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next achievement").font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                    Text(next.quest.title).font(.headline).foregroundStyle(Palette.text).lineLimit(2)
                    GoalBar(questId: next.quest.id, progress: max(0.04, Double(next.value) / Double(next.quest.threshold)))
                }
                .frame(maxWidth: .infinity, alignment: .topLeading).padding(16).glass()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The next achievement's bar. It fills only when the progress changed since you last saw it (not on every visit).
private struct GoalBar: View {
    let questId: String
    let progress: Double
    @State private var shown: Double?
    private static var seen: [String: Double] = [:]

    var body: some View {
        RankBar(progress: shown ?? progress, color: Palette.primary)
            .onAppear {
                let from = Self.seen[questId] ?? 0
                Self.seen[questId] = progress
                guard from != progress else { return }
                shown = from
                withAnimation(.smooth(duration: 0.9).delay(0.15)) { shown = progress }
            }
    }
}

extension Split {
    /// "3 exercises · 9 sets"
    var summary: String {
        "\(count(exercises.count, "exercise")) · \(count(exercises.reduce(0) { $0 + $1.sets.count }, "set"))"
    }
}
