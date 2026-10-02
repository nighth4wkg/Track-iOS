import Foundation

// Personal records as improvements (lib/training-progress.ts) and the weekly volume behind the Progress chart.

/// A logged set, as evidence for a record.
public struct Evidence: Equatable, Sendable {
    public let exercise: String
    public let kg: Double
    public let reps: Int
    public let rir: Int
    public let date: Int
    public let sessionId: String
}

/// A set that beat an earlier one: more weight for the same reps, or more reps at the same weight.
public struct Improvement: Equatable, Sendable {
    public enum Kind: Sendable { case weight, reps }
    public let kind: Kind
    public let before: Evidence
    public let after: Evidence
}

/// Exercise names compare without case or extra spaces.
public func exerciseKey(_ name: String) -> String {
    name.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
}

extension Array where Element == Session {
    /// Every improvement, newest first. Each workout's best set per (exercise, weight) and (exercise, reps) is compared
    /// with the best before it.
    public var improvements: [Improvement] {
        var bestReps: [String: Evidence] = [:], bestWeight: [String: Evidence] = [:]
        var records: [Improvement] = []
        let ordered = finished.sorted { a, b in a.finishedAt! == b.finishedAt! ? a.id < b.id : a.finishedAt! < b.finishedAt! }
        for session in ordered {
            var reps: [String: Evidence] = [:], weights: [String: Evidence] = [:]
            var repOrder: [String] = [], weightOrder: [String] = []
            for exercise in session.exercises { for set in exercise.sets where set.done && set.isValid {
                let evidence = Evidence(exercise: exercise.name, kg: set.kg!, reps: set.reps!, rir: set.rir!, date: session.finishedAt!, sessionId: session.id)
                let key = exerciseKey(exercise.name)
                let repKey = "\(key)\u{0}\(set.kg!)", weightKey = "\(key)\u{0}\(set.reps!)"
                if reps[repKey] == nil { repOrder.append(repKey) }
                if weights[weightKey] == nil { weightOrder.append(weightKey) }
                if (reps[repKey]?.reps ?? -1) < set.reps! { reps[repKey] = evidence }
                if (weights[weightKey]?.kg ?? -1) < set.kg! { weights[weightKey] = evidence }
            } }
            for key in repOrder {
                let after = reps[key]!, before = bestReps[key]
                if let before, after.reps > before.reps { records.append(Improvement(kind: .reps, before: before, after: after)) }
                if before == nil || after.reps > before!.reps { bestReps[key] = after }
            }
            for key in weightOrder {
                let after = weights[key]!, before = bestWeight[key]
                if let before, after.kg > before.kg { records.append(Improvement(kind: .weight, before: before, after: after)) }
                if before == nil || after.kg > before!.kg { bestWeight[key] = after }
            }
        }
        return records.sorted { a, b in a.after.date == b.after.date ? a.after.sessionId > b.after.sessionId : a.after.date > b.after.date }
    }

    /// The latest improvement per exercise, newest first: the Personal records list.
    public var latestRecords: [Improvement] {
        var seen = Set<String>()
        return improvements.filter { seen.insert(exerciseKey($0.after.exercise)).inserted }
    }

    /// Volume per week for the last `weeks` weeks, oldest first, ending with the time's week.
    public func weeklyVolumes(_ weeks: Int = 8, at time: Int, calendar: Calendar = Calendars.local) -> [Double] {
        let current = weekStart(time, calendar: calendar)
        let starts = (0..<weeks).reversed().map { back in
            weekStart(millis(calendar.date(byAdding: .day, value: -7 * back, to: date(current))!), calendar: calendar)
        }
        var totals = [Int: Double]()
        for session in finished { totals[weekStart(session.finishedAt!, calendar: calendar), default: 0] += session.volume }
        return starts.map { totals[$0] ?? 0 }
    }
}
