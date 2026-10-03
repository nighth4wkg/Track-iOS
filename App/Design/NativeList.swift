import SwiftUI

/// Rows on one glass card that use iOS's own list inside the page: the system swipe to show Delete (Track then asks
/// first), hold and drag to move when `onMove` is set, and the website's hairline 16pt in from both sides. The list
/// doesn't scroll by itself; it is exactly as tall as its rows, measured as they lay out.
struct NativeList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var deleteLabel = "Delete"
    var onDelete: ((Item) -> Void)?
    var onMove: ((Int, Int) -> Void)?
    var insets = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
    @ViewBuilder let row: (Item) -> Row
    @State private var heights: [Item.ID: CGFloat] = [:]

    var body: some View {
        List {
            ForEach(items) { item in
                row(item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[item.id] = $0 }
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
                    .listRowInsets(insets)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Palette.hairline)
                    .listRowSeparator(.hidden, edges: outerEdges(item))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if let onDelete {
                            Button { onDelete(item) } label: { Label(deleteLabel, systemImage: "trash") }.tint(Palette.danger)
                        }
                    }
            }
            .onMove(perform: onMove == nil ? nil : moved)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 0)
        .frame(height: items.reduce(0) { $0 + (heights[$1.id] ?? 52) + insets.top + insets.bottom })
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glass()
    }

    /// No hairline above the first row or below the last.
    private func outerEdges(_ item: Item) -> VerticalEdge.Set {
        var edges: VerticalEdge.Set = []
        if item.id == items.first?.id { edges.insert(.top) }
        if item.id == items.last?.id { edges.insert(.bottom) }
        return edges
    }

    /// SwiftUI's offset means "before this index"; Track's means the item's new place.
    private func moved(_ from: IndexSet, _ to: Int) {
        guard let start = from.first else { return }
        onMove?(start, to > start ? to - 1 : to)
    }
}
