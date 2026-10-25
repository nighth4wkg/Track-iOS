import SwiftUI
import TrackCore
import UIKit

/// The app after the first screen, as the PWA's routes: the four tabs (each built once and kept, shown one at a time),
/// pages opened over them (a split, a lift, a past workout, Settings), the workout, the recap after one, then the nav
/// pill, sheets, the question and the toast on top. Every change shows at once.
struct Shell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    /// The keyboard is up: the nav pill steps aside rather than riding up on it.
    @State private var keyboard = false

    var body: some View {
        let covered = !model.pages.isEmpty || model.workoutOpen || model.finished != nil
        ZStack {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let shown = !covered && model.tab == tab
                page(tab)
                    .environment(\.shown, shown)
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown)
            }
            ForEach(Array(model.pages.enumerated()), id: \.offset) { index, route in
                let shown = index == model.pages.count - 1 && !model.workoutOpen && model.finished == nil
                deeper(route)
                    .id(route)
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown)
                    .edgeBack(shown) { model.back() }
            }
            if model.workoutOpen, model.training.active != nil { WorkoutScreen() }
            if let finished = model.finished, !model.workoutOpen { CompleteScreen(finished: finished) }
            StatusFade()
            if !covered && !keyboard {
                NavPill().frame(maxHeight: .infinity, alignment: .bottom).floatingBottom()
            }
            SheetLayer()
            AskLayer()
            ToastLayer(above: covered ? 0 : Size.nav + Space.s3)
        }
        .background(Backdrop())
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboard = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboard = false }
        .onChange(of: phase) { _, now in
            guard now == .active else { return }
            model.refreshDay()
            if model.training.active != nil, (model.training.restUntil ?? 0) <= nowMillis() { RestLive.idle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in model.refreshDay() }
        // A new day draws the pages again: their dates and "today" are worked out as they draw.
        .id(model.day)
        .transaction { $0.disablesAnimations = true }
    }

    @ViewBuilder private func page(_ tab: AppTab) -> some View {
        switch tab {
        case .home: HomeScreen()
        case .history: HistoryScreen()
        case .progress: ProgressScreen()
        case .rank: RankScreen()
        }
    }

    @ViewBuilder private func deeper(_ route: Route) -> some View {
        switch route {
        case .split(let id): SplitScreen(splitId: id)
        case .lift(let name): LiftScreen(name: name)
        case .session(let id): SessionScreen(sessionId: id)
        case .settings: SettingsScreen()
        }
    }
}

extension EnvironmentValues {
    /// This tab is the one on screen (all four stay built).
    @Entry var shown = true
}

/// A tab's page (the PWA's .page): one scrolling column, 16 from the edges, its last card two page edges clear of
/// the nav pill. Shown again, it starts from the top, as the PWA's go() does.
struct TabPage<Content: View>: View {
    @Environment(\.shown) private var shown
    @ViewBuilder let content: Content
    @State private var position = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s4)
                .padding(.bottom, Size.nav + Space.s4 * 3 - homeIndicator)
                .frame(maxWidth: Size.column)
                .frame(maxWidth: .infinity)
        }
        .scrollPosition($position)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: shown) { if shown { position.scrollTo(edge: .top) } }
        .background(Backdrop())
    }
}

/// A page opened over a tab (the PWA's .page.bare): no nav pill, the content 24 clear of the bottom.
struct DeepPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s6)
                .frame(maxWidth: Size.column)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Backdrop())
    }
}

/// The floating nav pill: four tabs, the chosen one raised behind its own icon and word.
struct NavPill: View {
    @Environment(AppModel.self) private var model
    private static let tabs: [(tab: AppTab, label: String, icon: Icon)] =
        [(.home, "Home", .home), (.history, "History", .history), (.progress, "Progress", .progress), (.rank, "Rank", .rank)]

    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(Self.tabs, id: \.tab) { item in
                let on = model.tab == item.tab
                Button { model.go(item.tab) } label: {
                    VStack(spacing: 2) {
                        item.icon.image(IconSize.logo, bold: on)
                        Text(item.label).type(.t12)
                    }
                    .foregroundStyle(on ? Palette.accent : Palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { if on { Color.clear.raised(.control, .pill) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(Space.s1)
        .frame(maxWidth: Size.navWidth)
        .frame(height: Size.nav)
        .raised(.nav, .pill)
        .padding(.horizontal, Space.s4)
        .sensoryFeedback(.selection, trigger: model.tab)
    }
}

/// Under the clock and battery: the page colour, fading out just below, so content scrolling up passes under it as on
/// iOS's own pages rather than running into the status bar's text.
private struct StatusFade: View {
    var body: some View {
        let height = statusBar + Space.s4
        LinearGradient(stops: [.init(color: Palette.background, location: statusBar / max(1, height)),
                               .init(color: Palette.background.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: Back by the left edge

extension View {
    /// A swipe in from the left edge goes back, as iOS's own pages do, at once when let go far or fast enough.
    func edgeBack(_ on: Bool, back: @escaping () -> Void) -> some View {
        gesture(EdgePan(on: on, onEnd: { x, velocity in if x > EdgePan.distance || velocity > EdgePan.flick { back() } }))
    }
}

private struct EdgePan: UIGestureRecognizerRepresentable {
    static let distance: CGFloat = 64, flick: CGFloat = 600
    let on: Bool
    let onEnd: (_ x: CGFloat, _ velocity: CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIScreenEdgePanGestureRecognizer {
        let pan = UIScreenEdgePanGestureRecognizer()
        pan.edges = .left
        pan.isEnabled = on
        return pan
    }

    func updateUIGestureRecognizer(_ pan: UIScreenEdgePanGestureRecognizer, context: Context) { pan.isEnabled = on }

    func handleUIGestureRecognizerAction(_ pan: UIScreenEdgePanGestureRecognizer, context: Context) {
        guard pan.state == .ended else { return }
        onEnd(pan.translation(in: pan.view).x, pan.velocity(in: pan.view).x)
    }
}
