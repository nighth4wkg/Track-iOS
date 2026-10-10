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

/// The website's swipe to delete (components/gesture-item): the row slides left under the finger inside its rounded
/// card while a rounded red Delete slides in from the right edge. Any visible reveal opens it, a flick or any drag back
/// closes it; a tap on Delete deletes. Opening ticks; Delete warns. With `onEdit`, Edit shows beside Delete and the
/// row opens twice as far.
struct SwipeToDelete<Content: View>: View {
    var label = "Delete"
    let onDelete: () -> Void
    var onEdit: (() -> Void)? = nil
    @ViewBuilder let content: Content
    @State private var offset: CGFloat = 0
    @State private var open = false
    @State private var start: CGFloat = 0
    /// One action's width; the row opens as wide as its actions.
    private let action: CGFloat = 88
    private var width: CGFloat { action * (onEdit == nil ? 1 : 2) }

    var body: some View {
        ZStack(alignment: .trailing) {
            content
                .offset(x: offset)
                .allowsHitTesting(!open)
            HStack(spacing: 8) {
                if let onEdit {
                    Button { settle(false); onEdit() } label: {
                        tile("Edit", "pencil").foregroundStyle(Palette.text).glass(radius: 14, fill: Palette.control, lifted: false)
                    }
                    .buttonStyle(PressStyle())
                }
                Button(role: .destructive) { onDelete() } label: {
                    tile(label, "trash").foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Palette.danger, Palette.dangerDeep], startPoint: .topLeading, endPoint: .bottomTrailing)))
                }
                .buttonStyle(PressStyle())
            }
            .offset(x: width + offset)
            .opacity(offset < 0 ? 1 : 0)
            .accessibilityHidden(!open)
        }
        .contentShape(Rectangle())
        .clipped()
        .gesture(HorizontalPan(onChange: { x in
            offset = max(-width, min(0, start + x))
        }, onEnd: { x, velocity in
            // A flick decides; otherwise any drag left opens and any drag right closes.
            settle(abs(velocity) > HorizontalPan.flick ? velocity < 0 : x < -1 ? true : x > 1 ? false : open)
        }))
        .simultaneousGesture(TapGesture().onEnded { if open { settle(false) } })
        .sensoryFeedback(.impact(weight: .light), trigger: open) { _, now in now }
        .accessibilityAction(named: label) { onDelete() }
        .accessibilityActions { if let onEdit { Button("Edit", action: onEdit) } }
    }

    /// An action's face: its icon over its name, the tile's size.
    private func tile(_ name: String, _ icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.body.weight(.semibold))
            Text(name).font(.caption.weight(.semibold))
        }
        .frame(width: action - 8, height: 52)
    }

    private func settle(_ opening: Bool) {
        withAnimation(.smooth(duration: 0.24)) { offset = opening ? -width : 0 }
        open = opening
        start = offset
    }
}
