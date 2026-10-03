import SwiftUI
import TrackCore

/// The app after the first screen: the website's four tabs on the system tab bar (Liquid Glass on iOS 26), the
/// workout over everything while it's open, the recap when one finishes, and a finished workout's detail.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var settingsOpen = ScreenshotMode.screen == "settings"

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            HomeView(settingsOpen: $settingsOpen)
                .tabItem { Label("Home", systemImage: "house") }.tag(AppTab.home)
            HistoryView(settingsOpen: $settingsOpen)
                .tabItem { Label("History", systemImage: "calendar") }.tag(AppTab.history)
            ProgressPage(settingsOpen: $settingsOpen)
                .tabItem { Label("Progress", systemImage: "chart.bar") }.tag(AppTab.progress)
            RankPage(settingsOpen: $settingsOpen)
                .tabItem { Label("Rank", systemImage: "medal") }.tag(AppTab.rank)
        }
        .tint(Palette.accent)
        .sensoryFeedback(.selection, trigger: model.tab)
        .sheet(isPresented: $settingsOpen) { SettingsView().trackOverlays() }
        .fullScreenCover(isPresented: $model.workoutOpen) { WorkoutView().trackOverlays().presentationBackground(.clear) }
        .fullScreenCover(item: $model.finished) { CompletionView(finished: $0).trackOverlays() }
        .sheet(item: $model.history) { HistoryDetail(session: $0).trackOverlays().presentationDetents([.medium, .large]) }
        .trackOverlays()
    }
}
