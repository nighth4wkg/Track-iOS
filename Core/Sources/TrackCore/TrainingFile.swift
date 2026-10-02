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
