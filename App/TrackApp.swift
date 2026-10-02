import SwiftUI

@main
struct TrackApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if model.mode == nil { WelcomeView().transition(.opacity) } else { MainView().transition(.opacity) }
            }
            .environment(model)
            .tint(Palette.accent)
        }
    }
}
