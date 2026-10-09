import Foundation

/// The training data saved on this device: one JSON file, written whole and atomically, so a crash mid-save leaves the
/// last good copy. The same JSON the website keeps, so a backup from either one restores on the other.
public struct TrainingFile: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// The app's file in Application Support (kept in iCloud and computer backups of the iPhone).
    public static func standard() throws -> TrainingFile {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return TrainingFile(url: folder.appendingPathComponent("training.v1.json"))
    }

    /// The saved copy, or a fresh start when there is none yet. A file that can't be read is an error, never
    /// silently replaced, so data that a newer app version wrote isn't lost.
    public func load() throws -> Training {
        guard FileManager.default.fileExists(atPath: url.path) else { return Training() }
        return try Self.decode(Data(contentsOf: url))
    }

    /// Moves an unreadable copy aside (training.v1.unreadable-<time>.json), so a restored backup can be saved without
    /// destroying it.
    public func setAside(now: Int = nowMillis()) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent("training.v1.unreadable-\(now).json"))
    }

    public func save(_ training: Training) throws {
        try Self.encode(training).write(to: url, options: .atomic)
    }

    public static func decode(_ data: Data) throws -> Training {
        try JSONDecoder().decode(Training.self, from: data)
    }

    public static func encode(_ training: Training) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(training)
    }
}

extension Training {
    /// The website's checks on stored data (lib/training-schema.ts): numbers in range, done sets complete, unique ids,
    /// settings in range, finished workouts with a done set, and an active workout that isn't finished.
    public var isValid: Bool {
        let workouts = sessions + (active.map { [$0] } ?? [])
        let settingsOK = Limits.weeklyGoal.contains(settings.weeklyGoal) && Limits.restSeconds.contains(settings.restSeconds)
            && (settings.bodyweight.map { Limits.bodyweight.contains($0) } ?? true)
            && (settings.lifts.map(Self.validChoices) ?? true)
        let idsOK = Set(splits.map(\.id)).count == splits.count && Set(workouts.map(\.id)).count == workouts.count
        let sessionsOK = sessions.allSatisfy { ($0.finishedAt ?? .min) >= $0.startedAt && !$0.completedSets.isEmpty }
        let listsOK = (splits.map(\.exercises) + workouts.map(\.exercises)).allSatisfy(Self.validList)
        return version == 1 && settingsOK && idsOK && sessionsOK && listsOK && active?.finishedAt == nil
    }

    /// The website's limits on "counts as" choices: how many, key length in UTF-16 units, and the id's length.
    private static func validChoices(_ lifts: [String: String]) -> Bool {
        lifts.count <= Limits.liftChoices
            && lifts.allSatisfy { (1...Limits.liftKey).contains($0.key.utf16.count) && (1...Limits.name).contains($0.value.utf16.count) }
    }

    private static func validList(_ exercises: [Exercise]) -> Bool {
        let sets = exercises.flatMap(\.sets)
        guard Set(exercises.map(\.id)).count == exercises.count, Set(sets.map(\.id)).count == sets.count else { return false }
        return sets.allSatisfy { set in
            let numbers = (set.kg.map { (0...Limits.kg).contains($0) } ?? true) && (set.reps.map { (0...Limits.reps).contains($0) } ?? true)
            return numbers && (set.rir.map { (0...Limits.rir).contains($0) } ?? true) && (!set.done || set.isValid)
        }
    }
}
