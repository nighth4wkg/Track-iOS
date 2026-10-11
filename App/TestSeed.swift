import Foundation
import TrackCore

/// For the UI tests (UITests/, .github/workflows/uitests.yml): TRACK_SEED hands over the training each test starts
/// from. Without it nothing here runs.
enum TestSeed {
    static func apply(_ model: AppModel) {
        if let json = ProcessInfo.processInfo.environment["TRACK_SEED"], let seed = try? TrainingFile.decode(Data(json.utf8)) {
            model.restore(seed)
        }
        // For profiling (.github/workflows/profile.yml): straight into a workout, nothing tapped.
        if ProcessInfo.processInfo.arguments.contains("-perfOpen"), model.training.active == nil, let split = model.training.splits.first {
            model.start(split)
        }
    }
}
