import SwiftUI
import UIKit

/// A screen (a tab, a page, the workout, a sheet) in its own hosting controller, moved by Core Animation once it's
/// built: it's put up out of sight at its starting place, built and drawn in that frame, and sent on its way only on
/// the next. The move then runs in the render server, so nothing the app does meanwhile drops its frames. SwiftUI's
/// own moves are worked out in the app frame by frame, and their first frame was the new screen's build: 20-80 ms
/// late at 120 Hz (build 101), the stutter at the start of every page, tab and sheet.
///
/// Hidden (`shown` false) it's kept built but taken out of the window, so every update of the app (a set typed, a
/// toast) skips it: hidden at opacity 0 in the app's own tree a tab cost each one ~10-20 ms (build 81). Its state stays,
/// so showing it again is as quick as before. It gets `shown` false and settles once before it leaves the window.
struct Stage<Content: View>: UIViewControllerRepresentable {
    enum Way { case none, right, left, up }
    var shown = true
    /// How it comes in when first put up: a page from the right, a sheet up from below.
    var first: Way = .none
    /// How it comes in when shown again: from the left (a tab chosen, a page come back to).
    var again: Way = .none
    /// A sheet's dim behind it, faded in and out as it comes and goes.
    var dim = false
    /// Closed (a sheet): it goes back down and its dim out, taking no touches, before it's taken away.
    var leaving = false
    /// A sheet's height: it comes up from just below the screen's edge, its own height away, not the screen's.
    var height: () -> CGFloat? = { nil }
    /// Hidden, it stays in the window, only hidden (a tab, AB.keepTabs): taken out and put back, a tab's first frame
    /// was 15-42 ms of SwiftUI re-attaching the whole page (build 121-122), though nothing in it had changed.
    var keep: () -> Bool = { false }
    @ViewBuilder let content: Content

    func makeUIViewController(context: Context) -> Holder {
        let holder = Holder(UIHostingController(rootView: content), dim: dim)
        holder.height = height
        holder.keep = keep
        holder.show(shown, coming: first)
        // Built once in the window as the app starts, so the first time it's shown isn't the build.
        if !shown { DispatchQueue.main.async { holder.prebuild() } }
        return holder
    }

    func updateUIViewController(_ holder: Holder, context: Context) {
        // Hidden, it isn't given each new version: it gets the latest when it's shown again.
        guard shown || holder.shown else { return }
        let start = CACurrentMediaTime(), was = holder.shown
        // Going away it keeps what it showed: drawn again as it went, the picker searched its whole library (build 117).
        if !leaving { holder.host.rootView = content }
        holder.height = height
        let given = CACurrentMediaTime()
        holder.show(shown, coming: again)
        if leaving { holder.leave() }
        if shown != was {
            Sampler.note("stage \(shown ? "shown" : "hidden"): content \(Int((given - start) * 1000)) ms, show \(Int((CACurrentMediaTime() - given) * 1000)) ms")
        }
    }

    final class Holder: UIViewController {
        let host: UIHostingController<Content>
        var height: () -> CGFloat? = { nil }
        var keep: () -> Bool = { false }
        private(set) var shown = false
        private let dim: UIView?
        /// Each move's number: a move waiting for its next frame doesn't start if another has come since.
        private var moves = 0
        private var gone = false

        init(_ host: UIHostingController<Content>, dim: Bool) {
            self.host = host
            self.dim = dim ? UIView() : nil
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            host.view.backgroundColor = .clear
            addChild(host)
            host.didMove(toParent: self)
            if let dim {
                dim.backgroundColor = UIColor(Palette.scrim)
                dim.frame = view.bounds
                dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.addSubview(dim) // under the host, which is added as it's shown
            }
        }

        func prebuild() {
            guard !shown, host.view.superview == nil, view.window != nil else { return }
            show(true, coming: .none)
            host.view.layoutIfNeeded()
            show(false, coming: .none)
        }

        func show(_ on: Bool, coming way: Way) {
            loadViewIfNeeded()
            if on, host.view.superview == nil {
                host.view.frame = view.bounds
                host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.addSubview(host.view)
            } else if !on, host.view.superview != nil, keep() {
                host.view.isHidden = true
            } else if !on, host.view.superview != nil {
                host.view.layoutIfNeeded() // `shown` false reaches it while it's still in the window
                host.view.removeFromSuperview()
            }
            if on { host.view.isHidden = false }
            if on, !shown { arrive(way) }
            // An empty holder over the shown screen mustn't take its touches.
            view.isUserInteractionEnabled = on
            shown = on
        }

