import SwiftUI
import TrackCore

/// The app after the first screen: the website's four tabs on the system tab bar (Liquid Glass on iOS 26), the
/// workout over everything while it's open, the recap when one finishes, and a finished workout's detail.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var settingsOpen = false
    @State private var screen: CGFloat = 1000
    @Environment(\.scenePhase) private var phase

    var body: some View {
        @Bindable var model = model
        ZStack {
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
            // A new day redraws the pages from scratch: their dates and "today" are worked out as they draw.
            .id(model.day)
            .onChange(of: phase) { _, now in if now == .active { model.refreshDay() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in model.refreshDay() }
            .tint(Palette.accent)
            .opacity(model.workoutOpen && model.workoutCovers ? 0 : 1)
            .accessibilityHidden(model.workoutOpen)
            // The workout over the tabs: slid up by the app rather than presented by iOS, which ignores every tap while
            // its pages slide, and kept built below the screen while it's left for later, so coming back is instant.
            WorkoutView()
                .offset(y: model.workoutOpen ? 0 : screen)
                .animation(.smooth(duration: Motion.screen), value: model.workoutOpen)
                .allowsHitTesting(model.workoutOpen)
                .accessibilityHidden(!model.workoutOpen)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.top + $0.safeAreaInsets.bottom } action: { screen = $0 }
        .sensoryFeedback(.selection, trigger: model.tab)
        .sheet(isPresented: $settingsOpen) { SettingsView().trackOverlays() }
        .fullScreenCover(item: $model.finished) { CompletionView(finished: $0).trackOverlays() }
        .sheet(item: $model.history) { HistoryDetail(session: $0).trackOverlays().presentationDetents([.fraction(0.75), .large]) }
        .trackOverlays()
    }
}
