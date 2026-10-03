import SwiftUI
import UniformTypeIdentifiers

/// Moving a workout's exercises: hold a card's name and drag it. While it's held every card folds to its name, so
/// the list is short and each place is the same height; the one under the finger makes room; holding near the top
/// (the bar included) or the bottom scrolls there. Letting go anywhere on the page ends it.
final class ReorderBox {
    /// Each card's frame in the page ("cards" space), as laid out now. Not observed: it changes on every scroll.
    var frames: [String: CGRect] = [:]
    var height: CGFloat = 0
    var edge: String?
}

extension View {
    /// What you pick up: this view, shown as `preview` while it's dragged.
    func reorderHandle<Preview: View>(_ id: String, dragging: Binding<String?>, @ViewBuilder preview: () -> Preview) -> some View {
        onDrag({ dragging.wrappedValue = id; return NSItemProvider(object: id as NSString) }, preview: preview)
    }
}

struct ReorderDrop: DropDelegate {
    let ids: [String]
    let box: ReorderBox
    @Binding var dragging: String?
    /// Scrolls to "top" or "bottom".
    let scroll: (String) -> Void
    let move: (Int, Int) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let y = info.location.y
        let edge = y < 130 ? "top" : y > box.height - 110 ? "bottom" : nil
        if edge != box.edge {
            box.edge = edge
            if let edge { scroll(edge) }
        }
        // Past the middle of the card under the finger, so a short card and a tall one don't swap back and forth.
        if let dragging, let from = ids.firstIndex(of: dragging),
           let to = ids.firstIndex(where: { box.frames[$0].map { $0.minY <= y && y < $0.maxY } ?? false }), to != from,
           let target = box.frames[ids[to]], to > from ? y > target.midY : y < target.midY {
            withAnimation(.smooth(duration: 0.25)) { move(from, to) }
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { box.edge = nil }

    func performDrop(info: DropInfo) -> Bool {
        box.edge = nil
        withAnimation(.smooth(duration: 0.3)) { dragging = nil }
        return true
    }
}
