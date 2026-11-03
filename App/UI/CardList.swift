import SwiftUI
import UIKit

/// The workout's page as a UIKit list (-ab-uikit-list, being measured): each row is its own piece, so opening a card
/// updates that card alone (in one ScrollView a card open redid the whole page's SwiftUI graph, ~45 ms on the iPhone
/// 13), and iOS animates the heights itself, on the curve the app's moves use. A card is drawn by UIKit
/// (-ab-uikit-card, CardView): updating a SwiftUI card took 15-25 ms itself.
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

    func makeUIViewController(context: Context) -> Controller { Controller(model: model) }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.show(rows, animated: context.transaction.animation != nil && !Motion.still)
    }

    final class Controller: UIViewController {
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
            let changed = next.filter { row in rows[row.id].map { !Self.same($0.value, row.value) } ?? false }.map(\.id)
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
                UIView.animate(springDuration: Motion.normal, bounce: 0) { source.apply(snapshot, animatingDifferences: true) }
            } else {
                UIView.performWithoutAnimation { source.apply(snapshot, animatingDifferences: false) }
            }
            let applied = CACurrentMediaTime()
            list.layoutIfNeeded()
            Sampler.note("cardlist \(changed.count) changed: apply \(Self.ms(applied - start)) ms, layout \(Self.ms(CACurrentMediaTime() - applied)) ms")
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
            if animate { UIView.animate(springDuration: Motion.normal, bounce: 0, animations: change) } else { UIView.performWithoutAnimation(change) }
            if !hidden.isEmpty {
                var snapshot = source.snapshot()
                snapshot.reconfigureItems(hidden)
                UIView.performWithoutAnimation { source.apply(snapshot, animatingDifferences: false) }
            }
            Sampler.note("cardlist \(changed.count) changed in place (\(hidden.count) out of view): \(Self.ms(CACurrentMediaTime() - start)) ms")
        }

        /// -ab-prebuilt-sets: once a move has settled, the cards in view build what they open, one a run-loop turn,
        /// while the list isn't scrolling.
        private func prebuildSoon() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Motion.normal) { [weak self] in self?.prebuild() }
        }

        private func prebuild() {
            guard !list.isTracking, !list.isDecelerating else { prebuildSoon(); return }
            guard let cell = list.visibleCells.lazy.compactMap({ $0 as? CardCell }).first(where: { $0.card.needsSets }) else { return }
            let start = CACurrentMediaTime()
            cell.card.buildSets()
            Sampler.note("cardlist prebuilt a card's sets: \(Self.ms(CACurrentMediaTime() - start)) ms")
            DispatchQueue.main.async { [weak self] in self?.prebuild() }
        }

        private static func ms(_ seconds: CFTimeInterval) -> Int { Int((seconds * 1000).rounded()) }

        private static func same(_ a: any Equatable, _ b: any Equatable) -> Bool {
            func check<T: Equatable>(_ a: T) -> Bool { (b as? T) == a }
            return check(a)
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
