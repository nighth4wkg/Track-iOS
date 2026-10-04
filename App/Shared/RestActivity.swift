import ActivityKit
import Foundation

/// The rest timer as a Live Activity (Dynamic Island and Lock Screen), shared by the app, which starts and ends it,
/// and the widget extension, which draws it. The countdown runs on its own from `until`; nothing updates it per second.
struct RestAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the rest ends.
        var until: Date
        /// The rest's full length, for the ring.
        var seconds: Int
        /// False between rests: the activity stays for the whole workout and says you're ready for the next set.
        var resting = true
    }
    /// The workout resting in, as "Upper".
    var workout: String
}
