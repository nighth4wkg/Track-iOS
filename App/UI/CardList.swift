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
    }

    let rows: [Row]
    let model: AppModel
    /// How tall what floats over the page's bottom is, above the home indicator (the rest timer): the page runs under
    /// it to the screen's edge, and its last row scrolls clear of it.
    var dock: CGFloat = 0

    func makeUIViewController(context: Context) -> UIViewController {
        AB.ownList && AB.uikitCard ? Placed(model: model) : Controller(model: model)
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        (controller as? CardListShowing)?.show(rows, animated: context.transaction.animation != nil && !Motion.still)
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
            NotificationCenter.default.addObserver(self, selector: #selector(revealed), name: CardList.revealed, object: nil)
        }

        @objc private func revealed(_ note: Notification) {
            guard let to = note.object as? (String, Bool) else { return }
            going = to
            view.setNeedsLayout()
        }

        private func go(_ id: String, top: Bool) {
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
            if top || rect.height > shown || rect.minY < y + inset.top {
                y = rect.minY - inset.top
            } else if rect.maxY > y + inset.top + shown {
                y = rect.maxY - inset.top - shown
            }
            y = min(max(y, lowest), highest)
            guard y != scroll.contentOffset.y else { return }
            if Motion.still { scroll.contentOffset.y = y } else { Moves.travel { self.scroll.contentOffset.y = y } } // in step with the cards
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
            if let going { self.going = nil; go(going.id, top: going.top) }
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
            // New rows start where they go, closed up and clear, and open out with the rest.
            UIView.performWithoutAnimation {
                for id in fresh { make(id) }
                place(only: fresh, shut: true)
            }
            let animate = animated && view.window != nil && !AB.stillList
            let change = { [self] in
                for id in changed where !fresh.contains(id) { refresh(id) }
                for id in changed { measure(id) }
                for id in gone { leave(id) }
                place()
            }
            if animate { Moves.travel(change) } else { UIView.performWithoutAnimation(change) }
            Sampler.note("cardlist placed \(changed.count) changed (\(cards.count) made): \(CardList.ms(CACurrentMediaTime() - start)) ms")
            prebuildSoon()
        }

        private func make(_ id: String) {
            guard let row = rows[id] else { return }
            if row.card == nil {
                let host = UIHostingController(rootView: AnyView(content(row.view)))
                host.view.backgroundColor = .clear
                host.safeAreaRegions = []
                addChild(host)
                scroll.addSubview(host.view)
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
                heights[id] = Space.s1 + shown.height(for: inner).pixelUp(view.scale) + Space.s3 - Space.s1
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
                    host.view.frame = CGRect(x: 0, y: top, width: width, height: shut ? 0 : height)
                    host.view.alpha = shut ? 0 : 1
                }
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

        func scrollViewDidScroll(_ scrollView: UIScrollView) { makeInSight() }

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
                DispatchQueue.main.asyncAfter(deadline: .now() + Motion.travel) { done() }
            } else {
                done()
            }
        }

        /// A card's height changed by itself (typing showed an error or a new best).
        private func resized(_ id: String) {
            measure(id)
            Moves.spring { self.place() }
        }

        /// Once a move has settled, one thing an idle turn while the page isn't scrolling: the cards not made yet,
        /// nearest first, then (-ab-prebuilt-sets) what the cards near sight open.
        private func prebuildSoon() {
            settled = CACurrentMediaTime() + Motion.travel
            guard !preparing else { return }
            preparing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Motion.travel) { [weak self] in self?.prebuild() }
        }

        /// When the last move settles, and whether idle work is under way (one chain, however many moves).
        private var settled: CFTimeInterval = 0
        private var preparing = false

        private func prebuild() {
            let wait = settled - CACurrentMediaTime()
            guard wait <= 0, !scroll.isTracking, !scroll.isDecelerating else {
                DispatchQueue.main.asyncAfter(deadline: .now() + max(wait, Motion.travel)) { [weak self] in self?.prebuild() }
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

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { prebuildSoon() }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { prebuildSoon() }
        }

        /// A touch goes to the row shown under the finger: mid-move a row's frame is already where it's going.
        private final class Scroll: UIScrollView {
            override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
                guard isUserInteractionEnabled, !isHidden, alpha > 0, self.point(inside: point, with: event) else { return nil }
                for row in subviews.reversed() {
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
