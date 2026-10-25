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
    /// The keyboard is up: the nav pill steps aside rather than riding up on it.
    @State private var keyboard = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        @Bindable var model = model
        let covered = model.pushed.contains(model.tab)
        let navHidden = covered || keyboard
        ZStack {
            // iOS's own tabs with their bar hidden (the pill is the bar): each keeps its state, but only the one on
            // screen is in the window, so the others aren't laid out again as the keyboard or safe area changes.
            tabs
            .overlay(alignment: .bottom) {
                pill
                    .opacity(navHidden ? 0 : 1).allowsHitTesting(!navHidden)
                    .animation(.smooth(duration: Motion.fast), value: navHidden)
                    .ignoresSafeArea(.keyboard)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboard = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboard = false }
            .onChange(of: model.tab) { _, tab in built.insert(tab) }
            // A new day redraws the pages from scratch: their dates and "today" are worked out as they draw.
            .id(model.day)
            .onChange(of: phase) { _, now in
                guard now == .active else { return }
                model.refreshDay()
                if model.training.active != nil, (model.training.restUntil ?? 0) <= nowMillis() { RestLive.idle() }
            }
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
        .task(id: model.training.restUntil) { await RestLive.readyWhenOver(model.training.restUntil) }
        .sensoryFeedback(.selection, trigger: model.tab)
        .sheet(isPresented: $settingsOpen) { SettingsView().trackOverlays() }
        .fullScreenCover(item: $model.finished) { CompletionView(finished: $0).trackOverlays() }
        .sheet(item: $model.history) { HistoryDetail(session: $0).trackOverlays() }
        .trackOverlays(nav: !navHidden && !model.workoutOpen)
    }

    // shortcut: -noTabView / -pillHost are HitProbe's test switches for the pill dead at launch; remove with it.
    @ViewBuilder private var tabs: some View {
        @Bindable var model = model
        if HitProbe.on("-noTabView") {
            ZStack {
                ForEach(AppTab.allCases.filter(built.contains), id: \.self) { tab in
                    page(tab).opacity(tab == model.tab ? 1 : 0).allowsHitTesting(tab == model.tab)
                }
            }
        } else {
            TabView(selection: $model.tab) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Group { if built.contains(tab) { page(tab) } else { Backdrop() } }
                        .toolbarVisibility(.hidden, for: .tabBar)
                        .tag(tab)
                }
            }
        }
    }

    @ViewBuilder private var pill: some View {
        if HitProbe.on("-pillHost") {
            HostedPill(model: model).padding(.bottom, Space.s4 - homeIndicator)
        } else {
            NavPill()
        }
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

/// The nav pill in its own hosting view, so its touches are its own and not routed through the tabs' host.
private struct HostedPill: UIViewControllerRepresentable {
    let model: AppModel

    func makeUIViewController(context: Context) -> UIHostingController<AnyView> {
        let host = UIHostingController(rootView: AnyView(NavPill(floats: false).environment(model)))
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        return host
    }

    func updateUIViewController(_ host: UIHostingController<AnyView>, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController host: UIHostingController<AnyView>, context: Context) -> CGSize? {
        host.sizeThatFits(in: CGSize(width: proposal.width ?? .infinity, height: .infinity))
    }
}
