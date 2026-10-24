import SwiftUI
import TrackCore

/// The app after the first screen: the four tabs under the PWA's floating nav pill, the workout over everything while
/// it's open, the recap when one finishes, and a finished workout's detail.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var settingsOpen = false
    @State private var screen: CGFloat = 1000
    /// The workout on screen or sliding; once it's away it's also unseen, as iOS's own top bar inside it would
    /// otherwise still be read out (VoiceOver) below the screen.
    @State private var workoutShown = false
    /// Tabs built so far: each is built on its first visit and kept, so coming back is instant and keeps its place.
    @State private var built: Set<AppTab> = [.home]
    @Environment(\.scenePhase) private var phase

    var body: some View {
        @Bindable var model = model
        ZStack {
            ZStack {
                ForEach(AppTab.allCases.filter(built.contains), id: \.self) { tab in
                    let on = tab == model.tab
                    page(tab).opacity(on ? 1 : 0).allowsHitTesting(on).accessibilityHidden(!on)
                }
            }
            .overlay(alignment: .bottom) {
                NavPill().ignoresSafeArea(.container, edges: .bottom)
                    .opacity(model.pushed > 0 ? 0 : 1).allowsHitTesting(model.pushed == 0)
                    .animation(.smooth(duration: Motion.fast), value: model.pushed > 0)
            }
            .onChange(of: model.tab) { _, tab in built.insert(tab) }
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
                .opacity(model.workoutOpen || workoutShown ? 1 : 0)
                .allowsHitTesting(model.workoutOpen)
                .accessibilityHidden(!model.workoutOpen)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.top + $0.safeAreaInsets.bottom } action: { screen = $0 }
        .task(id: model.workoutOpen) {
            if model.workoutOpen { workoutShown = true; return }
            try? await Task.sleep(for: .seconds(Motion.screen))
            if !model.workoutOpen, !Task.isCancelled { workoutShown = false }
        }
        .sensoryFeedback(.selection, trigger: model.tab)
        .sheet(isPresented: $settingsOpen) { SettingsView().trackOverlays() }
        .fullScreenCover(item: $model.finished) { CompletionView(finished: $0).trackOverlays() }
        .sheet(item: $model.history) { HistoryDetail(session: $0).trackOverlays() }
        .trackOverlays(nav: model.pushed == 0 && !model.workoutOpen)
    }

    @ViewBuilder private func page(_ tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView(settingsOpen: $settingsOpen)
        case .history: HistoryView()
        case .progress: ProgressPage()
        case .rank: RankPage()
        }
    }
}
