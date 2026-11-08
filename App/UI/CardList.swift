import SwiftUI
import UIKit

/// The workout's page as a UIKit list (-ab-swiftui-list measures the SwiftUI page it replaced): each row is its own piece, so opening a card
/// updates that card alone (in one ScrollView a card open redid the whole page's SwiftUI graph, ~45 ms on the iPhone
/// 13), and iOS animates the heights itself, on the curve the app's moves use. A card is drawn by UIKit
/// (-ab-uikit-card, CardView): updating a SwiftUI card took 15-25 ms itself.
@MainActor protocol CardListShowing { func show(_ rows: [CardList.Row], animated: Bool) }

struct CardList: UIViewControllerRepresentable {
    struct Row {
        let id: String
        /// What the row draws: a row whose value hasn't changed isn't updated.
        let value: any Equatable
        let view: AnyView
        /// A card drawn by UIKit instead of `view`.
        var card: ExerciseCard? = nil
        /// The page's header: it moves with the page and stays over it (the PWA's .pinned).
        var pinned = false
    }

    let rows: [Row]
    let model: AppModel
    /// How tall what floats over the page's bottom is, above the home indicator (the rest timer): the page runs under
    /// it to the screen's edge, and its last row scrolls clear of it.
    var dock: CGFloat = 0
    /// Out of sight (the cards being arranged): left as it is, and shown as it's become at once, not moved there.
    var frozen = false
    /// No jump key now (typing, arranging, a done card handing over to the next).
    var quiet = false
    /// The jump key tapped while another card is open: the current one opens, and the page goes to it.
    var onJump: () -> Void = {}

    func makeUIViewController(context: Context) -> UIViewController {
        AB.ownList && AB.uikitCard ? Placed(model: model) : Controller(model: model)
    }

