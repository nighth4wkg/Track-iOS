import SwiftUI
import TrackCore

/// A sheet, as the PWA's Sheet (ui/parts.tsx): iOS's own sheet on the SHEET surface with its grab bar, as tall as its
/// content, the title (and a line under it) beside one button (Done, or Cancel on a sheet that saves), then the content.
struct SheetFrame<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var subtitle: String?
    var closeLabel = "Done"
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).type(.t20).foregroundStyle(Palette.text).lineLimit(1)
                        if let subtitle { Text(subtitle).type(.t14).foregroundStyle(Palette.muted).lineLimit(1) }
                    }
                    .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button(closeLabel) { dismiss() }.buttonStyle(SecondaryButtonStyle(hug: true))
                }
                content
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s6)
            .padding(.bottom, Space.s4)
            .frame(maxWidth: Measure.page)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents(height > 0 ? [.height(height)] : [.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground { LinearGradient(colors: Surface.sheet.shade, startPoint: .top, endPoint: .bottom) }
    }
}

/// A text field, as the PWA's .field: SUNK, a control tall, ringed green while you type in it.
struct Field: View {
    let placeholder: String
    @Binding var text: String
    /// What VoiceOver calls it.
    let label: String
    var limit = Limits.name
    /// A mark at its start, as the search's magnifier.
    var icon: String?
    var keyboard = UIKeyboardType.default
    var submit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.s2) {
            if let icon { Image(systemName: icon).font(.system(size: IconSize.medium)).foregroundStyle(Palette.muted).accessibilityHidden(true) }
            TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(Palette.placeholder))
                .focused($focused)
                .keyboardType(keyboard)
                .submitLabel(.done)
                .onSubmit(submit)
                .scaledFont(TextStyle.t16.size)
                .foregroundStyle(Palette.text)
        }
            .padding(.horizontal, Space.s3)
            .frame(minHeight: Size.control)
            .sunk(.inner, ring: focused ? Palette.accent : nil)
            .onChange(of: text) { _, value in if value.count > limit { text = String(value.prefix(limit)) } }
            .toolbar {
                // Number pads have no return key.
                if keyboard != .default, focused { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false; submit() } } }
            }
    }
}
