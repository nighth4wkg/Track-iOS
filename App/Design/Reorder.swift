import SwiftUI
import UniformTypeIdentifiers
import TrackCore

/// Moving a workout's exercises: hold a card's name and drag it. While it's held the workout is shown as just its
/// exercises' names (ReorderList), so the list is short and each place is the same height; the one under the finger
/// makes room; holding near the top (the bar included) or the bottom scrolls there. Letting go anywhere on the page
/// ends it.
final class ReorderBox {
    /// Each name's frame on screen in the list being dragged over. Not observed: it changes on every scroll.
    var frames: [String: CGRect] = [:]
    /// Each card's frame on the workout page, and the page's scrolling area: where a held name starts out.
    var cards: [String: CGRect] = [:]
    var viewport = CGRect.zero
    var pickedY: CGFloat?
    /// The screen's bottom edge.
    var height: CGFloat = 0
    var edge: String?
    /// Scrolls the page to "top" or "bottom".
    var scroll: ((String) -> Void)?
}

extension View {
    /// What you pick up: this view, shown as `preview` while it's dragged.
    func reorderHandle<Preview: View>(_ id: String, box: ReorderBox, dragging: Binding<String?>, @ViewBuilder preview: () -> Preview) -> some View {
        onDrag({
            box.pickedY = box.cards[id]?.minY
            withAnimation(.smooth(duration: 0.2)) { dragging.wrappedValue = id }
            return NSItemProvider(object: id as NSString)
        }, preview: preview)
    }
}

/// The workout while an exercise is held: each exercise as just its name on a glass card, over the real cards (which
/// fade out untouched, so nothing heavy folds or re-lays out), the held one dimmed where it would land. It opens
/// with the held name where its card was, so nothing jumps under the finger.
struct ReorderList: View {
    let exercises: [Exercise]
    let held: String
    let box: ReorderBox
    private static let row: CGFloat = 76

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    Color.clear.frame(height: 0).id("top")
                    ForEach(exercises) { exercise in
                        let done = exercise.sets.filter(\.done).count
                        HStack(spacing: 8) {
                            Text(exercise.name).font(.title3.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Chip(text: "\(done)/\(exercise.sets.count)", accent: done > 0 && done == exercise.sets.count)
                            Image(systemName: "line.3.horizontal").font(.subheadline.weight(.bold)).foregroundStyle(Palette.muted)
                        }
                        .frame(height: Self.row - 32).padding(16)
                        .glass(lifted: false)
                        .opacity(exercise.id == held ? 0.4 : 1)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { box.frames[exercise.id] = $0 }
                        .id(exercise.id)
                    }
                    Color.clear.frame(height: 0).id("bottom")
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
                .animation(.smooth(duration: 0.25), value: exercises.map(\.id))
            }
            .onAppear {
                box.scroll = { edge in proxy.scrollTo(edge, anchor: edge == "top" ? .top : .bottom) }
                // Lines the held name up with where its card was: the same point of the name and the page meet.
                let page = box.viewport, y = box.pickedY ?? page.minY
                let anchor = page.height > Self.row ? min(1, max(0, (y - page.minY) / (page.height - Self.row))) : 0
                proxy.scrollTo(held, anchor: UnitPoint(x: 0.5, y: anchor))
            }
        }
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
