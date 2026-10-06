import Foundation

/// Track's limits on training data, the website's (lib/data-limits.ts): what a saved copy may hold, what typing keeps,
/// and what the fields and messages say. Weights are in kg.
public enum Limits {
    public static let kg = 5000.0
    public static let reps = 1000
    public static let rir = 10
    public static let name = 100
    public static let notes = 500
    /// Sets in one exercise.
    public static let sets = 100
    public static let bodyweight = 20.0...400.0
    public static let restSeconds = 15...600
    public static let weeklyGoal = 1...7
    public static let poundsPerKilogram = 2.2046226218

    /// A kg range as the whole numbers it allows in the unit, as the website writes it: "0 to 5,000 kg",
    /// "45 to 881 lb" (44 lb is under 20 kg).
    public static func wholeRange(_ range: ClosedRange<Double>, _ unit: Settings.Unit) -> String {
        let factor = unit == .lb ? poundsPerKilogram : 1
        return "\(grouped(Int((range.lowerBound * factor).rounded(.up)))) to \(grouped(Int((range.upperBound * factor).rounded(.down)))) \(unit.rawValue)"
    }

    /// "1,000", in English whatever the phone's region (the website's wording).
    public static func grouped(_ value: Int) -> String {
        let format = NumberFormatter()
        format.numberStyle = .decimal
        format.locale = Locale(identifier: "en_US")
        return format.string(from: NSNumber(value: value)) ?? String(value)
    }
}
