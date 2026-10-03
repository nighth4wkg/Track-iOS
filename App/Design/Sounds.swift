import AudioToolbox
import Foundation

/// The moments Track makes a sound, each played with its haptic. The sounds are iOS's own interface sounds (the
/// keyboard click, Tink, Tock, the Apple Pay chime…), already on the iPhone. Each moment has a default, and any of
/// them can be swapped in Settings.
enum Sound: String, CaseIterable, Identifiable {
    case setDone, setUndone, newBest, restDone, workoutSaved, levelUp, delete
    var id: String { rawValue }

    var title: String {
        switch self {
        case .setDone: "Set done"
        case .setUndone: "Set undone"
        case .newBest: "New best"
        case .restDone: "Rest over"
        case .workoutSaved: "Workout saved"
        case .levelUp: "Level up"
        case .delete: "Delete"
        }
    }

    /// The default: the first of these this iPhone has.
    fileprivate var defaults: [String] {
        switch self {
        case .setDone: ["key_press_click.caf", "Tock.caf"]
        case .setUndone: ["key_press_delete.caf", "Tink.caf"]
        case .newBest: ["Tink.caf"]
        case .restDone: ["jbl_confirm.caf", "SIMToolkitPositiveACK.caf", "Tink.caf"]
        case .workoutSaved: ["payment_success.caf", "Tink.caf"]
        case .levelUp: ["payment_success.caf", "Tink.caf"]
        case .delete: ["Tock.caf", "key_press_delete.caf"]
        }
    }
}

enum Sounds {
    private static let folder = URL(fileURLWithPath: "/System/Library/Audio/UISounds")
    private static var loaded: [String: SystemSoundID] = [:]

    /// Every interface sound on this iPhone, as paths in iOS's sound folder ("Tink.caf", "nano/…").
    static let all: [String] = {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return files.filter { ["caf", "wav", "aiff", "m4a"].contains($0.pathExtension.lowercased()) }
            .map { String($0.path.dropFirst(folder.path.count + 1)) }
            .sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
    }()

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "track.sounds") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "track.sounds") }
    }

    /// The moment's sound, or nil for none.
    static func choice(_ sound: Sound) -> String? {
        if let saved = UserDefaults.standard.string(forKey: "track.sound." + sound.rawValue) { return saved.isEmpty ? nil : saved }
        return sound.defaults.first(where: all.contains)
    }

    static func choose(_ file: String?, for sound: Sound) {
        UserDefaults.standard.set(file ?? "", forKey: "track.sound." + sound.rawValue)
    }

    /// Plays the moment's sound (if sounds are on). iOS keeps it quiet with the silent switch and mixes it with music.
    static func play(_ sound: Sound) {
        guard enabled, let file = choice(sound) else { return }
        preview(file)
    }

    static func preview(_ file: String) {
        var id = loaded[file] ?? 0
        if id == 0 {
            AudioServicesCreateSystemSoundID(folder.appendingPathComponent(file) as CFURL, &id)
            loaded[file] = id
        }
        AudioServicesPlaySystemSound(id)
    }

    /// "key_press_click.caf" → "Key press click"; a watch sound says so.
    static func name(_ file: String) -> String {
        let base = (file as NSString).lastPathComponent.replacingOccurrences(of: "." + (file as NSString).pathExtension, with: "")
        var words = ""
        for (index, character) in base.enumerated() {
            if character == "_" || character == "-" { words.append(" "); continue }
            if index > 0, character.isUppercase, words.last.map({ $0.isLowercase }) == true { words.append(" ") }
            words.append(character)
        }
        let spaced = words.split(separator: " ").joined(separator: " ").lowercased()
        let title = spaced.prefix(1).uppercased() + spaced.dropFirst()
        return file.hasPrefix("nano/") ? title + " (Watch)" : file.contains("/") ? title + " (" + (file as NSString).deletingLastPathComponent + ")" : title
    }
}
