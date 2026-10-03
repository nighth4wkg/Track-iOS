import Foundation

// Volume, weeks, streaks, levels and records (lib/training-metrics.ts, components/up-next.tsx). Days and weeks are in
// the device's time zone, weeks starting on Monday, as on the website.

public enum Calendars {
    /// Gregorian in the device's time zone (the website uses the browser's local time).
    public static var local: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}

func date(_ millis: Int) -> Date { Date(timeIntervalSince1970: Double(millis) / 1000) }
public func millis(_ date: Date) -> Int { Int((date.timeIntervalSince1970 * 1000).rounded()) }

/// The day a time falls on, as "2026-10-02".
public func dayKey(_ time: Int, calendar: Calendar = Calendars.local) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date(time))
    return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
}

/// Midnight on the Monday of the time's week.
public func weekStart(_ time: Int, calendar: Calendar = Calendars.local) -> Int {
    let day = calendar.startOfDay(for: date(time))
    let sinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
    return millis(calendar.date(byAdding: .day, value: -sinceMonday, to: day)!)
}

extension Session {
    /// Weight × reps over the logged sets.
    public var volume: Double { completedSets.reduce(0) { $0 + ($1.kg ?? 0) * Double($1.reps ?? 0) } }
}

extension Array where Element == Session {
    public var finished: [Session] { filter { $0.finishedAt != nil } }

    /// The workouts finished in the time's week.
    public func inWeek(of time: Int, calendar: Calendar = Calendars.local) -> [Session] {
        let start = weekStart(time, calendar: calendar)
        return finished.filter { weekStart($0.finishedAt!, calendar: calendar) == start }
    }

    /// This week's volume so far, and its percentage change against last week up to the same moment (nil when last
    /// week had none by then), so a Monday never reads as a drop against a whole finished week.
    public func weekVolumeChange(at time: Int, calendar: Calendar = Calendars.local) -> (volume: Double, change: Int?) {
        let then = millis(calendar.date(byAdding: .day, value: -7, to: date(time))!)
        let now = inWeek(of: time, calendar: calendar).reduce(0) { $0 + $1.volume }
        let last = filter { ($0.finishedAt ?? .max) <= then }.inWeek(of: then, calendar: calendar).reduce(0) { $0 + $1.volume }
        return (now, last > 0 ? Int(((now - last) / last * 100).rounded()) : nil)
    }

    /// Weeks in a row with a workout, ending this week (or last week, while this one has none yet).
    public func weeklyStreak(at time: Int, calendar: Calendar = Calendars.local) -> Int {
        let weeks = Set(finished.map { weekStart($0.finishedAt!, calendar: calendar) })
        var cursor = weekStart(time, calendar: calendar)
        let back = { (week: Int) in weekStart(millis(calendar.date(byAdding: .day, value: -7, to: date(week))!), calendar: calendar) }
        if !weeks.contains(cursor) { cursor = back(cursor) }
        var streak = 0
        while weeks.contains(cursor) { streak += 1; cursor = back(cursor) }
        return streak
    }

    /// The heaviest logged weight per exercise, by name.
    public var personalRecords: [String: Double] {
        var records: [String: Double] = [:]
        for session in self { for exercise in session.exercises {
            for set in exercise.sets where set.done && set.isValid { records[exercise.name] = Swift.max(records[exercise.name] ?? 0, set.kg!) }
        } }
        return records
    }
}

// MARK: Levels

public enum Experience {
    public static let dailyStart = 20, perSet = 5, dailySetCap = 12

    /// XP to go from this level to the next: attainable early, asking for consistency later.
    public static func requirement(for level: Int) -> Int { Swift.min(300, 100 + 50 * Swift.max(0, level - 1)) }

    public struct Progress: Equatable, Sendable {
        public var total = 0, current = 0, level = 1
        public var required: Int { Experience.requirement(for: level) }
    }

    /// Level and XP from the finished workouts, oldest first: the first workout of a day earns a start bonus and every
    /// logged set earns XP, up to a daily set cap; achievement awards add their XP. Stored awards win over recomputing.
    public static func progress(of sessions: [Session], calendar: Calendar = Calendars.local) -> Progress {
        var progress = Progress()
        for (session, training) in rewards(of: sessions, calendar: calendar) {
            let earned = training + (session.questAwards ?? []).reduce(0) { $0 + $1.xp }
            progress.total += earned
            progress.current += earned
            while progress.current >= progress.required { progress.current -= progress.required; progress.level += 1 }
        }
        return progress
    }

    /// Each finished workout, oldest first, with its training XP (its stored award, else computed).
    public static func rewards(of sessions: [Session], calendar: Calendar = Calendars.local) -> [(Session, Int)] {
        var dailySets: [String: Int] = [:]
        let ordered = sessions.finished.sorted { a, b in a.finishedAt! == b.finishedAt! ? a.id < b.id : a.finishedAt! < b.finishedAt! }
        return ordered.map { session in
            let key = dayKey(session.finishedAt!, calendar: calendar)
            let prior = Swift.min(dailySetCap, dailySets[key] ?? 0)
            let sets = session.completedSets.count
            let counted = sets == 0 || prior >= dailySetCap ? 0 : Swift.min(dailySetCap - prior, sets)
            let computed = counted == 0 ? 0 : (prior == 0 ? dailyStart : 0) + counted * perSet
            dailySets[key] = Swift.min(dailySetCap, prior + sets)
            return (session, session.xpEarned ?? computed)
        }
    }
}

extension Training {
    /// The split trained longest ago (never-trained splits first, in list order): the natural next workout.
    public var nextSplit: (split: Split, lastDone: Int?)? {
        var best: (split: Split, last: Int)?
        for split in splits where !split.exercises.isEmpty {
            let last = latestSession(of: split.id)?.finishedAt ?? .min
            if best == nil || last < best!.last { best = (split, last) }
        }
        return best.map { ($0.split, $0.last == .min ? nil : $0.last) }
    }
}
