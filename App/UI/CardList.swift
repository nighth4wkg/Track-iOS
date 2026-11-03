import SwiftUI
import UIKit

/// The workout's page as a UIKit list (-ab-uikit-list, being measured): each row is its own SwiftUI piece, so opening a
/// card updates that card alone (in one ScrollView a card open redid the whole page's SwiftUI graph, ~45 ms on the
/// iPhone 13), and iOS animates the heights itself, on the curve the app's moves use.
struct CardList: UIViewControllerRepresentable {
    struct Row {
        let id: String
        /// What the row draws: a row whose value hasn't changed isn't updated.
        let value: any Equatable
        let view: AnyView
    }

    let rows: [Row]
    let model: AppModel

    func makeUIViewController(context: Context) -> Controller { Controller(model: model) }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.show(rows, animated: context.transaction.animation != nil && !Motion.still)
    }

    /// A row's view, read by its cell's SwiftUI piece (-ab-slot-cells): a change goes into the piece already there,
    /// instead of iOS setting the cell up again (two cards re-set took 35-57 ms of a card open on the iPhone 13).
    @Observable final class Slot {
        var view: AnyView
        init(_ view: AnyView) { self.view = view }
    }

    private struct Slotted: View {
        let slot: Slot
        var body: some View { slot.view }
    }

    final class Controller: UIViewController {
        private let model: AppModel
        private var rows: [String: Row] = [:]
        private var slots: [String: Slot] = [:]
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
                if AB.slotCells {
                    let slot = self.slots[id] ?? Slot(row.view)
                    self.slots[id] = slot
                    cell.contentConfiguration = UIHostingConfiguration { self.content(Slotted(slot: slot)) }.margins(.all, 0)
                } else {
                    cell.contentConfiguration = UIHostingConfiguration { self.content(row.view) }.margins(.all, 0)
                }
            }
            source = UICollectionViewDiffableDataSource(collectionView: list) { list, index, id in
                list.dequeueConfiguredReusableCell(using: cell, for: index, item: id)
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
            let moved = ids != order
            order = ids
            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])
            snapshot.appendItems(ids)
            let animate = animated && view.window != nil && !AB.stillList
            let start = CACurrentMediaTime()
            let update = { [self] in
                if AB.slotCells {
                    slots = slots.filter { rows[$0.key] != nil }
                    for id in changed { slots[id]?.view = rows[id]!.view }
                    if moved { source.apply(snapshot, animatingDifferences: animate) }
                    list.layoutIfNeeded()
                } else {
                    snapshot.reconfigureItems(changed)
                    source.apply(snapshot, animatingDifferences: animate)
                }
            }
            if animate {
                UIView.animate(springDuration: Motion.normal, bounce: 0, animations: update)
            } else {
                UIView.performWithoutAnimation(update)
            }
            let applied = CACurrentMediaTime()
            list.layoutIfNeeded()
            Sampler.note("cardlist \(changed.count) changed: apply \(Self.ms(applied - start)) ms, layout \(Self.ms(CACurrentMediaTime() - applied)) ms")
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
