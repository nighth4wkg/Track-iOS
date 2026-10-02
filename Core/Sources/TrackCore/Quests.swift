import Foundation

// Achievements (lib/quest-catalog.ts, training-quests.ts): 24 quests earned from the history, each awarded once to the
// workout that reached it, with its XP.

public struct Quest: Identifiable, Sendable {
    public enum Metric: Sendable { case sessions, sets, days, exercises, records, recordSessions, weeklySessions, weeklyRecordSessions, streak }
    public let id: String
    public let title: String
    public let description: String
    public let difficulty: String
    public let xp: Int
    public let metric: Metric
    public let threshold: Int

    public static let all: [Quest] = [
        Quest(id: "first-session", title: "First Step", description: "Finish 1 workout with a valid completed set.", difficulty: "Easy", xp: 20, metric: .sessions, threshold: 1),
        Quest(id: "ten-sets", title: "Set in Motion", description: "Complete 10 valid sets.", difficulty: "Easy", xp: 25, metric: .sets, threshold: 10),
        Quest(id: "two-sessions", title: "Back for More", description: "Finish 2 workouts.", difficulty: "Easy", xp: 30, metric: .sessions, threshold: 2),
        Quest(id: "three-days", title: "Three-Day Start", description: "Train on 3 different calendar days.", difficulty: "Easy", xp: 30, metric: .days, threshold: 3),
        Quest(id: "first-record", title: "New Ground", description: "Break a weight or rep record after a prior result.", difficulty: "Easy", xp: 35, metric: .records, threshold: 1),
        Quest(id: "three-in-week", title: "Weekly Rhythm", description: "Finish 3 workouts in one calendar week.", difficulty: "Easy", xp: 40, metric: .weeklySessions, threshold: 3),
        Quest(id: "five-sessions", title: "Building a Habit", description: "Finish 5 workouts.", difficulty: "Medium", xp: 50, metric: .sessions, threshold: 5),
        Quest(id: "fifty-sets", title: "Quality Volume", description: "Complete 50 valid sets.", difficulty: "Medium", xp: 55, metric: .sets, threshold: 50),
        Quest(id: "five-exercises", title: "Well Rounded", description: "Log valid sets for 5 different exercises.", difficulty: "Medium", xp: 60, metric: .exercises, threshold: 5),
        Quest(id: "three-records", title: "Record Collector", description: "Break 3 weight or rep records.", difficulty: "Medium", xp: 65, metric: .records, threshold: 3),
        Quest(id: "two-record-workouts-week", title: "Breakthrough Week", description: "Break records in 2 distinct workouts in one calendar week.", difficulty: "Medium", xp: 70, metric: .weeklyRecordSessions, threshold: 2),
        Quest(id: "three-week-streak", title: "Three Weeks Strong", description: "Train in 3 consecutive calendar weeks.", difficulty: "Medium", xp: 75, metric: .streak, threshold: 3),
        Quest(id: "ten-sessions", title: "Double Digits", description: "Finish 10 workouts.", difficulty: "Medium", xp: 80, metric: .sessions, threshold: 10),
        Quest(id: "twenty-sessions", title: "Committed", description: "Finish 20 workouts.", difficulty: "Hard", xp: 100, metric: .sessions, threshold: 20),
        Quest(id: "two-fifty-sets", title: "Volume Builder", description: "Complete 250 valid sets.", difficulty: "Hard", xp: 110, metric: .sets, threshold: 250),
        Quest(id: "ten-days", title: "Ten Training Days", description: "Train on 10 different calendar days.", difficulty: "Hard", xp: 120, metric: .days, threshold: 10),
        Quest(id: "five-record-workouts", title: "Proven Progress", description: "Break a record in 5 distinct workouts.", difficulty: "Hard", xp: 130, metric: .recordSessions, threshold: 5),
        Quest(id: "six-week-streak", title: "Six Weeks Strong", description: "Train in 6 consecutive calendar weeks.", difficulty: "Hard", xp: 140, metric: .streak, threshold: 6),
        Quest(id: "four-in-week", title: "High-Frequency Week", description: "Finish 4 workouts in one calendar week.", difficulty: "Hard", xp: 150, metric: .weeklySessions, threshold: 4),
        Quest(id: "fifty-sessions", title: "Fifty Finished", description: "Finish 50 workouts.", difficulty: "Extremely difficult", xp: 200, metric: .sessions, threshold: 50),
        Quest(id: "five-hundred-sets", title: "Deep Work", description: "Complete 500 valid sets.", difficulty: "Extremely difficult", xp: 225, metric: .sets, threshold: 500),
        Quest(id: "twenty-five-days", title: "Training Regular", description: "Train on 25 different calendar days.", difficulty: "Extremely difficult", xp: 250, metric: .days, threshold: 25),
        Quest(id: "twelve-week-streak", title: "Twelve Weeks Strong", description: "Train in 12 consecutive calendar weeks.", difficulty: "Extremely difficult", xp: 300, metric: .streak, threshold: 12),
        Quest(id: "hundred-sessions", title: "Century of Work", description: "Finish 100 workouts.", difficulty: "Extremely difficult", xp: 400, metric: .sessions, threshold: 100),
    ]
}

