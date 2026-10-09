import Foundation

/// Exercise names to lifts, from Resources/lifts.json: the website's lib/lifts.json word for word, read the same way as
/// lib/lift-detection.ts, so a name counts as the same lift in both apps (Tests/…/Fixtures/lift-names.txt checks it).
public struct Lift: Decodable, Sendable {
    public let id: String
    public let name: String
    /// The muscle it mainly trains (Chest, Biceps, Quads…), and the ones it also works.
    public let part: String
    let helpsList: [String]?
    let match: String
    /// Estimated one-rep max as a multiple of bodyweight for Novice, Solid, Strong and Elite; nil = never ranked.
    public let at: [Double]?
    /// The standard is one side's weight.
    public let perSide: Bool?
    /// The movement only exists on a machine or cable.
    let machine: Bool?
    /// Only when the name says that equipment ("dumbbell").
    let gear: String?
    /// With a dumbbell in each hand, their total counts this many times against the barbell standard.
    let pair: Double?
    /// The share of bodyweight moved, plus any added weight (or minus assistance).
    public let bodyweight: Double?
    /// More parts whose rank groups it counts toward (full-body lifts).
    public let also: [String]?

    public var helps: [String] { helpsList ?? [] }
    /// The rank group it counts toward (Chest, Back, Shoulders, Arms, Legs), or nil (Core).
    public var group: String? { LiftTable.group(of: part) }
    /// Every rank group it counts toward: its part's, then those of its `also` parts.
    public var groups: [String] {
        ([part] + (also ?? [])).compactMap(LiftTable.group(of:)).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, part, helpsList = "helps", match, at, perSide, machine, gear, pair, bodyweight, also
    }
}

/// What a name counts as: a lift, work that never counts (cardio, stretching), or a name it doesn't know.
public enum Detection: Sendable {
    case lift(Lift), ignore, unknown

    public var lift: Lift? { if case .lift(let lift) = self { lift } else { nil } }
}

public enum LiftTable {
    struct File: Decodable {
        let parts: [[String?]]
        let maxReps: Int
        let machineLoad: Double
        let ignore: String
        let gear: [String: String]
        let words: [String: String]
        let phrases: [[String]]
        let lifts: [Lift]
    }

    // swiftlint:disable:next force_try
    static let file: File = try! JSONDecoder().decode(File.self, from: Data(contentsOf: Bundle.module.url(forResource: "lifts", withExtension: "json")!))
    /// Each muscle and its rank group, in the table's order.
    public static let parts: [(part: String, group: String?)] = file.parts.map { ($0[0] ?? "", $0.count > 1 ? $0[1] : nil) }
    /// The rank groups, in order: Chest, Back, Shoulders, Arms, Legs.
    public static let groups: [String] = parts.compactMap(\.group).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    public static let lifts = file.lifts
    static let patterns = Dictionary(uniqueKeysWithValues: file.lifts.map { ($0.id, regex($0.match)) })
    static let gear = file.gear.mapValues(regex)
    static let ignore = regex(file.ignore)
    static let words = file.words
    static let phrases = file.phrases.map { (nameKey($0[0]), $0[1]) }
    static var maxReps: Int { file.maxReps }
    static var machineLoad: Double { file.machineLoad }

    public static func group(of part: String) -> String? { parts.first { $0.part == part }?.group }
    public static func lift(id: String) -> Lift? { lifts.first { $0.id == id } }

    // swiftlint:disable:next force_try
    static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }

    static func matches(_ regex: NSRegularExpression?, _ text: String) -> Bool {
        regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static let marks = regex(#"[\u0300-\u036f]"#), quotes = regex(#"['\u2019\u0060]"#), gaps = regex(#"[^\p{L}\p{M}\p{N}]+"#)
    private static let latinThenOther = regex(#"([a-z0-9])([^\p{ASCII}\p{Script=Latin}])"#)
    private static let otherThenLatin = regex(#"([^\p{ASCII}\p{Script=Latin}])([a-z0-9])"#)

    /// A name as stored and compared: accents and punctuation gone, lower case, words split from other scripts. The key
    /// the user's choices are saved under, so it must stay stable (and equal the website's).
    public static func nameKey(_ name: String) -> String {
        var text = name.decomposedStringWithCompatibilityMapping.lowercased()
        text = replace(marks, in: text, with: "")
        text = replace(quotes, in: text, with: "")
        text = replace(gaps, in: text, with: " ")
        text = replace(latinThenOther, in: text, with: "$1 $2")
        text = replace(otherThenLatin, in: text, with: "$1 $2")
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// The key with other languages' phrases and shorthand swapped for the standard words the lifts match.
    static func matchKey(_ name: String) -> String {
        var text = " \(nameKey(name)) "
        for (from, to) in phrases { text = text.replacingOccurrences(of: from, with: " \(to) ", options: .literal) }
        return text.split(separator: " ").map { words[String($0)] ?? String($0) }.joined(separator: " ")
    }

    /// What the name itself says, ignoring any choice.
    public static func detect(_ name: String) -> Detection {
        let key = matchKey(name)
        if matches(ignore, key) { return .ignore }
        let dumbbell = matches(gear["dumbbell"], key)
        return lifts.first { ($0.gear == nil || dumbbell) && matches(patterns[$0.id], key) }.map(Detection.lift) ?? .unknown
    }

    /// What the name counts as: the user's choice if they made one (and it still exists), else what it says.
    public static func lift(for name: String, choices: [String: String] = [:]) -> Detection {
        let choice = choices[nameKey(name)]
        if choice == "none" { return .ignore }
        return choice.flatMap(lift(id:)).map(Detection.lift) ?? detect(name)
    }

    /// How the logged weight turns into load on the lift's standard, from the equipment the name says.
    static func load(for lift: Lift, name: String) -> (oneSided: Bool, sign: Double, scale: Double) {
        let key = matchKey(name)
        let oneSided = matches(Exercise.oneSided, key)
        let machine = !matches(gear["free"], key) && (lift.machine == true || matches(gear["machine"], key))
        let sign: Double = lift.bodyweight != nil && matches(gear["assisted"], key) ? -1 : 1
        // One side's standard, two-handed implement: each side takes half. Two dumbbells: both count, scaled to the bar
        // (one-sided, it's taken as one dumbbell, and the side counts double instead).
        let shared = lift.perSide == true && !oneSided && matches(gear["shared"], key) && !matches(gear["dumbbell"], key)
        let paired = lift.pair.flatMap { pair in !oneSided && matches(gear["pair"], key) ? 2 * pair : nil }
        let scale = (shared ? 0.5 : paired ?? 1) * (machine && lift.bodyweight == nil ? machineLoad : 1)
        return (oneSided, sign, scale)
    }
}
