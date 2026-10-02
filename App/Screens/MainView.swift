import SwiftUI
import TrackCore

/// The app after the first screen: the four tabs of the website on the system tab bar (Liquid Glass on iOS 26), the
/// workout over everything while it's open, and the summary when one finishes.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var settingsOpen = false

    var body: some View {
        @Bindable var model = model
        TabView {
            HomeView(settingsOpen: $settingsOpen)
                .tabItem { Label("Home", systemImage: "house") }
            HistoryView(settingsOpen: $settingsOpen)
                .tabItem { Label("History", systemImage: "calendar") }
            ProgressPage(settingsOpen: $settingsOpen)
                .tabItem { Label("Progress", systemImage: "chart.bar") }
            RankPage(settingsOpen: $settingsOpen)
                .tabItem { Label("Rank", systemImage: "medal") }
        }
        .tint(Palette.accent)
        .sheet(isPresented: $settingsOpen) { SettingsView() }
        .fullScreenCover(isPresented: $model.workoutOpen) { WorkoutView() }
        .sheet(item: $model.summary) { FinishView(summary: $0) }
        .alert("Track", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.message ?? "")
        }
    }
}
