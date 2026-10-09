import Foundation

// The training data, exactly as the website saves it (lib/training-schema.ts, `track.training.v1`), so a copy moves
// between the iPhone and the website unchanged: the same keys, `null` where the website writes null, and optional
// keys left out when absent. Times are milliseconds since 1970, like JavaScript's Date.now().

public enum Side: String, Codable, Sendable { case left, right }

public struct TrainingSet: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kg: Double?
    public var reps: Int?
    public var rir: Int?
    public var done: Bool
    /// Done one arm or leg at a time; absent for two-sided sets.
    public var side: Side?

    public init(id: String = newID(), kg: Double? = nil, reps: Int? = nil, rir: Int? = nil, done: Bool = false, side: Side? = nil) {
        self.id = id; self.kg = kg; self.reps = reps; self.rir = rir; self.done = done; self.side = side
    }

    // kg, reps and rir are always written, as null when empty; side only when set.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kg, forKey: .kg)
        try c.encode(reps, forKey: .reps)
        try c.encode(rir, forKey: .rir)
        try c.encode(done, forKey: .done)
        try c.encodeIfPresent(side, forKey: .side)
    }
}

public struct Exercise: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var sets: [TrainingSet]

    public init(id: String = newID(), name: String, sets: [TrainingSet]) {
        self.id = id; self.name = name; self.sets = sets
    }
}

public struct Split: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var exercises: [Exercise]

    public init(id: String = newID(), name: String, exercises: [Exercise] = []) {
        self.id = id; self.name = name; self.exercises = exercises
    }
}

public struct QuestAward: Codable, Equatable, Sendable {
    public var questId: String
    public var earnedAt: Int
    public var xp: Int
}

/// A workout: the active one (finishedAt nil) or a finished one in the history.
public struct Session: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var exercises: [Exercise]
    public var splitId: String
    public var startedAt: Int
    public var finishedAt: Int?
    public var xpEarned: Int?
    public var xpBase: Int?
    public var xpBonus: Int?
    public var questAwards: [QuestAward]?
    public var notes: String?

    public init(id: String = newID(), name: String, exercises: [Exercise], splitId: String, startedAt: Int, finishedAt: Int? = nil) {
        self.id = id; self.name = name; self.exercises = exercises; self.splitId = splitId
        self.startedAt = startedAt; self.finishedAt = finishedAt
    }

    // finishedAt is always written (null while active); the award and note fields only when present.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(exercises, forKey: .exercises)
        try c.encode(splitId, forKey: .splitId)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(finishedAt, forKey: .finishedAt)
        try c.encodeIfPresent(xpEarned, forKey: .xpEarned)
        try c.encodeIfPresent(xpBase, forKey: .xpBase)
        try c.encodeIfPresent(xpBonus, forKey: .xpBonus)
        try c.encodeIfPresent(questAwards, forKey: .questAwards)
        try c.encodeIfPresent(notes, forKey: .notes)
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public enum Unit: String, Codable, Sendable { case kg, lb }
    public enum Theme: String, Codable, Sendable { case light, dark, system, liquid }
    public enum LogSets: String, Codable, Sendable { case auto, manual }

    public var unit: Unit = .kg
    public var weeklyGoal = 3
    public var restSeconds = 90
    public var theme: Theme = .system
    /// In kg: only strength ranks use it.
    public var bodyweight: Double?
    /// Absent means auto.
    public var logSets: LogSets?
    /// What an exercise name counts as on Rank, keyed by LiftTable.nameKey: a lift id, or "none". Ids this version
    /// doesn't know (from a newer one) are kept and ignored.
    public var lifts: [String: String]?

    public init() {}
}

public struct Training: Codable, Equatable, Sendable {
    public var version = 1
    public var splits: [Split] = []
    public var sessions: [Session] = []
    public var questVersion = 1
    public var active: Session?
    public var settings = Settings()
    public var restUntil: Int?
    /// When this copy was last edited on its device; the newer copy wins when two devices changed the same thing.
    public var editedAt: Int?

    public init() {}

    enum CodingKeys: String, CodingKey { case version, splits, sessions, questVersion, active, settings, restUntil, editedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        splits = try c.decode([Split].self, forKey: .splits)
        sessions = try c.decode([Session].self, forKey: .sessions)
        // Older copies have no questVersion: the website reads that as 0.
        questVersion = try c.decodeIfPresent(Int.self, forKey: .questVersion) ?? 0
        active = try c.decodeIfPresent(Session.self, forKey: .active)
        settings = try c.decode(Settings.self, forKey: .settings)
        restUntil = try c.decodeIfPresent(Int.self, forKey: .restUntil)
        editedAt = try c.decodeIfPresent(Int.self, forKey: .editedAt)
    }

    // active and restUntil are always written (null when empty), editedAt only once set.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(splits, forKey: .splits)
        try c.encode(sessions, forKey: .sessions)
        try c.encode(questVersion, forKey: .questVersion)
        try c.encode(active, forKey: .active)
        try c.encode(settings, forKey: .settings)
        try c.encode(restUntil, forKey: .restUntil)
        try c.encodeIfPresent(editedAt, forKey: .editedAt)
    }
}

/// Identifiers in the website's form: a lowercase UUID, as crypto.randomUUID() makes.
public func newID() -> String { UUID().uuidString.lowercased() }

/// Now, in the website's time unit.
public func nowMillis() -> Int { Int((Date().timeIntervalSince1970 * 1000).rounded()) }
