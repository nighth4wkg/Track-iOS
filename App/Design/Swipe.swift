import SwiftUI
import UIKit

/// A pan that only begins when the finger moves more sideways than up or down (the website's 6px direction rule),
/// so a row's swipe and the page's scroll never fight: vertical drags stay the scroll's. One that `sharesTouches` (the
/// tab swipe) runs alongside the scroll, and never starts within 24pt of the screen's sides, on a native list (whose
/// rows swipe for themselves, see SwipeZones) or on a control such as the segmented tabs.
struct HorizontalPan: UIGestureRecognizerRepresentable {
    /// A release this fast (pt/s) decides a row's swipe by its direction, however far it went.
    static let flick: CGFloat = 300

    /// The tab swipe, the website's rule: past 64pt or a flick past 600pt/s, to the next tab (1) or the one before
    /// (-1); nil when it's neither.
    static func tabStep(_ x: CGFloat, _ velocity: CGFloat) -> Int? { abs(x) > 64 || abs(velocity) > 600 ? (x < 0 ? 1 : -1) : nil }

    var sharesTouches = false
    var onChange: (CGFloat) -> Void
    var onEnd: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator(sharesTouches: sharesTouches) }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let x = pan.translation(in: pan.view).x
        switch pan.state {
        case .changed: onChange(x)
        case .ended, .cancelled, .failed: onEnd(x, pan.velocity(in: pan.view).x)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let sharesTouches: Bool
        init(sharesTouches: Bool) { self.sharesTouches = sharesTouches }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            if sharesTouches, let window = pan.view?.window {
                let x = pan.location(in: window).x - pan.translation(in: window).x
                if x < 24 || x > window.bounds.width - 24 { return false }
                let start = CGPoint(x: x, y: pan.location(in: window).y - pan.translation(in: window).y)
                if SwipeZones.frames.values.contains(where: { $0.contains(start) }) { return false }
                var node = window.hitTest(pan.location(in: window), with: nil)
                while let view = node {
                    if view is UIControl { return false }
                    node = view.superview
                }
            }
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            sharesTouches
        }
    }
}

/// Where sideways drags belong to a native list's rows (their own swipe to delete), on screen. Lists add themselves
/// as they lay out and leave when they go; it isn't observed, so scrolling costs nothing.
enum SwipeZones {
    nonisolated(unsafe) static var frames: [String: CGRect] = [:]
}

/// One row with iOS's own swipe, as Home's workout card: swipe it left for Edit and Delete, round icons that follow
/// the finger on the system's physics (a tap on either closes it). A one-row list, exactly as tall as its row, that
/// keeps the tab swipe away from itself (SwipeZones).
struct SwipeRow<Content: View>: View {
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 44
    @State private var zone = UUID().uuidString
    @State private var frame: CGRect?

    var body: some View {
        List {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                // The first is nearest the edge: Delete, then Edit.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(action: onDelete) { Label("Delete", systemImage: "trash").labelStyle(.iconOnly) }.tint(Palette.danger)
                    Button(action: onEdit) { Label("Edit", systemImage: "pencil").labelStyle(.iconOnly) }.tint(Palette.action)
                }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 0)
        .frame(height: height)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0; SwipeZones.frames[zone] = $0 }
        .onAppear { if let frame { SwipeZones.frames[zone] = frame } }
        .onDisappear { SwipeZones.frames[zone] = nil }
    }
}
