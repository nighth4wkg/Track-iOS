import Foundation

// Sets: what counts as logged, the numbers as typed, and one-sided lifts (lib/training-validation.ts,
// training-input.ts, training-sides.ts).

public enum TrainingError: LocalizedError, Equatable {
    case activeWorkout, noExercises, noActiveWorkout, finishBeforeStart, nothingLogged, needWeightAndReps

    public var errorDescription: String? {
        switch self {
        case .activeWorkout: "Finish or discard the current workout first."
        case .noExercises: "Add at least one exercise before starting."
        case .noActiveWorkout: "No active workout."
        case .finishBeforeStart: "Workout cannot finish before it starts."
        case .nothingLogged: "Mark at least one set done to save this workout."
        case .needWeightAndReps: "Enter the weight and reps for this set first."
        }
    }
}

extension TrainingSet {
    /// Weight, positive reps and RIR, all in range: the set can be logged.
    public var isValid: Bool {
        guard let kg, let reps, let rir else { return false }
        return kg >= 0 && kg <= Limits.kg && reps > 0 && reps <= Limits.reps && rir >= 0 && rir <= Limits.rir
    }

    /// Marks the set done, or not. A blank RIR counts as 0 (nothing left in reserve).
    public func toggledDone() throws -> TrainingSet {
        if done { var set = self; set.done = false; return set }
        var set = self
        set.rir = rir ?? 0
        set.done = true
        guard set.isValid else { throw TrainingError.needWeightAndReps }
        return set
    }

    /// The set after editing its fields as typed. Editing keeps a done set done while it stays valid; it logs a new
    /// one only in auto mode, where changing the numbers is the signal.
    public func edited(weight: String, reps repsText: String, rir rirText: String, unit: Settings.Unit, autoLog: Bool = false) -> TrainingSet {
        // Auto mode logs a set once its RIR is filled in too (the last field), so it doesn't log mid-entry.
        let logging = done || (autoLog && !rirText.trimmingCharacters(in: .whitespaces).isEmpty)
        let kg = weight == Self.display(kg: self.kg, unit: unit) ? self.kg : Self.kilograms(from: weight, unit: unit)
        let reps = Self.wholeNumber(repsText)
        let rir = Self.wholeNumber(rirText) ?? (logging && rirText.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : nil)
        var next = self
        next.kg = kg.flatMap { $0.isFinite && $0 >= 0 && $0 <= Limits.kg ? $0 : nil }
        next.reps = reps.flatMap { $0 > 0 && $0 <= Limits.reps ? $0 : nil }
        next.rir = rir.flatMap { $0 >= 0 && $0 <= Limits.rir ? $0 : nil }
        next.done = false
        next.done = logging && next.isValid
        return next
    }

    /// Digits only, like the website's /^\d+$/ (no signs, decimals or spaces inside).
    public static func wholeNumber(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) else { return nil }
        return Int(trimmed)
    }

    /// The weight as shown in the chosen unit, up to two decimals, no trailing zeros ("" when empty).
    public static func display(kg: Double?, unit: Settings.Unit) -> String {
        guard let kg else { return "" }
        let value = ((kg * (unit == .lb ? Limits.poundsPerKilogram : 1)) * 100).rounded() / 100
        return value == value.rounded() ? String(Int(value)) : String(value)
    }

    /// A typed weight in kg, or nil when it isn't a plain decimal ("62,5" counts, as comma-decimal keypads type it).
    public static func kilograms(from text: String, unit: Settings.Unit) -> Double? {
        let decimal = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard decimal.range(of: #"^(?:\d+(?:\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil, let value = Double(decimal) else { return nil }
        return value / (unit == .lb ? Limits.poundsPerKilogram : 1)
    }
}

extension Session {
    /// The sets that count: marked done and valid. Carried-over numbers are only suggestions until then.
    public var completedSets: [TrainingSet] { exercises.flatMap { $0.sets.filter { $0.done && $0.isValid } } }

    /// Logged sets as counted: done and valid, a left and right pair once.
    public var loggedCount: Int {
        exercises.reduce(0) { $0 + Exercise.groups($1.sets.filter { $0.done && $0.isValid }).count }
    }

    /// Minutes from start to finish, at least 1 once finished.
    public var minutes: Int {
        guard let finishedAt, finishedAt >= startedAt else { return 0 }
        return max(1, Int((Double(finishedAt - startedAt) / 60000).rounded()))
    }
}

// MARK: One side at a time

extension Side {
    public var other: Side { self == .left ? .right : .left }
}