        /// Out of sight where it starts this frame (the frame it's built in), on its way from the next.
        private func arrive(_ way: Way) {
            moves += 1
            let move = moves, moving = host.view!
            guard way != .none, !Motion.still else {
                UIView.performWithoutAnimation { moving.transform = .identity; moving.alpha = 1; dim?.alpha = 1 }
                return
            }
            // Before it's laid out its height isn't known: the window's takes it off the screen. (Its place in the window
            // came out moved by this very shift, so a sheet started above its place and dropped in: build 102.)
            let below = { [unowned self] in CGAffineTransform(translationX: 0, y: self.height() ?? self.view.bounds.height) }
            UIView.performWithoutAnimation {
                switch way {
                case .right: moving.transform = CGAffineTransform(translationX: Space.s6, y: 0); moving.alpha = 0
                case .left: moving.transform = CGAffineTransform(translationX: -Space.s6, y: 0); moving.alpha = 0
                case .up: moving.transform = CGAffineTransform(translationX: 0, y: keyWindow?.bounds.height ?? view.bounds.height)
                case .none: break
                }
                dim?.alpha = 0
            }
            NextFrame.run { [weak self] in
                guard let self, moves == move, shown, !gone else { return }
                if way == .up { UIView.performWithoutAnimation { moving.transform = below() } }
                Moves.travel { moving.transform = .identity; moving.alpha = 1; self.dim?.alpha = 1 }
            }
        }

        /// A closed sheet: down past the screen's edge from wherever it is, its dim out, from the next frame. Started
        /// in the close's own frame (the app redrawn around it: 30-50 ms at 120 Hz), the picker's went down with a hitch
        /// (build 102 recordings).
        func leave() {
            guard !gone else { return }
            gone = true
            moves += 1
            view.isUserInteractionEnabled = false
            let moving = host.view!
            NextFrame.run { [weak self] in
                guard let self else { return }
                Moves.travel { moving.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height); self.dim?.alpha = 0 }
            }
        }
    }
}

/// A page or the workout over the tabs: from the right as it opens, from the left as it's come back to (not when
/// swapped to), its floating bar (a docked button, the rest timer) passed up to the app for the toast's place.
struct Covering<Content: View>: View {
    @Environment(AppModel.self) private var model
    var shown = true
    /// Shown again, it opens anew from the right (the workout continued), not comes back from the left.
    var anew = false
    @ViewBuilder let content: Content
    @State private var bar: CGFloat = 0

    var body: some View {
        Stage(shown: shown, first: .right, again: anew ? .right : model.swapping ? .none : .left) {
            Calm(model: model, live: shown) { content.environment(\.shown, shown) }
                .onPreferenceChange(FloatingBar.self) { bar = $0 }
        }
        .ignoresSafeArea()
        .floatingBar(shown ? bar : 0)
    }
}

/// The app's way inside a screen of its own, as Shell's: words and numbers change in place, and a change shows at once
/// unless it says how it moves. It reads what Shell reads, so each change passes through it on the way down, as it
/// did through Shell; without that, a change drawn only below it (the rest's ±15s) took a part's own animation (the
/// rest timer rose in again: build 102).
struct Calm<Content: View>: View {
    /// Given, not from the environment: this is the top of its screen, where the environment starts empty.
    let model: AppModel
    /// Hidden (a page under another, the workout kept for later) it reads nothing, so no change elsewhere (a sheet,
    /// a toast, a set) redraws it: shown again, it's given the latest (Stage). The hidden workout redrew in other
    /// screens' first frames (build 122).
    var live = true
    @ViewBuilder let content: Content

    var body: some View {
        if live {
            _ = (model.training, model.tab, model.pages, model.sheets.count, model.confirm?.id, model.toast?.id, model.workoutOpen, model.finished?.id, model.bench)
        }
        return content
            .environment(model)
            .tint(Palette.accent)
            .contentTransition(.identity)
            .transaction { $0.disablesAnimations = true }
    }
}

extension View {
    /// This as a screen of its own (Calm).
    func calm(_ model: AppModel) -> some View { Calm(model: model) { self } }
}
