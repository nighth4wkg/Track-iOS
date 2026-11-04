import SwiftUI
import TrackCore
import UIKit

/// The app after the first screen, as the PWA's routes: the four tabs (each built once and kept, shown one at a time),
/// pages opened over them (a split, a lift, a past workout, Settings), the workout, the recap after one, then the nav
/// pill, sheets, the question and the toast on top. Every change shows at once.
struct Shell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    /// The keyboard is up: the nav pill steps aside rather than riding up on it, and the toast goes to the top.
    @State private var keyboard = false
    /// The bar floating at the bottom of the covering screen (rest timer, docked button): the pill sits above it.
    @State private var bar: CGFloat = 0

    var body: some View {
        let covered = !model.pages.isEmpty || model.workoutOpen || model.finished != nil
        // What a sheet or the question covers is out of VoiceOver's reach, as it is out of the finger's. Folded into each
        // page's own flag: an outer accessibilityHidden(false) un-hid the hidden tabs (the UI tour tapped invisible ones).
        let behind = !model.sheets.isEmpty || model.confirm != nil
        ZStack {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let shown = !covered && model.tab == tab
                if AB.sharedTabs {
                    TabData(shown: shown, live: model.training) { page(tab) }
                        .environment(\.shown, shown)
                        .opacity(shown ? 1 : 0)
                        .allowsHitTesting(shown)
                        .accessibilityHidden(!shown || behind)
                } else {
                    Stage(shown: shown, again: model.swapping ? .none : .left) {
                        TabData(shown: shown, live: model.training) { page(tab) }
                            .environment(\.shown, shown)
                            .environment(model)
                            .tint(Palette.accent)
                            .contentTransition(.identity)
                            .transaction { $0.disablesAnimations = true }
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown || behind)
                }
            }
            ForEach(Array(model.pages.enumerated()), id: \.offset) { index, route in
                let shown = index == model.pages.count - 1 && !model.workoutOpen && model.finished == nil
                Covering(shown: shown) { deeper(route).swipeBack(shown) { model.back() } }
                    .id(route)
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown || behind)
                    .transition(.identity)
            }
            // Screens come and go at once, even in a tap's move (starting or finishing a workout): each moves in itself (Stage).
            // Kept made while it's kept for later: Continue workout only shows it (made anew it cost ~30 ms: build 107).
            if model.training.active != nil { Covering(shown: model.workoutOpen, anew: true) { WorkoutScreen() }.transition(.identity) }
            if let finished = model.finished, !model.workoutOpen { CompleteScreen(finished: finished).transition(.identity) }
            StatusFade()
            if !covered && !keyboard {
                NavPill().frame(maxHeight: .infinity, alignment: .bottom).floatingBottom().transition(.identity)
            }
            SheetLayer()
            AskLayer()
            ToastLayer(above: covered ? (bar > 0 ? bar + Space.s3 : 0) : Size.nav + Space.s3, keyboard: keyboard)
        }
        .onPreferenceChange(FloatingBar.self) { bar = $0 }
        .background(Backdrop())
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboard = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboard = false }
        .onChange(of: phase) { _, now in
            guard now == .active else { return }
            model.refreshDay()
            if model.training.active != nil, (model.training.restUntil ?? 0) <= nowMillis() { RestLive.idle() }
        }
        // As a rest runs out the Live Activity says Ready: its stale date alone left "Rest 0:00" up.
        .task(id: model.training.restUntil) { await RestLive.readyWhenOver(model.training.restUntil) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in model.refreshDay() }
        // A new day draws the pages again: their dates and "today" are worked out as they draw.
        .id(model.day)
        // Words and numbers change in place, as the PWA's do, even inside a tap's move (Motion.tap).
        .contentTransition(.identity)
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
        if AB.emptyPages { DeepPage { EmptyView() } } else { screen(route) }
    }

    @ViewBuilder private func screen(_ route: Route) -> some View {
        switch route {
        case .split(let id): SplitScreen(splitId: id)
        case .lift(let name): LiftScreen(name: name)
        case .session(let id): SessionScreen(sessionId: id)
        case .settings: SettingsScreen()
        }
    }
}

extension EnvironmentValues {
    /// This tab or page is the one on screen (all four tabs stay built, and pages under the top one stay too).
    @Entry var shown = true
    /// The training a tab draws (TabData).
    @Entry var tabTraining = Training()
}

/// A tab's training: the live one while it's on screen, the one it last showed while hidden, so a change made
/// elsewhere (a set typed, a split made) doesn't redraw tabs nobody sees. Shown again, it draws the live one.
private struct TabData<Content: View>: View {
    let shown: Bool
    let live: Training
    @ViewBuilder let content: Content
    /// Not observed: keeping the copy mustn't draw anything.
    @State private var kept = Kept()
    private final class Kept { var training: Training? }

