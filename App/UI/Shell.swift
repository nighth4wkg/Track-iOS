import SwiftUI
import TrackCore
import UIKit

/// The app after the first screen, as the PWA's routes: the four tabs (each built once and kept, shown one at a time)
/// with the nav pill, pages pushed over them (a split, a lift, a past workout, Settings) and the workout last, on
/// iOS's own navigation (its push, and its swipe back that follows the finger); the recap after a workout, then
/// sheets, the question and the toast on top. Everything else shows at once.
struct Shell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    /// The keyboard is up: the nav pill steps aside rather than riding up on it, and the toast goes to the top.
    @State private var keyboard = false
    /// Each pushed screen's floating bar (rest timer, docked button): the toast sits above the top one's. Gathered per
    /// screen: a pushed screen's preferences don't reach past the navigation.
    @State private var bars: [Stop: CGFloat] = [:]

    @State private var path: [Stop] = []

    var body: some View {
        if AB.navProbe { AnyView(NavProbe()) } else if AB.navBare { AnyView(bare) } else { AnyView(main) }
    }

    private var bare: some View {
        @Bindable var model = model
        return NavigationStack(path: $model.stops) {
            Button("Bare push") { model.open(.settings) }
                .navigationDestination(for: Stop.self) { _ in Text("Bare page") }
        }
    }

    @ViewBuilder private var main: some View {
        @Bindable var model = model
        let stops = model.stops
        let covered = !stops.isEmpty || model.finished != nil
        let behind = Self.behind(model)
        let bar = stops.last.flatMap { bars[$0] } ?? 0
        ZStack {
            NavigationStack(path: AB.navState ? $path : $model.stops) {
                ZStack {
                    if AB.navNoTabs { Button("Bare push") { model.open(.settings) } } else {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        // Under a page the tab stays drawn (the swipe back uncovers it), just not the one shown.
                        let current = model.tab == tab, shown = current && !covered
                        TabData(shown: shown, live: model.training) { page(tab) }
                            .environment(\.shown, shown)
                            .opacity(current ? 1 : 0)
                            .allowsHitTesting(current)
                            .accessibilityHidden(!shown || behind)
                    }
                    if !keyboard {
                        NavPill().frame(maxHeight: .infinity, alignment: .bottom).floatingBottom()
                    }
                    }
                }
                .background(Backdrop())
                .toolbar(AB.navPlain ? .visible : .hidden, for: .navigationBar)
                .transaction { if !AB.navPlain { $0.disablesAnimations = true } }
                .navigationDestination(for: Stop.self) { stop in
                    if AB.navDest { Text("Bare page") } else {
                    Pushed(stop: stop) {
                        switch stop {
                        case .page(let route): deeper(route)
                        case .workout: WorkoutScreen()
                        }
                    }
                    .background(Backdrop())
                    .onPreferenceChange(FloatingBar.self) { bars[stop] = $0 }
                    .toolbar(AB.navPlain ? .visible : .hidden, for: .navigationBar)
                    .transaction { if !AB.navPlain { $0.disablesAnimations = true } }
                    }
                }
            }
            // Only the push and the swipe back move (under a no-animation the stack's push doesn't); the rest shows at once.
            if !AB.navSolo {
            Group {
                if let finished = model.finished, !model.workoutOpen { CompleteScreen(finished: finished) }
                StatusFade()
                SheetLayer()
                AskLayer()
                ToastLayer(above: covered ? (bar > 0 ? bar + Space.s3 : 0) : Size.nav + Space.s3, keyboard: keyboard)
            }
            .transaction { if !AB.navPlain { $0.disablesAnimations = true } }
            }
        }
        .background(Backdrop())
        .onChange(of: model.stops) { if AB.navState, path != $1 { path = $1 } }
        .onChange(of: path) { if AB.navState, model.stops != $1 { model.stops = $1 } }
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
        .id(AB.navNoId ? "" : model.day)
    }

    /// What a sheet or the question covers is out of VoiceOver's reach, as it is out of the finger's. Folded into each
    /// page's own flag: an outer accessibilityHidden(false) un-hid the hidden tabs (the UI tour tapped invisible ones).
    static func behind(_ model: AppModel) -> Bool { !model.sheets.isEmpty || model.confirm != nil }

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

// DIAG (remove)
private struct NavProbe: View {
    @State private var path: [Int] = []
    var body: some View {
        NavigationStack(path: $path) {
            Button("Probe push") { path.append(path.count + 1) }
                .navigationDestination(for: Int.self) { Text("Probe page \($0)") }
        }
    }
}

/// A pushed screen, on top or not. It reads the model itself: the stack keeps the screen its closure built, with the
/// path as it was then (read there, the workout never counted as on top and was hidden from VoiceOver).
private struct Pushed<Content: View>: View {
    @Environment(AppModel.self) private var model
    let stop: Stop
    @ViewBuilder let content: Content

    var body: some View {
        let shown = stop == model.stops.last && model.finished == nil
        content
            .environment(\.shown, shown)
            .accessibilityHidden(!shown || Shell.behind(model))
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
/// the nav pill. Swapped to again, it starts from the top, as the PWA's go() does; come back to from a page, it's
/// where it was (the swipe back shows it there).
struct TabPage<Content: View>: View {
    @Environment(AppModel.self) private var model
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
        .onChange(of: shown) { if shown && model.swapping { position.scrollTo(edge: .top) } }
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
                    VStack(spacing: Gap.tab) {
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
