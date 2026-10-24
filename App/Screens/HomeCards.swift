import SwiftUI
import TrackCore

/// Home's first card, as the PWA's: this week's training days on the ring beside what's next (a green label, the
/// name, its facts as lines), then one main button. The split trained longest ago and Start; or the workout in
/// progress and Continue, which a swipe left turns into Discard (Track asks first); or, with no splits, New split.
struct UpNextCard: View {
    @Environment(AppModel.self) private var model
    let training: Training
    let now: Int
    let create: () -> Void
    @State private var discarding = false

    var body: some View {
        VStack(spacing: Space.s4) {
            HStack(spacing: Space.s4) {
                WeekRing(done: model.derived("days \(dayKey(now))") { $0.trainingDays(inWeekOf: now).count }, goal: training.settings.weeklyGoal)
                VStack(alignment: .leading, spacing: Space.s1) {
                    if let active = training.active {
                        Badge(text: "In progress").padding(.bottom, Space.s1)
                        Text(active.name).type(.t20)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("\(elapsed(active.startedAt, context.date)) min").type(.t14).monospacedDigit().foregroundStyle(Palette.muted)
                        }
                        Text("\(active.exercises.doneCount) of \(count(active.exercises.plannedCount, "set")) done")
                            .type(.t14).monospacedDigit().foregroundStyle(Palette.muted)
                    } else if let next = training.nextSplit {
                        Badge(text: "Up next").padding(.bottom, Space.s1)
                        Text(next.split.name).type(.t20)
                        Text(next.split.summary).type(.t14).foregroundStyle(Palette.muted)
                        Text(lastDone(next.lastDone)).type(.t14).foregroundStyle(Palette.muted)
                    } else {
                        Badge(text: "Get started").padding(.bottom, Space.s1)
                        Text("First split").type(.t20)
                        Text("A workout to repeat.").type(.t14).foregroundStyle(Palette.muted)
                    }
                }
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            button
        }
        .padding(Space.s4)
        .raised()
        .modifier(ArmIf(on: training.active != nil, armed: $discarding))
        .onChange(of: training.active == nil) { discarding = false }
        .sensoryFeedback(.impact(weight: .medium), trigger: model.workoutOpen) { _, open in open }
    }

    @ViewBuilder private var button: some View {
        if training.active != nil {
            if discarding {
                Button { discarding = false; model.discard() } label: { Label("Discard workout", systemImage: "trash") }
                    .buttonStyle(SecondaryButtonStyle(danger: true, height: Size.primary))
                    .transition(.opacity)
            } else {
                Button { model.workoutOpen = true } label: { Label("Continue workout", systemImage: "play") }
                    .buttonStyle(PrimaryButtonStyle())
                    .transition(.opacity)
            }
        } else if let next = training.nextSplit {
            Button { model.start(next.split) } label: { Label("Start workout", systemImage: "play") }.buttonStyle(PrimaryButtonStyle())
        } else {
            Button(action: create) { Label("New split", systemImage: "plus") }.buttonStyle(PrimaryButtonStyle())
        }
    }

    /// "Last done yesterday", as the PWA's ago(): calendar days, so last night's workout is "yesterday" this morning.
    private func lastDone(_ last: Int?) -> String {
        guard let last else { return "Not done yet" }
        let day = { (time: Int) in Calendars.local.startOfDay(for: Date(timeIntervalSince1970: Double(time) / 1000)) }
        let days = Calendars.local.dateComponents([.day], from: day(last), to: day(now)).day ?? 0
        return "Last done " + (days < 1 ? "today" : days == 1 ? "yesterday" : "\(days) days ago")
    }
}

/// Swipe to arm, only while there's something to arm (the workout in progress).
private struct ArmIf: ViewModifier {
    let on: Bool
    @Binding var armed: Bool

    func body(content: Content) -> some View {
        if on { content.swipeToArm($armed) } else { content }
    }
}

/// This week's volume against last week up to the same moment, and the achievement you're nearest: side by side
/// while each has room for its longest line, stacked on narrower phones (the PWA's .tiles).
struct HomeTiles: View {
    @Environment(AppModel.self) private var model
    let training: Training
    let now: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Space.s3) { volume.frame(minWidth: Size.tileMin); achievement.frame(minWidth: Size.tileMin) }
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Space.s3) { volume; achievement }
        }
    }

    private var volume: some View {
        let week = model.derived("volume W \(now / 60_000)") { $0.volumeChange(per: .week, at: now) }
        return VStack(alignment: .leading, spacing: 0) {
            Text("Volume this week").type(.t14).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                Text(weight(week.volume, training.settings.unit)).type(.t20).monospacedDigit().foregroundStyle(Palette.text)
                Text(training.settings.unit.rawValue).type(.t14).foregroundStyle(Palette.muted)
            }
            .padding(.top, Space.s2)
            if let change = week.change {
                Text(week.volume == 0 ? "Nothing logged yet" : change == 0 ? "Same as last week" : "\(change > 0 ? "▲" : "▼") \(abs(change))% vs last week")
                    .type(.t14).foregroundStyle(week.volume > 0 && change > 0 ? Palette.accent : Palette.muted)
            }
        }
        .tile()
    }

    private var achievement: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Next achievement").type(.t14).foregroundStyle(Palette.muted)
            if let next = model.derived("nearest quest", { $0.nearestQuest() }) {
                Text(next.quest.title).type(.t16).foregroundStyle(Palette.text)
                GoalBar(questId: next.quest.id, progress: Double(next.value) / Double(next.quest.threshold))
            } else {
                Text("All earned").type(.t16).foregroundStyle(Palette.text)
            }
        }
        .tile()
    }
}

private extension View {
    /// A tile's card: 16 all round, its content top left, as tall as its neighbour.
    func tile() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(Space.s4).raised()
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
                withAnimation(.smooth(duration: Motion.slow).delay(Motion.fast)) { shown = progress }
            }
    }
}

extension Split {
    /// "3 exercises · 9 sets"
    var summary: String {
        "\(count(exercises.count, "exercise")) · \(count(exercises.plannedCount, "set"))"
    }
}
