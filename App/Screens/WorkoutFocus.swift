import SwiftUI
import TrackCore

/// The parts of the workout that follow the keyboard focus, each its own small view: reading the focus in the
/// workout page itself redrew the whole page (toolbar, bars, every card) on each Next.

/// One card's share of the focus: the field being typed in when it's on this card, so a move redraws only the cards
/// it leaves and enters.
struct CardFocus<Content: View>: View {
    var focus: FocusState<String?>.Binding
    let sets: [TrainingSet]
    @ViewBuilder let content: (String?) -> Content

    var body: some View {
        content(focus.wrappedValue.flatMap { id in sets.contains { id.hasPrefix($0.id) } ? id : nil })
    }
}

/// The bar at the bottom: while typing, one capsule over the keyboard (the rest's time, Next, Done) instead of the rest
/// capsule. Without the keyboard the capsule dips into the home indicator's strip, 16pt from the screen's edge, as
/// iOS's own floating bars do (a phone with a home button has no strip, so it stays put).
struct WorkoutBottomBar: View {
    @Environment(AppModel.self) private var model
    var focus: FocusState<String?>.Binding
    let fields: [String]

    var body: some View {
        Group { if focus.wrappedValue != nil { keyboardBar } else { RestCapsule().padding(.bottom, -max(0, homeIndicator - 8)) } }
            .animation(.smooth(duration: Motion.quick), value: focus.wrappedValue == nil)
    }

    /// The home indicator's strip at the bottom of the screen (0 on a phone with a home button), never the keyboard.
    private var homeIndicator: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets.bottom ?? 0
    }

    /// Next walks weight → reps → RIR → next set; Done puts the keyboard away. It replaces the rest capsule meanwhile, so
    /// the two never stack up.
    private var keyboardBar: some View {
        // Without a rest it's just Next and Done, at the right: no empty bar.
        let resting = model.training.restUntil != nil
        return HStack(spacing: 8) {
            if resting {
                RestCapsule(compact: true)
                Spacer(minLength: 8)
            }
            if let current = focus.wrappedValue, let index = fields.firstIndex(of: current), index + 1 < fields.count {
                Button("Next") { focus.wrappedValue = fields[index + 1] }.foregroundStyle(Palette.text)
                    .padding(.horizontal, 22).frame(minHeight: 44).glass(radius: 22, fill: Palette.control, lifted: false)
            }
            Button("Done") { focus.wrappedValue = nil }.foregroundStyle(Palette.primaryText)
                .padding(.horizontal, 22).frame(minHeight: 44).glass(radius: 22, fill: Palette.primary, lifted: false)
        }
        .font(.body.weight(.semibold)).buttonStyle(PressStyle())
        // A floating glass capsule like the rest's, solid inside so the page doesn't show through; the pills sit 8pt in,
        // their curves matching its own.
        .padding(.leading, resting ? 14 : 8).padding(.trailing, 8).padding(.vertical, 8)
        .glass(radius: 30, fill: Palette.dialog)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 16).padding(.bottom, 8)
        .transition(.opacity)
    }
}
