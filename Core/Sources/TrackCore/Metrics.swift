import Foundation

// Volume, weeks, streaks, levels and records (lib/training-metrics.ts, components/up-next.tsx). Days and weeks are in
// the device's time zone, weeks starting on Monday, as on the website.

public enum Calendars {
    /// Gregorian in the device's time zone (the website uses the browser's local time).
    /// Made once and remade only when the time zone changes: the date helpers ask for it in every loop.
    public static var local: Calendar {
        let zone = TimeZone.current
        if cached.timeZone != zone { cached.timeZone = zone }
        return cached
    }
    private static var cached = Calendar(identifier: .gregorian)
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

/// What Progress groups volume by.
public enum Period: String, CaseIterable, Sendable {
    case day = "D", week = "W", month = "M"
    var component: Calendar.Component { self == .day ? .day : self == .week ? .weekOfYear : .month }
}

/// What Progress counts.
public enum Tally: String, CaseIterable, Sendable {
    case volume = "Volume", sets = "Sets", workouts = "Workouts", time = "Time"
}

/// One of Progress's bars: its span's tally and the same span a period before.
public struct Bar: Sendable {
    public let label: String
    public let now: Double, last: Double
    /// The span holds this moment.
    public let today: Bool
}

/// Midnight at the start of the time's day, week (Monday) or month.
public func periodStart(_ time: Int, _ period: Period, calendar: Calendar = Calendars.local) -> Int {
    switch period {
    case .day: millis(calendar.startOfDay(for: date(time)))
    case .week: weekStart(time, calendar: calendar)
    case .month: millis(calendar.dateInterval(of: .month, for: date(time))!.start)
    }
}

extension TrainingSet {
    /// Epley: weight × (1 + reps / 30), the estimate the app has always shown.
    public var estimate: Double { (kg ?? 0) * (1 + Double(reps ?? 0) / 30) }
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

    /// This period's volume so far, and its percentage change against the last one up to the same moment.
    public func volumeChange(per period: Period, at time: Int, calendar: Calendar = Calendars.local) -> (volume: Double, change: Int?) {
        let result = change(of: .volume, per: period, at: time, calendar: calendar)
        return (result.value, result.change)
    }

    /// The tally over these workouts (Progress's measures).
    public func amount(_ tally: Tally) -> Double {
        switch tally {
        case .volume: reduce(0) { $0 + $1.volume }
        case .sets: Double(reduce(0) { $0 + $1.loggedCount })
        case .workouts: Double(count)
        case .time: Double(reduce(0) { $0 + $1.minutes })
        }
    }

    /// This period's tally so far, and its percentage change against the last one up to the same moment (nil when
    /// that had none by then), so a Monday never reads as a drop against a whole finished week.
    public func change(of tally: Tally, per period: Period, at time: Int, calendar: Calendar = Calendars.local) -> (value: Double, change: Int?) {
        let then = millis(calendar.date(byAdding: period.component, value: -1, to: date(time))!)
        let value = { (end: Int) in
            let start = periodStart(end, period, calendar: calendar)
            return finished.filter { (start...end).contains($0.finishedAt!) }.amount(tally)
        }
        let now = value(time), last = value(then)
        return (now, last > 0 ? Int(((now - last) / last * 100).rounded()) : nil)
    }

    /// Progress's bars (pwa Progress.tsx): this week's days (or the last 7 days, or this month's weeks from the 1st),
    /// each beside the same span a period before.
    public func bars(of tally: Tally, per period: Period, at time: Int, calendar: Calendar = Calendars.local) -> [Bar] {
        let day = { (from: Int, days: Int) in millis(calendar.date(byAdding: .day, value: days, to: date(from))!) }
        var spans: [(label: String, from: Int, to: Int, lastFrom: Int, lastTo: Int)] = []
        if period == .month {
            let first = periodStart(time, .month, calendar: calendar)
            let last = millis(calendar.date(byAdding: .month, value: -1, to: date(first))!)
            for week in 0..<5 {
                spans.append(("\(week * 7 + 1)", day(first, week * 7), day(first, week * 7 + 7), day(last, week * 7), day(last, week * 7 + 7)))
            }
        } else {
            let start = period == .week ? weekStart(time, calendar: calendar) : day(periodStart(time, .day, calendar: calendar), -6)
            for offset in 0..<7 {
                let from = day(start, offset)
                let letter = ["M", "T", "W", "T", "F", "S", "S"][(calendar.component(.weekday, from: date(from)) + 5) % 7]
                spans.append((letter, from, day(from, 1), day(from, -7), day(from, -6)))
            }
        }
        let of = { (from: Int, to: Int) in finished.filter { $0.finishedAt! >= from && $0.finishedAt! < to }.amount(tally) }
        return spans.map { span in
            Bar(label: span.label, now: span.from > time ? 0 : of(span.from, span.to), last: of(span.lastFrom, span.lastTo),
                today: (span.from..<span.to).contains(time))
        }
    }

    /// Each exercise's heaviest logged set, heaviest first.
    public var personalRecords: [(name: String, kg: Double)] {
        var best: [String: Double] = [:]
        for session in self { for exercise in session.exercises { for set in exercise.sets where set.done && set.isValid {
            if let kg = set.kg { best[exercise.name] = Swift.max(best[exercise.name] ?? 0, kg) }
        } } }
        return best.map { ($0.key, $0.value) }.sorted { $0.kg == $1.kg ? $0.name < $1.name : $0.kg > $1.kg }
    }

    /// One exercise's logged sets in each workout that has any, newest first (pwa Lift.tsx).
    public func entries(of name: String) -> [(session: Session, sets: [TrainingSet])] {
        finished.map { session in (session, session.exercises.filter { $0.name == name }.flatMap { $0.sets.filter { $0.done && $0.isValid } }) }
            .filter { !$0.sets.isEmpty }
            .sorted { $0.session.finishedAt! > $1.session.finishedAt! }
    }

    /// The best estimated one-rep max in each of the last `limit` days, weeks or months the exercise was trained,
    /// oldest first.
    public func oneRepMaxes(of name: String, per period: Period, limit: Int = 8, calendar: Calendar = Calendars.local) -> [(at: Int, value: Double)] {
        var best: [Int: (at: Int, value: Double)] = [:]
        for (session, sets) in entries(of: name) {
            let key = periodStart(session.finishedAt!, period, calendar: calendar)
            let value = sets.map(\.estimate).max()!
            if value > best[key]?.value ?? -1 { best[key] = (session.finishedAt!, value) }
        }
        return Swift.Array(best.values.sorted { $0.at < $1.at }.suffix(limit))
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
}

// MARK: Levels

public enum Experience {
    public static let dailyStart = 20, perSet = 5, dailySetCap = 12

    /// XP to go from this level to the next: attainable early, asking for consistency later.
    public static let maxRequirement = 300
    public static func requirement(for level: Int) -> Int { Swift.min(maxRequirement, 100 + 50 * Swift.max(0, level - 1)) }

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
