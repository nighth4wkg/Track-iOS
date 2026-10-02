import Foundation
import Observation
import TrackCore

/// Where the person keeps their training: synced through their Track account, or only on this iPhone. Chosen once on
/// the first screen; local can turn on sync later in Settings.
enum StorageMode: String {
    case sync, local
}

/// The app's state: the training data (saved to this device after every change) and the storage choice.
@Observable
final class AppModel {
    private(set) var training: Training
    /// nil until the first screen's choice is made.
    private(set) var mode: StorageMode?
    /// Why the saved copy couldn't be read, if it couldn't. The app then starts empty without overwriting it.
    private(set) var loadError: String?

    private let file: TrainingFile?
    @ObservationIgnored private var canSave = true
    private static let modeKey = "track.storageMode"

    init(file: TrainingFile? = try? TrainingFile.standard()) {
        self.file = file
        mode = UserDefaults.standard.string(forKey: Self.modeKey).flatMap(StorageMode.init)
        do {
            training = try file?.load() ?? Training()
        } catch {
            training = Training()
            canSave = false
            loadError = "Your saved workouts couldn’t be read, so they were left untouched."
        }
    }

    func choose(_ choice: StorageMode) {
        mode = choice
        UserDefaults.standard.set(choice.rawValue, forKey: Self.modeKey)
    }

    /// Changes the training data and saves it on this device.
    func update(_ change: (inout Training) -> Void) {
        change(&training)
        training.editedAt = nowMillis()
        guard canSave, let file else { return }
        do { try file.save(training) } catch { loadError = "Couldn’t save on this iPhone. Free up some space and try again." }
    }
}