    func makeCoordinator() -> Frozen { Frozen() }
    final class Frozen { var was = false }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        let thawed = context.coordinator.was
        context.coordinator.was = frozen
        (controller as? Placed)?.onJump = onJump
        (controller as? Placed)?.quiet = quiet || frozen
        guard !frozen else { return }
        (controller as? CardListShowing)?.show(rows, animated: context.transaction.animation != nil && !Motion.still && !thawed)
        (controller as? Placed)?.dock = dock
    }

    private static func same(_ a: any Equatable, _ b: any Equatable) -> Bool {
        func check<T: Equatable>(_ a: T) -> Bool { (b as? T) == a }
        return check(a)
    }

    /// The page going to a row, or a set in an open card (`top`: to the page's top, else just enough), as
    /// ScrollViewReader's scrollTo does in the SwiftUI page.
    static let revealed = Notification.Name("CardList.revealed")
    static func reveal(_ id: String, top: Bool) { NotificationCenter.default.post(name: revealed, object: (id, top)) }

    private static func ms(_ seconds: CFTimeInterval) -> Int { Int((seconds * 1000).rounded()) }

    /// -ab-own-list: the page as one scroll view that places every row itself, so a card that opens updates itself
    /// and the rows move to where it says, in one animation (the collection view's own re-measuring took ~11 ms of a
    /// card open). A card is made as it comes into sight, the rest one an idle turn after (making all 24 took ~45 ms
    /// of Continue workout), and kept; until then a sizer gives its height. The heading and Add exercise are SwiftUI
    /// pieces measured when they change.
    final class Placed: UIViewController, CardListShowing, UIScrollViewDelegate {
        private let model: AppModel
        private let scroll = Scroll()
        private var order: [String] = []
        private var rows: [String: Row] = [:]
        private var cards: [String: CardView] = [:]
        private var hosts: [String: UIHostingController<AnyView>] = [:]
        private var heights: [String: CGFloat] = [:]
        private var tops: [String: CGFloat] = [:]
        private var width: CGFloat = 0
        /// Measures the cards not made yet.
        private lazy var sizer = CardView()
        /// Where to go once the page is laid out (the card it's in may just have opened, the keyboard come up).
        private var going: (id: String, top: Bool)?
        var dock: CGFloat = 0 { didSet { if dock != oldValue { view.setNeedsLayout() } } }

        // The header (the PWA's .pinned): on a strip of the page's colour that also covers the status bar, over the
        // rows. A scroll down takes it away by as much as the page moved, a scroll up brings it back; left part way when
        // the page stops it settles the way the page last went. Near the top it stays in its place on the page.
        // It's in the scroll view, so a glide of the page carries it in the same animation (no frame behind).
        private let pin = UIView()
        private var pinnedId: String?
        /// Where it shows: 0 in full under the status bar, -span away above the screen.
        private var offset: CGFloat = 0
        private var lastY: CGFloat = 0, turn: CGFloat = 0, wentUp = false
        private var settling = false, settleTicket = 0
        /// When the page's own glide (go) ends: the header settles and the jump key shows only after it.
        private var glideUntil: CFTimeInterval = 0

        // The jump key (the PWA's .jump): shown only while the current set is off the screen, pointing to it.
        private let jump = RoundControl(.up, surface: .float)
        /// Fades and swells the key: the key's own alpha is its press look, set back as a finger lifts (it undid the
        /// fade out: owner, the key shrank on a tap and stayed).
        private let jumpHolder = UIView(frame: CGRect(x: 0, y: 0, width: Size.control, height: Size.control))
        /// nil hidden, else whether it points down.
        private var pointing: Bool?
        var quiet = false {
            didSet {
                guard quiet != oldValue else { return }
                if quiet { aim(showing: false) } else { DispatchQueue.main.async { [weak self] in self?.aim(showing: true) } }
            }
        }
        var onJump: () -> Void = {}

        init(model: AppModel) {
            self.model = model
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidLoad() {
            super.viewDidLoad()
            scroll.backgroundColor = .clear
            scroll.alwaysBounceVertical = true
            scroll.keyboardDismissMode = .interactive
            scroll.delegate = self
            scroll.frame = view.bounds
            scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(scroll)
            // First of the rows (read first by VoiceOver), drawn over them.
            pin.backgroundColor = .background
            pin.layer.zPosition = 1
            scroll.addSubview(pin)
            jumpHolder.alpha = 0
            jumpHolder.transform = CGAffineTransform(scaleX: Pop.from, y: Pop.from)
            jumpHolder.addSubview(jump)
            jump.isUserInteractionEnabled = false
            jump.isAccessibilityElement = false
            jump.accessibilityLabel = "Go to the current set"
            jump.accessibilityTraits = .button
            jump.addTarget(self, action: #selector(jumped), for: .touchUpInside)
            view.addSubview(jumpHolder)
            NotificationCenter.default.addObserver(self, selector: #selector(revealed), name: CardList.revealed, object: nil)
        }

        @objc private func revealed(_ note: Notification) {
            guard let to = note.object as? (String, Bool) else { return }
            going = to
            view.setNeedsLayout()
        }

        private func go(_ id: String, top: Bool) {
            // A page still coasting from a fling stops where it is: the jump key isn't on the page, so its tap didn't
            // stop it, and the coast carried on under the glide (owner: it stopped short of the set, then drifted).
            if scroll.isDecelerating { scroll.setContentOffset(scroll.contentOffset, animated: false) }
            let rect: CGRect
            if let y = tops[id] {
                rect = CGRect(x: 0, y: y, width: width, height: heights[id] ?? 0)
            } else if case let (card, frame)? = order.lazy.compactMap({ self.cards[$0] }).compactMap({ card in card.frame(ofSet: id).map { (card, $0) } }).first {
                rect = scroll.convert(frame, from: card)
            } else {
                return
            }
            let inset = scroll.adjustedContentInset
            let shown = scroll.bounds.height - inset.top - inset.bottom
            let lowest = -inset.top, highest = max(lowest, scroll.contentSize.height + inset.bottom - scroll.bounds.height)
            var y = scroll.contentOffset.y
            // What of the header shows now covers the page's top; going up brings it back in full, so a part goes
            // under it (the PWA's reveal settling a part below the pinned header).
            let cover = pinnedId == nil ? 0 : max(0, pin.frame.maxY - (y + inset.top))
            if top || rect.height > shown || rect.minY < y + inset.top + cover {
                y = rect.minY - inset.top
                if y < scroll.contentOffset.y { y -= pinnedId.flatMap { heights[$0] } ?? 0 }
            } else if rect.maxY > y + inset.top + shown {
                y = rect.maxY - inset.top - shown
            }
            y = min(max(y, lowest), highest)
            guard y != scroll.contentOffset.y else { return }
            if Motion.still { scroll.contentOffset.y = y; return }
            glideUntil = .infinity // the move's own scroll (below) is the page's glide
            let length = Moves.travel(over: y - scroll.contentOffset.y) { self.scroll.contentOffset.y = y }
            glideUntil = CACurrentMediaTime() + length
            settleSoon()
            DispatchQueue.main.asyncAfter(deadline: .now() + length) { [weak self] in self?.aim(showing: true) }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            // The dock over the home indicator, less what of the screen's edge the page's own safe area already keeps clear.
            let bottom = max(0, dock + (view.window?.safeAreaInsets.bottom ?? 0) - scroll.safeAreaInsets.bottom)
            if scroll.contentInset.bottom != bottom { scroll.contentInset.bottom = bottom; scroll.verticalScrollIndicatorInsets.bottom = bottom }
            if scroll.bounds.width != width {
                width = scroll.bounds.width
                for id in order { measure(id) }
                UIView.performWithoutAnimation { place() }
            }
            let before = cards.count
            UIView.performWithoutAnimation { makeInSight() }
            if cards.count != before {
                Sampler.note("cardlist in sight \(scroll.bounds.debugDescription) of \(Int(scroll.contentSize.height)): \(cards.count) made")
            }
            if !settling { UIView.performWithoutAnimation { placePin() } }
            placeJump()
            if let going { self.going = nil; go(going.id, top: going.top) }
            // A change under it (the rest timer coming, the page's size) only hides the key: it shows from a scroll.
            aim(showing: false)
        }

        func show(_ next: [Row], animated: Bool) {
            loadViewIfNeeded()
            let start = CACurrentMediaTime()
            let changed = Set(next.filter { row in rows[row.id].map { !CardList.same($0.value, row.value) } ?? true }.map(\.id))
            let ids = next.map(\.id)
            guard ids != order || !changed.isEmpty else { return }
            let gone = order.filter { !ids.contains($0) }
            let fresh = Set(ids.filter { !order.contains($0) })
            rows = Dictionary(next.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            order = ids
            let wasTop = tops, wasHeight = heights
            // New rows start where they go, closed up and clear, and open out with the rest. Cards not made yet are
            // measured now, out of sight (as they'd be in the move): with the made ones' heights ahead, the move's length.
            let ahead = changed.filter { cards[$0] == nil && !fresh.contains($0) }
            UIView.performWithoutAnimation {
                for id in fresh { make(id) }
                place(only: fresh, shut: true)
                for id in ahead { measure(id) }
                for id in changed where cards[id]?.needsSets == true && rows[id]?.card?.open == true { cards[id]?.buildSets() }
            }
            let animate = animated && view.window != nil && !AB.stillList
            let change = { [self] in
                for id in changed where !fresh.contains(id) { refresh(id) }
                for id in changed where !ahead.contains(id) { measure(id) }
                for id in gone { leave(id) }
                place()
            }
            var length = 0.0, distance: CGFloat = 0
            if animate {
                distance = farthest(from: wasTop, wasHeight, to: changed.subtracting(ahead).reduce(into: heights) { $0[$1] = predicted($1) }, gone: gone)
                length = Moves.travel(over: distance, change)
            } else {
                UIView.performWithoutAnimation(change)
            }
            Sampler.note("cardlist placed \(changed.count) changed (\(cards.count) made): \(CardList.ms(CACurrentMediaTime() - start)) ms, \(Int(distance)) pt in \(CardList.ms(length)) ms")
            prebuildSoon(after: length)
            // The key shows once the rows have moved and any glide the change asks for (posted after it) has begun.
            DispatchQueue.main.asyncAfter(deadline: .now() + length) { [weak self] in self?.aim(showing: true) }
        }

        private func make(_ id: String) {
            guard let row = rows[id] else { return }
            if row.card == nil {
                let host = UIHostingController(rootView: AnyView(content(row.view)))
                host.view.backgroundColor = .clear
                host.safeAreaRegions = []
                addChild(host)
                if row.pinned { pinnedId = id }
                (row.pinned ? pin : scroll).addSubview(host.view)
                host.didMove(toParent: self)
                hosts[id] = host
            }
            measure(id)
        }

        /// A card's views, where it was (`top`) or is, so it moves in with the rest.
        @discardableResult private func build(_ id: String, at top: CGFloat? = nil) -> CardView? {
            if let built = cards[id] { return built }
            guard let card = rows[id]?.card else { return nil }
            let view = CardView()
            view.onResize = { [weak self] in self?.resized(id) }
            UIView.performWithoutAnimation {
                view.update(card, model: model)
                if let top = top ?? tops[id] { view.frame = CGRect(x: x, y: top + Space.s1, width: inner, height: (heights[id] ?? 0) - Space.s3) }
            }
            cards[id] = view
            scroll.addSubview(view)
            return view
        }

        private func refresh(_ id: String) {
            guard let row = rows[id] else { return }
            if let card = row.card { cards[id]?.update(card, model: model) } else { hosts[id]?.rootView = AnyView(content(row.view)) }
        }

        /// What Shell gives each screen (its own SwiftUI piece doesn't inherit it).
        private func content(_ view: some View) -> some View {
            view
                .environment(model)
                .tint(Palette.accent)
                .contentTransition(.identity)
                .transaction { $0.disablesAnimations = true }
        }

        /// How far the move goes: the most any row's top or bottom moves (a row coming or going: its height).
        private func farthest(from wasTop: [String: CGFloat], _ wasHeight: [String: CGFloat], to height: [String: CGFloat], gone: [String]) -> CGFloat {
            var y: CGFloat = 0, most: CGFloat = 0
            for id in order {
                let now = height[id] ?? 0
                if let top = wasTop[id], let was = wasHeight[id] { most = max(most, abs(y - top), abs(y + now - top - was)) } else { most = max(most, now) }
                y += now
            }
            return gone.reduce(most) { max($0, wasHeight[$1] ?? 0) }
        }

        /// A made card's row height once it shows its new row, worked out before it does; any other row's as it is.
        private func predicted(_ id: String) -> CGFloat {
            guard let card = rows[id]?.card, let made = cards[id] else { return heights[id] ?? 0 }
            return rowHeight(made.height(for: inner, as: card))
        }

        private func rowHeight(_ card: CGFloat) -> CGFloat { Space.s1 + card.pixelUp(view.scale) + Space.s3 - Space.s1 }

        /// A row's height at the page's width (a card's with its share of the gaps, as CardCell's).
        private func measure(_ id: String) {
            guard width > 0 else { return }
            if let card = rows[id]?.card {
                // An open card is always made (it has what it opens to measure).
                let shown: CardView
                if let made = cards[id] ?? (card.open ? build(id) : nil) {
                    shown = made
                } else {
                    UIView.performWithoutAnimation { sizer.update(card, model: model) }
                    shown = sizer
                }
                heights[id] = rowHeight(shown.height(for: inner))
            } else if let host = hosts[id] {
                heights[id] = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
            }
        }

        private var inner: CGFloat { min(width, Size.column) - Space.s4 * 2 }
        private var x: CGFloat { (width - min(width, Size.column)) / 2 + Space.s4 }

        /// Every row where it goes (`only` these, `shut`: closed up at the top of their place).
        private func place(only: Set<String>? = nil, shut: Bool = false) {
            let was = tops
            var y: CGFloat = 0
            for id in order { tops[id] = y; y += heights[id] ?? 0 }
            if only == nil { scroll.contentSize = CGSize(width: width, height: y) }
            // Cards coming into sight are made where they were, so they move in with the rest.
            for id in order where cards[id] == nil && only?.contains(id) ?? true && inSight(id) { build(id, at: was[id]) }
            for id in order where only?.contains(id) ?? true {
                let height = heights[id] ?? 0, top = tops[id] ?? 0
                if let card = cards[id] {
                    card.frame = CGRect(x: x, y: top + Space.s1, width: inner, height: shut ? 0 : height - Space.s3)
                    card.alpha = shut ? 0 : 1
                } else if let host = hosts[id] {
                    // The header sits in its strip, under the part covering the status bar.
                    host.view.frame = CGRect(x: 0, y: id == pinnedId ? scroll.adjustedContentInset.top : top, width: width, height: shut ? 0 : height)
                    host.view.alpha = shut ? 0 : 1
                }
            }
            if !settling { placePin() }
        }

        /// The page's scroll from its top (0) to its end: a bounce past either doesn't move the header.
        private func pageY() -> CGFloat {
            let inset = scroll.adjustedContentInset
            let end = max(0, scroll.contentSize.height + inset.top + inset.bottom - scroll.bounds.height)
            return min(max(scroll.contentOffset.y + inset.top, 0), end)
        }

        /// How far the header goes to be away: itself and the status bar it covers.
        private var span: CGFloat { scroll.adjustedContentInset.top + (pinnedId.flatMap { heights[$0] } ?? 0) }

        /// The header where `offset` puts it, never below its own place on the page (at the top, or pulled down).
        private func placePin() {
            guard let id = pinnedId else { return }
            let inset = scroll.adjustedContentInset.top, height = heights[id] ?? 0
            let y = max(0, scroll.contentOffset.y + inset + offset)
            pin.frame = CGRect(x: 0, y: y - inset, width: width, height: inset + height)
            hosts[id]?.view.frame.origin.y = inset
        }

        /// The page moved (a finger, its own glide, a change in its size): the header goes with it, as the PWA's.
        private func follow() {
            guard pinnedId != nil else { return }
            let y = pageY()
            halt()
            // The way it goes turns only past a slop: a glide's last point of jitter read as a turn (the PWA's).
            if wentUp ? y < turn : y > turn { turn = y } else if abs(y - turn) >= Space.s2 { wentUp = y < turn; turn = y }
            offset = min(0, max(offset - (y - lastY), -span))
            lastY = y
            placePin()
            if !scroll.isTracking { settleSoon() }
        }

        /// Settles once the page has been still a moment with no finger on it (a drag held still doesn't snap it).
        private func settleSoon() {
            settleTicket += 1
            let ticket = settleTicket, now = CACurrentMediaTime()
            let wait = max(Motion.fast, (glideUntil.isFinite ? glideUntil : now) - now)
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self, ticket == self.settleTicket, !self.scroll.isTracking else { return }
                self.settle()
            }
        }

        /// Left part way, it slides the way the page last went: shown after a scroll up, away after one down.
        private func settle() {
            let away = -min(pageY(), span)
            guard pinnedId != nil, offset < 0, offset > away else { return aim(showing: true) }
            offset = wentUp ? 0 : -span
            guard !Motion.still else { placePin(); return aim(showing: true) }
            settling = true
            Moves.spring({ self.placePin() }) { [weak self] _ in
                guard let self, self.settling else { return }
                self.settling = false
                self.aim(showing: true)
            }
        }

        /// A scroll mid-settle carries on from where the header is.
        private func halt() {
            guard settling else { return }
            settling = false
            let shown = pin.layer.presentation()?.frame.minY ?? pin.frame.minY
            pin.layer.removeAllAnimations()
            offset = min(0, max(shown + scroll.adjustedContentInset.top - (scroll.contentOffset.y + scroll.adjustedContentInset.top), -span))
            placePin()
        }

        /// The key over the rest timer's place, its right edge a little inside the timer's (the PWA's .jump).
        private func placeJump() {
            guard let window = view.window else { return }
            let screen = window.bounds, pill = min(Size.navWidth, screen.width - Space.s4 * 2)
            let center = CGPoint(x: (screen.width + pill) / 2 - Space.s2 - Size.control / 2,
                                 y: screen.height - floatingGap - Size.nav - Space.s6 - Size.control / 2)
            jumpHolder.center = view.convert(center, from: window)
        }

        /// The current card's next set (or the card, while it's closed), on the page.
        private func currentPart() -> (id: String, card: CGRect, part: CGRect)? {
            guard let id = order.first(where: { rows[$0]?.card?.current == true }), let card = rows[id]?.card, let top = tops[id] else { return nil }
            let whole = CGRect(x: 0, y: top, width: width, height: heights[id] ?? 0)
            guard card.open, let set = card.exercise.sets.first(where: { !$0.done }), let made = cards[id],
                  let frame = made.frame(ofSet: set.id) else { return (id, whole, whole) }
            return (id, whole, scroll.convert(frame, from: made))
        }

        /// Shows the key while the current set is off the screen (above the header, below the rest timer), pointing
        /// to it; `showing` false only hides it. Not during the page's own glide: it would flash on the way.
        private func aim(showing: Bool) {
            var off: Bool?
            if !quiet, let part = currentPart()?.part {
                let top = max(scroll.contentOffset.y + scroll.adjustedContentInset.top, pinnedId == nil ? -CGFloat.infinity : pin.frame.maxY)
                let bottom = scroll.contentOffset.y + scroll.bounds.height - scroll.adjustedContentInset.bottom
                if part.maxY <= top { off = false } else if part.minY >= bottom { off = true }
            }
            guard let off else { return point(nil) }
            guard showing, going == nil, CACurrentMediaTime() >= glideUntil, !settling else { return }
            point(off)
        }

        private func point(_ down: Bool?) {
            guard down != pointing else { return }
            let was = pointing
            pointing = down
            jump.isUserInteractionEnabled = down != nil
            jump.isAccessibilityElement = down != nil
            if let down {
                let turn = { self.jump.icon.transform = down ? CGAffineTransform(rotationAngle: .pi) : .identity }
                if was == nil || Motion.still { UIView.performWithoutAnimation(turn) } else { Moves.spring(turn) }
            }
            guard (was == nil) != (down == nil) else { return }
            let on = down != nil
            let look = { self.jumpHolder.alpha = on ? 1 : 0 }, size = { self.jumpHolder.transform = on ? .identity : CGAffineTransform(scaleX: Pop.from, y: Pop.from) }
            if Motion.still { look(); size(); return }
            // The fade on its own even curve, quick; the swell on the app's move (the PWA's .jump transition).
            UIView.animate(withDuration: Motion.fast, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction], animations: look)
            Moves.spring(size)
        }

        /// To the whole card, its name in view under the header, unless that leaves the set off the screen (a long
        /// card): then to the set. Another card open: the current one opens in its place, and the page goes to it.
        @objc private func jumped() {
            guard let now = currentPart() else { return }
            guard rows[now.id]?.card?.open == true else { return onJump() }
            let inset = scroll.adjustedContentInset
            let room = scroll.bounds.height - inset.top - inset.bottom - (pinnedId.flatMap { heights[$0] } ?? 0)
            if now.part.maxY - now.card.minY <= room {
                go(now.id, top: true)
            } else if let set = rows[now.id]?.card?.exercise.sets.first(where: { !$0.done }) {
                go(set.id, top: false)
            }
        }

        private func inSight(_ id: String) -> Bool {
            // Only once on screen at a real size: SwiftUI sizes the page in passes first, and a provisional size had
            // every card in sight (a representable's controller isn't told it's appearing).
            guard let window = view.window, scroll.bounds.height > 0, scroll.bounds.height <= window.bounds.height,
                  rows[id]?.card != nil, let top = tops[id] else { return false }
            return CGRect(x: 0, y: top, width: width, height: heights[id] ?? 0).intersects(scroll.bounds)
        }

        private func makeInSight() { for id in order where cards[id] == nil && inSight(id) { build(id) } }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            makeInSight()
            follow()
            aim(showing: true)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            settleTicket += 1
            halt()
        }

        /// A removed row closes up and clears as what's under it comes up, then goes.
        private func leave(_ id: String) {
            let card = cards.removeValue(forKey: id)
            let view: UIView? = card ?? hosts[id]?.view
            card?.flush()
            heights[id] = nil
            tops[id] = nil
            guard let view else { return }
            let host = hosts.removeValue(forKey: id)
            var frame = view.frame
            frame.size.height = 0
            view.frame = frame
            view.alpha = 0
            let done = {
                view.removeFromSuperview()
                host?.willMove(toParent: nil)
                host?.removeFromParent()
            }
            if UIView.inheritedAnimationDuration > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + UIView.inheritedAnimationDuration) { done() } // the move it's in
            } else {
                done()
            }
        }

        /// A card's height changed by itself (typing showed an error or a new best).
        private func resized(_ id: String) {
            let was = heights[id] ?? 0
            measure(id)
            Moves.travel(over: (heights[id] ?? 0) - was) { self.place() }
        }

        /// Once a move has settled, one thing an idle turn while the page isn't scrolling: the cards not made yet,
        /// nearest first, then (-ab-prebuilt-sets) what the cards near sight open.
        private func prebuildSoon(after length: Double = Motion.normal) {
            settled = max(settled, CACurrentMediaTime() + length)
            guard !preparing else { return }
            preparing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + length) { [weak self] in self?.prebuild() }
        }

        /// When the last move settles, and whether idle work is under way (one chain, however many moves).
        private var settled: CFTimeInterval = 0
        private var preparing = false

        private func prebuild() {
            let wait = settled - CACurrentMediaTime()
            guard wait <= 0, !scroll.isTracking, !scroll.isDecelerating else {
                DispatchQueue.main.asyncAfter(deadline: .now() + max(wait, Motion.normal)) { [weak self] in self?.prebuild() }
                return
            }
            let start = CACurrentMediaTime()
            let away = { [self] (id: String) in abs((tops[id] ?? 0) - scroll.bounds.midY) }
            let near = scroll.bounds.insetBy(dx: 0, dy: -scroll.bounds.height)
            if let id = order.filter({ rows[$0]?.card != nil && cards[$0] == nil }).min(by: { away($0) < away($1) }) {
                build(id)
                Sampler.note("cardlist made a card ahead: \(CardList.ms(CACurrentMediaTime() - start)) ms")
            } else if AB.prebuiltSets, let card = order.lazy.compactMap({ self.cards[$0] }).first(where: { $0.needsSets && $0.frame.intersects(near) }) {
                card.buildSets()
                Sampler.note("cardlist prebuilt a card's sets: \(CardList.ms(CACurrentMediaTime() - start)) ms")
            } else {
                preparing = false
                return
            }
            DispatchQueue.main.async { [weak self] in self?.prebuild() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            prebuildSoon()
            aim(showing: true)
        }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { prebuildSoon(); settleSoon() }
        }

        /// A touch goes to the row shown under the finger: mid-move a row's frame is already where it's going.
        private final class Scroll: UIScrollView {
            /// Kept for later, the page comes back at its top, as it did made anew.
            override func didMoveToWindow() {
                super.didMoveToWindow()
                if window == nil { contentOffset.y = -adjustedContentInset.top }
            }

            override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
                guard isUserInteractionEnabled, !isHidden, alpha > 0, self.point(inside: point, with: event) else { return nil }
                // What's drawn over the rows (the header) first.
                let front = subviews.reversed().filter { $0.layer.zPosition > 0 }, rest = subviews.reversed().filter { $0.layer.zPosition <= 0 }
                for row in front + rest {
                    if let hit = row.hitTest(row.onScreen(convert(point, to: row)), with: event) { return hit }
                }
                return self
            }
        }
    }

    final class Controller: UIViewController, CardListShowing {
        private let model: AppModel
        private var rows: [String: Row] = [:]
        private var order: [String] = []
        private let list = UICollectionView(frame: .zero, collectionViewLayout: Controller.layout())
        private var source: UICollectionViewDiffableDataSource<Int, String>?

        init(model: AppModel) {
            self.model = model
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidLoad() {
            super.viewDidLoad()
            list.backgroundColor = .clear
            list.keyboardDismissMode = .interactive
            list.frame = view.bounds
            list.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(list)
            let cell = UICollectionView.CellRegistration<UICollectionViewCell, String> { [unowned self] cell, _, id in
                // A growing card is uncovered from its top as its cell grows (the PWA's resize).
                cell.clipsToBounds = true
                guard let row = self.rows[id] else { return }
                cell.contentConfiguration = UIHostingConfiguration { self.content(row.view) }.margins(.all, 0)
            }
            let card = UICollectionView.CellRegistration<CardCell, String> { [unowned self] cell, _, id in
                guard let card = self.rows[id]?.card else { return }
                cell.card.update(card, model: self.model)
            }
            source = UICollectionViewDiffableDataSource(collectionView: list) { [unowned self] list, index, id in
                self.rows[id]?.card != nil ? list.dequeueConfiguredReusableCell(using: card, for: index, item: id)
                    : list.dequeueConfiguredReusableCell(using: cell, for: index, item: id)
            }
        }

        /// What Shell gives each screen (its own SwiftUI piece doesn't inherit it).
        private func content(_ view: some View) -> some View {
            view
                .environment(model)
                .tint(Palette.accent)
                .contentTransition(.identity)
                .transaction { $0.disablesAnimations = true }
        }

        func show(_ next: [Row], animated: Bool) {
            loadViewIfNeeded()
            guard let source else { return }
            let changed = next.filter { row in rows[row.id].map { !CardList.same($0.value, row.value) } ?? false }.map(\.id)
            let ids = next.map(\.id)
            rows = Dictionary(next.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            guard ids != order || !changed.isEmpty else { return }
            let animate = animated && view.window != nil && !AB.stillList
            defer { if AB.prebuiltSets { prebuildSoon() } }
            if AB.directCards, ids == order, changed.allSatisfy({ rows[$0]?.card != nil }) {
                resize(changed, animate: animate)
                return
            }
            order = ids
            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])
            snapshot.appendItems(ids)
            snapshot.reconfigureItems(changed)
            let start = CACurrentMediaTime()
            if animate {
                Moves.spring { source.apply(snapshot, animatingDifferences: true) }
            } else {
                UIView.performWithoutAnimation { source.apply(snapshot, animatingDifferences: false) }
            }
            let applied = CACurrentMediaTime()
            list.layoutIfNeeded()
            Sampler.note("cardlist \(changed.count) changed: apply \(CardList.ms(applied - start)) ms, layout \(CardList.ms(CACurrentMediaTime() - applied)) ms")
        }

        /// -ab-direct-cards: cards in view update their own views and resize in the list's animation; cards out of
        /// view are configured anew (without moving anything) for when they come in.
        private func resize(_ changed: [String], animate: Bool) {
            guard let source else { return }
            let start = CACurrentMediaTime()
            var hidden: [String] = []
            let change = { [self] in
                for id in changed {
                    guard let card = rows[id]?.card, let index = source.indexPath(for: id),
                          let cell = list.cellForItem(at: index) as? CardCell else { hidden.append(id); continue }
                    cell.card.update(card, model: model)
                    cell.invalidateIntrinsicContentSize()
                }
                list.layoutIfNeeded()
            }
            if animate { Moves.travel(change) } else { UIView.performWithoutAnimation(change) }
            if !hidden.isEmpty {
                var snapshot = source.snapshot()
                snapshot.reconfigureItems(hidden)
                UIView.performWithoutAnimation { source.apply(snapshot, animatingDifferences: false) }
            }
            Sampler.note("cardlist \(changed.count) changed in place (\(hidden.count) out of view): \(CardList.ms(CACurrentMediaTime() - start)) ms")
        }

        /// -ab-prebuilt-sets: once a move has settled, the cards in view build what they open, one a run-loop turn,
        /// while the list isn't scrolling.
        private func prebuildSoon() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Motion.travel) { [weak self] in self?.prebuild() }
        }

        private func prebuild() {
            guard !list.isTracking, !list.isDecelerating else { prebuildSoon(); return }
            guard let cell = list.visibleCells.lazy.compactMap({ $0 as? CardCell }).first(where: { $0.card.needsSets }) else { return }
            let start = CACurrentMediaTime()
            cell.card.buildSets()
            Sampler.note("cardlist prebuilt a card's sets: \(CardList.ms(CACurrentMediaTime() - start)) ms")
            DispatchQueue.main.async { [weak self] in self?.prebuild() }
        }

        private static func layout() -> UICollectionViewLayout {
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(Size.row))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
            return UICollectionViewCompositionalLayout(section: NSCollectionLayoutSection(group: group))
        }
    }
}

/// A card's row: the card in the page's column, with its share of the gaps (Space.s1 above, the rest of Space.s3
/// below), as Workout's `column` places a SwiftUI row.
final class CardCell: UICollectionViewCell {
    let card = CardView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // A growing card is uncovered from its top as its cell grows (the PWA's resize).
        clipsToBounds = true
        contentView.addSubview(card)
        card.onResize = { [weak self] in self?.invalidateIntrinsicContentSize() }
    }

    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        card.flush()
    }

    private func place(_ width: CGFloat) -> CGRect {
        let column = min(width, Size.column), inner = column - Space.s4 * 2
        return CGRect(x: (width - column) / 2 + Space.s4, y: Space.s1, width: inner, height: card.height(for: inner).pixelUp(scale))
    }

    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let fitted = attributes.copy() as! UICollectionViewLayoutAttributes
        fitted.size.height = place(attributes.size.width).height + Space.s3
        return fitted
    }

    // In the list's animation, so the card grows with its row.
    override func apply(_ attributes: UICollectionViewLayoutAttributes) {
        super.apply(attributes)
        card.frame = place(attributes.size.width)
    }
}
