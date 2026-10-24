import SwiftUI

@main
struct TrackApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        RestIntent.change = { seconds in
            await MainActor.run { model.changeRest(by: seconds) }
            await RestLive.pending?.value
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if model.mode == nil { WelcomeView().transition(.opacity) } else { MainView().transition(.opacity) }
            }
            .environment(model)
            .tint(Palette.accent)
            .onAppear { DialogWindow.install(model); TestSeed.apply(model); FrameLog.install() }
            .task { await PerfDrive.run(model) }
            // The rest Live Activity: back to the workout in progress.
            .onOpenURL { url in if url.host == "workout", model.training.active != nil { model.workoutOpen = true } }
        }
    }
}
