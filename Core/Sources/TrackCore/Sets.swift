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
        return kg >= 0 && kg <= 5000 && reps > 0 && reps <= 1000 && rir >= 0 && rir <= 10
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
        let logging = done || autoLog
        let kg = weight == Self.display(kg: self.kg, unit: unit) ? self.kg : Self.kilograms(from: weight, unit: unit)
        let reps = Self.wholeNumber(repsText)
        let rir = Self.wholeNumber(rirText) ?? (logging && rirText.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : nil)
        var next = self
        next.kg = kg.flatMap { $0.isFinite && $0 >= 0 && $0 <= 5000 ? $0 : nil }
        next.reps = reps.flatMap { $0 > 0 && $0 <= 1000 ? $0 : nil }
        next.rir = rir.flatMap { $0 >= 0 && $0 <= 10 ? $0 : nil }
        next.done = false
        next.done = logging && next.isValid
        return next
    }

    static let poundsPerKilogram = 2.2046226218

    /// Digits only, like the website's /^\d+$/ (no signs, decimals or spaces inside).
    public static func wholeNumber(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) else { return nil }
        return Int(trimmed)
    }

    /// The weight as shown in the chosen unit, up to two decimals, no trailing zeros ("" when empty).
    public static func display(kg: Double?, unit: Settings.Unit) -> String {
        guard let kg else { return "" }
        let value = ((kg * (unit == .lb ? poundsPerKilogram : 1)) * 100).rounded() / 100
        return value == value.rounded() ? String(Int(value)) : String(value)
    }

    /// A typed weight in kg, or nil when it isn't a plain decimal.
    public static func kilograms(from text: String, unit: Settings.Unit) -> Double? {
        let decimal = text.trimmingCharacters(in: .whitespaces)
        guard decimal.range(of: #"^(?:\d+(?:\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil, let value = Double(decimal) else { return nil }
        return value / (unit == .lb ? poundsPerKilogram : 1)
    }
}

extension Session {
    /// The sets that count: marked done and valid. Carried-over numbers are only suggestions until then.
    public var completedSets: [TrainingSet] { exercises.flatMap { $0.sets.filter { $0.done && $0.isValid } } }

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
    static let oneSided = try! NSRegularExpression(pattern: #"\b(one|single)[ -](leg(ged)?|arm(ed)?)\b|\bunilateral\b|\bbulgarian\b|\bpistol\b"#)

    public var usesSides: Bool { sets.contains { $0.side != nil } }

    /// Which side the exercise starts on, or nil when its sets are two-sided.
    public var startingSide: Side? { sets.first { $0.side != nil }?.side }

    /// Cycles Both → Left first → Right first → Both. Sets alternate from the starting side; Both clears every tag.
    public func togglingSides() -> Exercise {
        let start: Side? = startingSide == nil ? .left : startingSide == .left ? .right : nil
        var exercise = self
        for index in exercise.sets.indices { exercise.sets[index].side = start.map { index % 2 == 0 ? $0 : $0.other } }
        return exercise
    }

    /// The side a newly added set takes: the opposite of the last set's, if the exercise is in sides.
    public var nextSide: Side? { sets.last?.side?.other ?? (usesSides ? .left : nil) }

    /// A new exercise named as one-sided starts in sides.
    public static func firstSide(for name: String) -> Side? {
        let lower = name.lowercased()
        return oneSided.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) == nil ? nil : .left
    }

    /// A new exercise with one empty set.
    public static func new(named name: String) -> Exercise {
        Exercise(name: name.trimmingCharacters(in: .whitespacesAndNewlines), sets: [TrainingSet(side: firstSide(for: name))])
    }
}

extension Array {
    /// The array with the item at `index` moved by `direction` places; unchanged if either end is out of range.
    public func moving(_ index: Int, by direction: Int) -> [Element] {
        let destination = index + direction
        guard indices.contains(index), indices.contains(destination) else { return self }
        var next = self
        next.insert(next.remove(at: index), at: destination)
        return next
    }
}
