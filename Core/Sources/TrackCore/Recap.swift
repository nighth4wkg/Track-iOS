import Foundation

// The finished-workout recap (lib/workout-recap.ts), live records while logging (lib/records-live.ts), history
// filters (lib/history.ts), training days this week, and the website's duration wording (lib/format.ts).

/// "45 min", "1h", "2h 5m", "20d 1h".
public func trainingDuration(_ minutes: Int) -> String {
    let total = max(0, minutes)
    if total < 60 { return "\(total) min" }
    let hours = total / 60
    if hours < 24 { return total % 60 == 0 ? "\(hours)h" : "\(hours)h \(total % 60)m" }
    return "\(hours / 24)d" + (hours % 24 == 0 ? "" : " \(hours % 24)h")
}

public struct Recap: Sendable {
    public let session: Session
    public let previous: Session?
    public let volume: Double
    /// Against the split's previous workout; nil for a first result.
    public let volumeDelta: Double?
    public let sets: Int
    public let reps: Int
    public let minutes: Int
    public let best: (exercise: String, set: TrainingSet)?
    public let records: [Improvement]
    public let observation: String
}

extension Array where Element == Session {
    /// What a finished workout added up to, against the same split's previous one.
    public func recap(of sessionId: String) -> Recap? {
        guard let session = first(where: { $0.id == sessionId }) else { return nil }
        let previous = filter { $0.id != session.id && $0.splitId == session.splitId && $0.finishedAt != nil && $0.finishedAt! <= session.finishedAt! }
            .max { $0.finishedAt! < $1.finishedAt! }
        var best: (exercise: String, set: TrainingSet)?
        for exercise in session.exercises { for set in exercise.sets where set.done && set.kg != nil && set.reps != nil {
            if best == nil || set.kg! > best!.set.kg! || (set.kg == best!.set.kg && set.reps! > best!.set.reps!) { best = (exercise.name, set) }
        } }
        let sets = session.completedSets
        return Recap(session: session, previous: previous, volume: session.volume,
                     volumeDelta: previous.map { session.volume - $0.volume }, sets: sets.count,
                     reps: sets.reduce(0) { $0 + $1.reps! }, minutes: session.minutes, best: best,
                     records: improvements.filter { $0.after.sessionId == session.id },
                     observation: Self.observation(session, previous))
    }

    private struct Stats { var name: String; var volume: Double; var sets: Int; var reps: Int; var rir: Double }

    private static func stats(_ session: Session) -> [(String, Stats)] {
        session.exercises.map { exercise in
            let sets = exercise.sets.filter { $0.done && $0.kg != nil && $0.reps != nil && $0.rir != nil }
            return (exerciseKey(exercise.name), Stats(name: exercise.name, volume: sets.reduce(0) { $0 + $1.kg! * Double($1.reps!) },
                                                      sets: sets.count, reps: sets.reduce(0) { $0 + $1.reps! },
                                                      rir: sets.isEmpty ? 0 : Double(sets.reduce(0) { $0 + $1.rir! }) / Double(sets.count)))
        }
    }

    /// One plain sentence on what changed most since last time.
    static func observation(_ current: Session, _ previous: Session?) -> String {
        guard let previous else { return "First result saved. Next time, compare load, reps, and total work." }
        let before = Dictionary(stats(previous), uniquingKeysWith: { $1 })
        let changes = stats(current).map { key, item -> (Stats, Stats?, Int?) in
            let old = before[key]
            return (item, old, old.flatMap { $0.volume > 0 ? Int(((item.volume - $0.volume) / $0.volume * 100).rounded()) : nil })
        }
        // Stable: on a tie the earlier exercise wins, as the website's sort keeps it.
        guard let (item, oldValue, change) = changes.enumerated().max(by: { a, b in
            abs(a.element.2 ?? 0) == abs(b.element.2 ?? 0) ? a.offset > b.offset : abs(a.element.2 ?? 0) < abs(b.element.2 ?? 0)
        })?.element else { return "Workout saved. Keep the next session consistent for a useful comparison." }
        guard let old = oldValue else { return "\(item.name) was new today. Its baseline is now saved." }
        let name = item.name
        guard let percent = change, percent != 0 else {
            if item.rir < old.rir { return "Same \(name) volume, with sets closer to failure." }
            if item.rir > old.rir { return "Same \(name) volume, with more reps left in reserve." }
            if item.reps < old.reps { return "Same \(name) volume in fewer reps means heavier loading." }
            if item.reps > old.reps { return "Same \(name) volume with more, lighter reps." }
            return "\(name) matched your previous load, reps, and effort."
        }
        if percent > 0 {
            if item.sets > old.sets { let extra = item.sets - old.sets; return "\(name) added volume through \(extra) extra \(extra == 1 ? "set" : "sets")." }
            if item.reps > old.reps { return "\(name) added reps without adding sets." }
            if item.reps == old.reps { return "\(name) moved more weight with the same total reps." }
            if percent >= 30 { return "\(name) volume jumped \(percent)%. Give recovery extra attention." }
            return "\(name) volume rose \(percent)%. A steady overload step."
        }
        if item.sets < old.sets { let fewer = old.sets - item.sets; return "\(name) volume was lower after \(fewer) fewer \(fewer == 1 ? "set" : "sets")." }
        if item.reps < old.reps { return "\(name) volume was lower because total reps dropped." }
        return "\(name) volume fell \(abs(percent))%."
    }

