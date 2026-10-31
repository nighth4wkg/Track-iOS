import SwiftUI
import TrackCore

@main
struct TrackApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        RestIntent.change = { seconds in
            await MainActor.run { if seconds == 0 { model.skipRest() } else { model.shiftRest(by: seconds) } }
            await RestLive.pending?.value
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if model.mode == nil { WelcomeScreen() } else { Shell() }
            }
            .environment(model)
            .tint(Palette.accent)
            .preferredColorScheme(.dark)
            .onAppear {
                TestSeed.apply(model)
                FrameLog.install()
                TouchLog.install()
                // The library's and your own exercises' muscles worked out off the main thread, ahead of the picker,
                // the workout's cards and the ranks.
                let names = Catalog.names + model.training.sessions.flatMap { $0.exercises.map(\.name) }
                Task.detached(priority: .utility) { LiftTable.warm(names) }
            }
            // The rest Live Activity: back to the workout in progress.
            .onOpenURL { url in if url.host == "workout", model.training.active != nil { model.workoutOpen = true } }
        }
    }
}