extension Exercise {
    /// Names that already say the lift is done one arm or leg at a time.
    static let oneSided = try! NSRegularExpression(pattern: #"\b(one|single|1)[ -]?(leg(ged)?|arm(ed)?|hand(ed)?)\b|\bunilateral\b|\bbulgarian\b|\bpistol\b"#)

    public var usesSides: Bool { sets.contains { $0.side != nil } }

    /// Which side the exercise starts on, or nil when its sets are two-sided.
    public var startingSide: Side? { sets.first { $0.side != nil }?.side }

    /// The side a newly added set takes: the opposite of the last set's, if the exercise is in sides.
    public var nextSide: Side? { sets.last?.side?.other ?? (usesSides ? .left : nil) }

    /// A set added to the exercise: the last set's weight and reps to start from (not logged), RIR left for you to
    /// fill in, on the next side.
    public var nextSet: TrainingSet {
        TrainingSet(kg: sets.last?.kg, reps: sets.last?.reps, side: nextSide)
    }

    /// The sets as counted: a left and the right beside it (either order) are one set.
    public var setGroups: [[TrainingSet]] { Exercise.groups(sets) }

    static func groups(_ sets: [TrainingSet]) -> [[TrainingSet]] {
        var groups: [[TrainingSet]] = [], index = 0
        while index < sets.count {
            let set = sets[index]
            if let side = set.side, index + 1 < sets.count, sets[index + 1].side == side.other {
                groups.append([set, sets[index + 1]]); index += 2
            } else { groups.append([set]); index += 1 }
        }
        return groups
    }

    public var setCount: Int { setGroups.count }
    /// Sets with every side ticked done.
    public var doneCount: Int { setGroups.filter { $0.allSatisfy(\.done) }.count }

    /// Each stored set's label: its number, with its side when one-sided ("1L", "1R").
    public var setLabels: [String] {
        setGroups.enumerated().flatMap { index, group in group.map { "\(index + 1)\($0.side.map { $0 == .left ? "L" : "R" } ?? "")" } }
    }

    /// One more set: a pair when one-sided (or the missing side, if the last set has only one).
    public func addingSet() -> Exercise {
        var exercise = self
        exercise.sets.append(exercise.nextSet)
        if let last = exercise.setGroups.last, last.count == 1, last[0].side != nil { exercise.sets.append(exercise.nextSet) }
        return exercise
    }

    /// Both → Left first → Right first → Both. Turning sides on makes each set a pair (the right takes the left's
    /// weight and reps to start); turning them off keeps each pair's first side, and the other only if it was done.
    public func cyclingSides() -> Exercise {
        var exercise = self
        switch startingSide {
        case nil:
            exercise.sets = sets.flatMap { set -> [TrainingSet] in
                var left = set, right = set
                left.side = .left
                right.id = newID(); right.done = false; right.side = .right
                return [left, right]
            }
        case .left?:
            for index in exercise.sets.indices { exercise.sets[index].side = exercise.sets[index].side?.other }
        case .right?:
            exercise.sets = setGroups.flatMap { group -> [TrainingSet] in
                let plain = group.map { set -> TrainingSet in var set = set; set.side = nil; return set }
                guard plain.count == 2 else { return plain }
                return plain[1].done && !plain[0].done ? [plain[1]] : plain[1].done ? plain : [plain[0]]
            }
        }
        return exercise
    }

    /// A new exercise named as one-sided starts in sides.
    public static func firstSide(for name: String) -> Side? {
        let lower = name.lowercased()
        return oneSided.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) == nil ? nil : .left
    }

    /// A new exercise with three sets (three pairs when its name says it is one-sided), as the PWA's withSets.
    public static func new(named name: String) -> Exercise {
        var exercise = Exercise(name: name.trimmingCharacters(in: .whitespacesAndNewlines), sets: [TrainingSet(side: firstSide(for: name))])
        if exercise.sets[0].side != nil { exercise.sets.append(exercise.nextSet) }
        while exercise.setCount < 3 { exercise = exercise.addingSet() }
        return exercise
    }
}

extension Array where Element == Exercise {
    /// The sets planned, as counted.
    public var plannedCount: Int { reduce(0) { $0 + $1.setCount } }
    public var doneCount: Int { reduce(0) { $0 + $1.doneCount } }
}

extension Array {
    /// The array with the item at `from` moved to `to`'s place; unchanged if either is out of range.
    public func moved(_ from: Int, to: Int) -> [Element] {
        guard indices.contains(from), indices.contains(to) else { return self }
        var next = self
        next.insert(next.remove(at: from), at: to)
        return next
    }
}
