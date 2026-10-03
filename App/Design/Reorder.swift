import SwiftUI
import UniformTypeIdentifiers

/// Hold an item and drag it to move it: the others make room as it passes over them. The item's id rides along as
/// text; only ids in the same list move anything.
extension View {
    /// What you pick up: this view, shown as `preview` while it's dragged.
    func reorderHandle<Preview: View>(_ id: String, dragging: Binding<String?>, @ViewBuilder preview: () -> Preview) -> some View {
        onDrag({ dragging.wrappedValue = id; return NSItemProvider(object: id as NSString) }, preview: preview)
    }

    /// Where it can go: passing over this item moves the dragged one to its place.
    func reorderTarget(_ id: String, in ids: [String], dragging: Binding<String?>, move: @escaping (Int, Int) -> Void) -> some View {
        onDrop(of: [.text], delegate: ReorderDrop(id: id, ids: ids, dragging: dragging, move: move))
    }
}

private struct ReorderDrop: DropDelegate {
    let id: String
    let ids: [String]
    @Binding var dragging: String?
    let move: (Int, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != id, let from = ids.firstIndex(of: dragging), let to = ids.firstIndex(of: id) else { return }
        withAnimation(.smooth(duration: 0.25)) { move(from, to) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
