import SwiftUI

extension View {
    /// The workout's set numbers typed on one keyboard: an unseen input (KeyInput) stays first responder while any
    /// set is typed in, so Next only moves the highlight. A field taking the keyboard made iOS rebuild it, most of
    /// what each Next cost. The set being typed in is scrolled into view, as iOS does for a field it focuses.
    func setKeyboard(_ focus: Binding<String?>) -> some View { modifier(SetKeyboard(focus: focus)) }
}

private struct SetKeyboard: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var focus: String?

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .background(alignment: .topLeading) {
                    // Only built while typing, so there's no field of its own for VoiceOver or the UI tests (the set's
                    // boxes are) and nothing for iOS to hand the keyboard back to when a sheet closes. The keyboard going
                    // by itself (dragged away, another field taking it) ends the typing.
                    if focus != nil {
                        KeyInput { if focus != nil { focus = nil } }
                            .frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true).transition(.identity)
                    }
                }
                .onChange(of: focus) { reveal(proxy) }
                // A dialog (they open in their own window) ends the typing, rather than leaving the keyboard under it.
                .onChange(of: model.confirm != nil) { _, open in if open { focus = nil } }
                // The keyboard coming up (or the bar over it changing) can cover the set.
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { _ in reveal(proxy) }
        }
    }

    /// Scrolls just enough to show the set being typed in, once a card it opens has its height.
    private func reveal(_ proxy: ScrollViewProxy) {
        guard let focus, let dot = focus.lastIndex(of: ".") else { return }
        let set = String(focus[..<dot])
        DispatchQueue.main.async { withAnimation(.smooth(duration: Motion.standard)) { proxy.scrollTo(set) } }
    }
}

/// The unseen input: the system's decimal pad, whose keys go to the set row being typed in (SetRow.key).
struct KeyInput: UIViewRepresentable {
    /// A key: the text added, or nil for delete.
    static let typed = Notification.Name("KeyInput.typed")
    let onEnd: () -> Void

    func makeUIView(context: Context) -> Field { Field() }

    func updateUIView(_ view: Field, context: Context) {
        view.onEnd = onEnd
        guard !view.started else { return }
        view.started = true
        // After the update: taking the keyboard changes the safe area being laid out.
        DispatchQueue.main.async { _ = view.becomeFirstResponder() }
    }

    /// Typing ended: the keyboard goes with the field.
    static func dismantleUIView(_ view: Field, coordinator: ()) {
        view.onEnd = {}
        _ = view.resignFirstResponder()
    }

    final class Field: UIView, UIKeyInput {
        var onEnd: () -> Void = {}
        var started = false
        var keyboardType: UIKeyboardType = .decimalPad
        override var canBecomeFirstResponder: Bool { true }
        var hasText: Bool { true }
        func insertText(_ text: String) { NotificationCenter.default.post(name: KeyInput.typed, object: text) }
        func deleteBackward() { NotificationCenter.default.post(name: KeyInput.typed, object: nil) }
        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { onEnd() }
            return resigned
        }
    }
}