    /// The days (as "2026-10-02") with a finished workout in the time's week: the ring counts these.
    public func trainingDays(inWeekOf time: Int, calendar: Calendar = Calendars.local) -> Set<String> {
        Set(inWeek(of: time, calendar: calendar).map { dayKey($0.finishedAt!, calendar: calendar) })
    }

    /// Finished workouts matching every word (in the name or any exercise) and the day range ("2026-09-01"), newest first.
    public func filtered(query: String, from: String = "", to: String = "", calendar: Calendar = Calendars.local) -> [Session] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
        return finished.filter { session in
            let day = dayKey(session.finishedAt!, calendar: calendar)
            if !from.isEmpty, day < from { return false }
            if !to.isEmpty, day > to { return false }
            let text = ([session.name] + session.exercises.map(\.name)).joined(separator: " ").lowercased()
            return terms.allSatisfy { text.contains($0) }
        }
        .sorted { a, b in a.finishedAt! == b.finishedAt! ? a.id < b.id : a.finishedAt! > b.finishedAt! }
    }
}

// MARK: Live records

/// A logged set that beats every earlier result: what kind of best, and what it beat.
public enum LiveRecord: Equatable, Sendable {
    case heaviest(previousKg: Double)
    case weightForReps(previousKg: Double)
    case repsForWeight(previousReps: Int)
    case repsAtOrAbove(previousReps: Int)
}

/// Each exercise's earlier results (weight × reps), computed once per workout.
public struct RecordBests: Sendable, Identifiable {
    /// New for each working out, so screens can tell a changed history at a glance.
    public let id = UUID()
    var points: [String: [(kg: Double, reps: Int)]] = [:]

    public init(_ sessions: [Session]) {
        for session in sessions where session.finishedAt != nil {
            for exercise in session.exercises { for set in exercise.sets where set.done && set.isValid {
                points[exerciseKey(exercise.name), default: []].append((set.kg!, set.reps!))
            } }
        }
    }

    /// A set is a new best when no earlier set (in history, or above it today) matched or beat it on both weight and
    /// reps, or it's heavier at the same reps, or more reps at the same weight. A first-ever set never counts.
    public func record(for exercise: String, _ set: TrainingSet, earlierToday: [TrainingSet] = []) -> LiveRecord? {
        guard set.done, set.isValid, let history = points[exerciseKey(exercise)] else { return nil }
        let today = earlierToday.filter { $0.done && $0.isValid }.map { (kg: $0.kg!, reps: $0.reps!) }
        let kg = set.kg!, reps = set.reps!
        if today.contains(where: { $0.kg >= kg && $0.reps >= reps }) { return nil }
        let all = history + today
        let maxKg = all.map(\.kg).max() ?? 0
        if kg > maxKg { return .heaviest(previousKg: maxKg) }
        if let heaviest = all.filter({ $0.reps == reps }).map(\.kg).max(), kg > heaviest { return .weightForReps(previousKg: heaviest) }
        if let most = all.filter({ $0.kg == kg }).map(\.reps).max(), reps > most { return .repsForWeight(previousReps: most) }
        if !all.contains(where: { $0.kg >= kg && $0.reps >= reps }) {
            return .repsAtOrAbove(previousReps: all.filter { $0.kg >= kg }.map(\.reps).max() ?? 0)
        }
        return nil
    }
}