    var body: some View {
        if shown || kept.training == nil { kept.training = live }
        return content.environment(\.tabTraining, kept.training ?? live)
    }
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
                .padding(.bottom, Size.nav + floatingGap + Space.s4 * 2 - homeIndicator)
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

extension View {
    /// A screen's content as it shows (the PWA's shift): from Space.s6 to the right and faded as it opens (`forward`:
    /// a page, the workout), from the left as it's come back to. A tab swapped to just shows; so does all of it with
    /// Reduce Motion. A page's docked button fades in with it but doesn't shift (`shifts` false): alone at full
    /// strength over a page still fading in, it popped in. The nav pill is the app's, not the page's, and stays put.
    @ViewBuilder func arrives(forward: Bool, shifts: Bool = true, on: Bool = true) -> some View {
        if on { modifier(Arrive(forward: forward, shifts: shifts)) } else { self }
    }
}

private struct Arrive: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.shown) private var shown
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var x: CGFloat
    @State private var opacity: Double
    let shifts: Bool

    init(forward: Bool, shifts: Bool) {
        self.shifts = shifts
        _x = State(initialValue: forward ? Space.s6 : 0)
        _opacity = State(initialValue: forward ? 0 : 1)
    }

    func body(content: Content) -> some View {
        let moving = !still && !AB.stillPages
        content
            .compositingGroup(when: AB.groupArrive)
            .geometryGroup(when: AB.geometryArrive)
            .offset(x: moving && shifts && !AB.fadeOnly ? x : 0)
            .opacity(moving && !AB.shiftOnly ? opacity : 1)
            .onAppear { settle() }
            .onChange(of: shown) { _, now in
                if !now {
                    // Out of sight: ready to come back from the left.
                    x = -Space.s6
                    opacity = 0
                } else if model.swapping {
                    x = 0
                    opacity = 1
                } else {
                    settle()
                }
            }
    }

    private func settle() {
        guard x != 0 || opacity != 1 else { return }
        if AB.lateArrive { NextFrame.run { withAnimation(Motion.move) { x = 0; opacity = 1 } } } else { withAnimation(Motion.move) { x = 0; opacity = 1 } }
    }
}

/// The floating nav pill: four tabs, the chosen one raised behind its own icon and word.
struct NavPill: View {
    @Environment(AppModel.self) private var model
    private static let tabs: [(tab: AppTab, label: String, icon: Icon)] =
        [(.home, "Home", .home), (.history, "History", .history), (.progress, "Progress", .progress), (.rank, "Rank", .rank)]
    private static var items: [(value: AppTab, text: String, icon: (Bool) -> AnyView)] {
        tabs.map { item in (value: item.tab, text: item.label, icon: { (on: Bool) -> AnyView in AnyView(item.icon.image(IconSize.logo, bold: on)) }) }
    }

    var body: some View {
        PillTabs(label: "Tabs", items: Self.items, chosen: model.tab) { model.go($0) }
            .padding(.horizontal, Space.s4)
            .sensoryFeedback(.selection, trigger: model.tab)
    }
}

/// Under the clock and battery: the page colour, fading out just below, so content scrolling up passes under it as on
/// iOS's own pages rather than running into the status bar's text.
private struct StatusFade: View {
    var body: some View {
        let height = statusBarHeight + Space.s4
        LinearGradient(stops: [.init(color: Palette.background, location: statusBarHeight / max(1, height)),
                               .init(color: Palette.background.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: Back by a swipe right

extension View {
    /// A swipe right from anywhere goes back (the PWA's swipe back), at once when let go far or fast enough. Not while
    /// a row is armed (its swipe right disarms it) or a grip is held.
    func swipeBack(_ on: Bool, back: @escaping () -> Void) -> some View {
        gesture(BackPan(on: on, onEnd: { x, velocity in if x > BackPan.distance || velocity > BackPan.flick { back() } }))
    }
}

struct BackPan: UIGestureRecognizerRepresentable {
    static let distance: CGFloat = 64, flick: CGFloat = 600
    /// An arrange grip held (ArrangeList): its drag is the finger's, whichever way it goes.
    @MainActor static var holding = false
    let on: Bool
    let onEnd: (_ x: CGFloat, _ velocity: CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.isEnabled = on
        return pan
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context: Context) { pan.isEnabled = on }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        guard pan.state == .ended else { return }
        onEnd(pan.translation(in: pan.view).x, pan.velocity(in: pan.view).x)
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Only a move right, more sideways than up or down: anything else is the page's scroll.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer, !BackPan.holding else { return false }
            let velocity = pan.velocity(in: pan.view)
            return velocity.x > abs(velocity.y)
        }

        /// An armed row's swipe right (it disarms) comes first.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            other.delegate is SidewaysPan.Coordinator
        }

        /// Alongside the page's scroll, which never waits for it (owner: lowest touch latency); a swipe right that
        /// scrolls a little as it goes back is the cost.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }
    }
}
