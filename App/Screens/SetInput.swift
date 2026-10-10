import TrackCore

extension TrainingSet {
    /// What's wrong with a set's typed numbers, worded as on the website: every field out of range (each gets a red
    /// edge) and the first one's message (shown under the row).
    static func inputError(weight: String, reps: String, rir: String, unit: TrackCore.Settings.Unit) -> (fields: Set<String>, message: String)? {
        var bad: [(field: String, message: String)] = []
        if !weight.isEmpty, kilograms(from: weight, unit: unit).map({ $0 <= Limits.kg }) != true {
            bad.append(("kg", "Enter a weight from \(Limits.wholeRange(0...Limits.kg, unit))."))
        }
        if !reps.isEmpty, wholeNumber(reps).map({ (1...Limits.reps).contains($0) }) != true {
            bad.append(("reps", "Reps must be a whole number from 1 to \(Limits.grouped(Limits.reps))."))
        }
        if !rir.isEmpty, wholeNumber(rir).map({ (0...Limits.rir).contains($0) }) != true {
            bad.append(("rir", "RIR must be a whole number from 0 to \(Limits.rir)."))
        }
        return bad.first.map { (Set(bad.map(\.field)), $0.message) }
    }
}