/// The history's totals, as the achievements count them.
struct QuestStats {
    var values: [Quest.Metric: Int] = [:]
    subscript(metric: Quest.Metric) -> Int { values[metric] ?? 0 }
}

extension Array where Element == Session {
    /// Walks the history oldest first: the totals after each workout, and which achievements each one reached.
    func qualificationTimeline(calendar: Calendar = Calendars.local) -> (history: [Session], qualified: Set<String>, stats: QuestStats) {
        let history = finished.filter { !$0.completedSets.isEmpty }
            .sorted { a, b in a.finishedAt! == b.finishedAt! ? a.id < b.id : a.finishedAt! < b.finishedAt! }
        var recordCounts: [String: Int] = [:]
        for record in history.improvements { recordCounts[record.after.sessionId, default: 0] += 1 }
        var days = Set<String>(), exercises = Set<String>(), recordSessions = Set<String>(), weeks = Set<Int>()
        var sessionsByWeek: [Int: Int] = [:], recordsByWeek: [Int: Int] = [:]
        var qualified = Set<String>(), stats = QuestStats()
        var sets = 0, records = 0, streak = 0, longest = 0, count = 0
        var previousWeek: Int?
        for session in history {
            count += 1
            for exercise in session.exercises {
                let valid = exercise.sets.filter { $0.done && $0.isValid }.count
                sets += valid
                if valid > 0 { exercises.insert(exerciseKey(exercise.name)) }
            }
            days.insert(dayKey(session.finishedAt!, calendar: calendar))
            let week = weekStart(session.finishedAt!, calendar: calendar)
            if !weeks.contains(week) {
                let following = previousWeek.map { weekStart(millis(calendar.date(byAdding: .day, value: 7, to: date($0))!), calendar: calendar) }
                streak = following == week ? streak + 1 : 1
                longest = Swift.max(longest, streak)
                previousWeek = week
                weeks.insert(week)
            }
            sessionsByWeek[week, default: 0] += 1
            let sessionRecords = recordCounts[session.id] ?? 0
            records += sessionRecords
            if sessionRecords > 0 { recordSessions.insert(session.id); recordsByWeek[week, default: 0] += 1 }
            stats.values = [.sessions: count, .sets: sets, .days: days.count, .exercises: exercises.count, .records: records,
                            .recordSessions: recordSessions.count, .weeklySessions: sessionsByWeek.values.max() ?? 0,
                            .weeklyRecordSessions: recordsByWeek.values.max() ?? 0, .streak: longest]
            for quest in Quest.all where !qualified.contains(quest.id) && stats[quest.metric] >= quest.threshold { qualified.insert(quest.id) }
        }
        return (history, qualified, stats)
    }

    /// Achievements already awarded, by id: when, and to which workout.
    public var questAwards: [String: (sessionId: String, earnedAt: Int)] {
        var awards: [String: (sessionId: String, earnedAt: Int)] = [:]
        for session in self { for award in session.questAwards ?? [] { awards[award.questId] = (session.id, award.earnedAt) } }
        return awards
    }

    /// The unfinished achievement you're furthest along (ties to the easier one), with how far.
    public func nearestQuest(calendar: Calendar = Calendars.local) -> (quest: Quest, value: Int)? {
        let (_, qualified, stats) = qualificationTimeline(calendar: calendar)
        let earned = questAwards
        var best: (quest: Quest, value: Int, ratio: Double)?
        for quest in Quest.all where !qualified.contains(quest.id) && earned[quest.id] == nil {
            let value = Swift.min(stats[quest.metric], quest.threshold - 1)
            let ratio = Double(value) / Double(quest.threshold)
            if best == nil || ratio > best!.ratio { best = (quest, value, ratio) }
        }
        return best.map { ($0.quest, $0.value) }
    }
}

extension Training {
    /// After finishing: fixes each workout's training XP (so later edits elsewhere can't change past awards), then
    /// gives the newest workout any achievements the history now reaches that nobody has yet.
    public mutating func awardLatestQuests(calendar: Calendar = Calendars.local) {
        let rewards = Dictionary(uniqueKeysWithValues: Experience.rewards(of: sessions, calendar: calendar).map { ($0.0.id, $0.1) })
        for index in sessions.indices where sessions[index].xpEarned == nil { sessions[index].xpEarned = rewards[sessions[index].id] }
        let (history, qualified, _) = sessions.qualificationTimeline(calendar: calendar)
        guard let latest = history.last, let index = sessions.firstIndex(where: { $0.id == latest.id }) else { return }
        let awarded = Set(sessions.flatMap { ($0.questAwards ?? []).map(\.questId) })
        let new = Quest.all.filter { qualified.contains($0.id) && !awarded.contains($0.id) }
        guard !new.isEmpty else { return }
        sessions[index].questAwards = (sessions[index].questAwards ?? []) + new.map { QuestAward(questId: $0.id, earnedAt: latest.finishedAt!, xp: $0.xp) }
    }
}
