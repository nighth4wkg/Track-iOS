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
                    // The keyboard going by itself (dragged away, another field taking it) ends the typing.
                    KeyInput(active: focus != nil) { if focus != nil { focus = nil } }
                        .frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true)
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
    let active: Bool
    let onEnd: () -> Void

    func makeUIView(context: Context) -> Field { Field() }

    func updateUIView(_ view: Field, context: Context) {
        view.onEnd = onEnd
        guard view.wanted != active else { return }
        view.wanted = active
        // After the update: taking or giving up the keyboard changes the safe area being laid out.
        DispatchQueue.main.async {
            if view.wanted { _ = view.becomeFirstResponder() } else if view.isFirstResponder { _ = view.resignFirstResponder() }
        }
    }

    final class Field: UIView, UIKeyInput {
        var onEnd: () -> Void = {}
        var wanted = false
        var keyboardType: UIKeyboardType = .decimalPad
        /// Only while a set is typed in: iOS hands the keyboard back to what had it when a sheet closes, even after
        /// the typing has ended.
        override var canBecomeFirstResponder: Bool { wanted }
        var hasText: Bool { true }
        func insertText(_ text: String) { NotificationCenter.default.post(name: KeyInput.typed, object: text) }
        func deleteBackward() { NotificationCenter.default.post(name: KeyInput.typed, object: nil) }
        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { wanted = false; onEnd() }
            return resigned
        }
    }
}
