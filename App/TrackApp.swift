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
            // From the very first frame, so a Dark choice never flashes the system's light look (glass buttons first).
            .preferredColorScheme(model.training.settings.theme == .light ? .light : model.training.settings.theme == .dark ? .dark : nil)
            .onAppear { DialogWindow.install(model); Appearance.apply(model.training.settings.theme) }
            .onChange(of: model.training.settings.theme) { _, theme in Appearance.apply(theme) }
        }
    }
}
