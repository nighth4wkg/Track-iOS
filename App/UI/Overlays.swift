import SwiftUI
import TrackCore

// What shows over the screen, as the PWA's: sheets (ui/parts.tsx Sheet), the question before something that can't be
// taken back (AskSheet) and the pill at the bottom (Toasts). They show and go at once.

extension EnvironmentValues {
    /// Closes the sheet this view is in.
    @Entry var closeSheet: () -> Void = {}
}

/// The open sheets, newest on top, over a dim; a tap on the dim closes the top one.
struct SheetLayer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            ForEach(model.sheets) { sheet in
                ZStack(alignment: .bottom) {
                    Palette.scrim.ignoresSafeArea().onTapGesture { close(sheet) }
                    SheetBox(tall: sheet.tall, close: { close(sheet) }) { sheet.view }
                        .environment(\.closeSheet, { close(sheet) })
                }
                // Only the top sheet speaks to VoiceOver (none while the question is up).
                .accessibilityHidden(sheet.id != model.sheets.last?.id || model.confirm != nil)
                // The layer reaches the screen's bottom edge (not the home indicator's), so the sheet sits 8 above
                // it; the keyboard still lifts it.
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
    }

    private func close(_ sheet: Presented) {
        if let onClose = sheet.onClose { onClose() } else { model.dismiss(sheet.id) }
    }
}

/// One sheet's box: the SHEET surface, 8 above the screen's bottom edge (above the keyboard while it's up), as tall
/// as what it holds up to the screen (SheetFrame scrolls what's under its title past that). Its top (grab bar and
/// title row) follows a finger down and closes it when let go past 40% of its height or flicked.
private struct SheetBox<Content: View>: View {
    let tall: Bool
    let close: () -> Void
    @ViewBuilder let content: Content
    @State private var finger = Finger()
    @State private var pulling = false
    @State private var height: CGFloat = 0
    /// Let go past this share of its height (or flicked as far), it closes: the PWA's CLOSE_DRAG.
    private static var closeShare: Double { 0.4 }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Palette.handle).frame(width: Size.handle.width, height: Size.handle.height)
                .frame(maxWidth: .infinity).padding(.top, Size.handleTop).padding(.bottom, Space.s3)
                .contentShape(Rectangle())
                .gesture(drag)
                .accessibilityHidden(true)
            // As tall as what it holds up to the room there is: swapping a plain copy for a scrolling one
            // (ViewThatFits) when the keyboard came up rebuilt the content, so it jumped and its field lost the keyboard.
            Group { if tall { content } else { UpToContent { content } } }
            .environment(\.sheetDrag, drag)
        }
        .frame(maxWidth: Size.column - Space.s4, maxHeight: tall ? .infinity : nil, alignment: .top)
        .raised(.sheet, .sheet)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .follow(finger, while: pulling)
        .padding(.horizontal, Space.s2)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s2)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
    }

    private var drag: AnyGesture<DragGesture.Value> {
        // Measured on the screen: in the sheet's own space the distance shrinks as the sheet follows the finger, so
        // a slow drag jittered.
        AnyGesture(DragGesture(minimumDistance: Space.s1, coordinateSpace: .global)
            .onChanged {
                finger.y = max(0, $0.translation.height)
                if !pulling { pulling = true }
            }
            .onEnded { value in
                let down = max(0, value.translation.height)
                finger.speed = value.velocity.height
                pulling = false
                if down > height * Self.closeShare || value.predictedEndTranslation.height - value.translation.height > height * Self.closeShare { close() }
            })
    }
}

/// Its one view as tall as it would be (a scroll view: its content), but no taller than offered.
private struct UpToContent: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let ideal = view.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? ideal.width, height: min(ideal.height, proposal.height ?? ideal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

extension EnvironmentValues {
    /// A sheet's drag down, for its title row to carry too.
    @Entry var sheetDrag: AnyGesture<DragGesture.Value>?
}

/// A sheet's head and content (the PWA's Sheet): the title (and a line under it) beside one button (Done, or Cancel
/// on a sheet that saves, or `action` in its place), then the content. Only the content scrolls: the title row and
/// its Done stay put, as in iOS's own sheets.
struct SheetFrame<Content: View, Action: View>: View {
    @Environment(\.closeSheet) private var close
    @Environment(\.sheetDrag) private var drag
    let title: String
    var subtitle: String?
    var closeLabel = "Done"
    /// What stays under the title (a search and its filters): scrolled away, it slid half under the title.
    var pinned: AnyView? = nil
    @ViewBuilder var action: Action
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).type(.t20).foregroundStyle(Palette.text)
                    if let subtitle { Text(subtitle).type(.t14).foregroundStyle(Palette.muted) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(drag ?? AnyGesture(DragGesture().onChanged { _ in }))
                .accessibilityAddTraits(.isHeader)
                if Action.self == EmptyView.self {
                    Button(closeLabel, action: close).buttonStyle(SecondaryStyle(hug: true))
                } else {
                    action
                }
            }
            .padding(.horizontal, Space.s4)
            if let pinned { pinned.padding(.horizontal, Space.s4) }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
            }
            .scrollDismissesKeyboard(.interactively).scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SheetFrame where Action == EmptyView {
    init(title: String, subtitle: String? = nil, closeLabel: String = "Done", pinned: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, closeLabel: closeLabel, pinned: pinned, action: { EmptyView() }, content: content)
    }
}

/// The question (model.confirm) as a sheet over everything: what happens, the action (green, or red when it can't
/// be taken back) over Cancel.
struct AskLayer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let confirm = model.confirm {
            let cancel = { model.confirm = nil }
            ZStack(alignment: .bottom) {
                Palette.scrim.ignoresSafeArea().onTapGesture(perform: cancel)
                VStack(alignment: .leading, spacing: 0) {
                    Text(confirm.title).type(.t20).foregroundStyle(Palette.text).accessibilityAddTraits(.isHeader)
                    Text(confirm.message).type(.t14).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.s2)
                    VStack(spacing: Space.s3) {
                        Button(confirm.label) { model.confirm = nil; confirm.action() }
                            .buttonStyle(AnswerStyle(destructive: confirm.destructive))
                        Button("Cancel", action: cancel).buttonStyle(SecondaryStyle())
                    }
                    .padding(.top, Space.s4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .pad()
                .padding(.top, Space.s2)
                .frame(maxWidth: Size.column - Space.s4)
                .raised(.sheet, .sheet)
                .padding(.horizontal, Space.s2)
                .padding(.bottom, Space.s2)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, cancel)
                .sensoryFeedback(confirm.destructive ? .warning : .impact(weight: .light), trigger: confirm.id)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    private struct AnswerStyle: ButtonStyle {
        let destructive: Bool
        func makeBody(configuration: Configuration) -> some View {
            if destructive { SecondaryStyle(danger: true).makeBody(configuration: configuration) } else { PrimaryStyle().makeBody(configuration: configuration) }
        }
    }
}

/// The pill at the bottom (model.toast): a tick when something worked, Undo when there's something to bring back.
/// Gone after a few seconds, on ✕, or on a swipe down. It sits `above` the floating bar under it (the nav pill, the rest
/// timer, a docked button); while
/// typing, or while a sheet is open, it moves to the top, off the fields and the sheet's buttons.
struct ToastLayer: View {
    @Environment(AppModel.self) private var model
    let above: CGFloat
    @State private var keyboard = false
    /// How long a pill stays, as the PWA's PILL_MS: a problem a little longer to read, Undo longer to reach it.
    private static let seconds = (done: 3.0, problem: 4.0, undo: 6.0)

    var body: some View {
        let top = keyboard || !model.sheets.isEmpty
        VStack {
            if let toast = model.toast {
                let dismiss = { model.toast = nil }
                HStack(spacing: Space.s3) {
                    if toast.problem {
                        Icon.alert.image(IconSize.medium, bold: true).foregroundStyle(Palette.danger).accessibilityHidden(true)
                    } else if toast.undo == nil {
                        Icon.check.image(IconSize.medium, bold: true).foregroundStyle(Palette.accent).accessibilityHidden(true)
                    }
                    Text(toast.text).type(.t14).fontWeight(.semibold).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                    if let undo = toast.undo {
                        Button("Undo") { undo(); dismiss() }.buttonStyle(SecondaryStyle(height: Size.tile, hug: true)).foregroundStyle(Palette.accent)
                    }
                    Button(action: dismiss) {
                        Icon.close.image(IconSize.medium).foregroundStyle(Palette.muted)
                            .frame(width: Size.control, height: Size.control).contentShape(Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss")
                }
                .accessibilityElement(children: .contain)
                .padding(.leading, Space.s4 + Space.s1).padding(.trailing, Space.s1).padding(.vertical, Space.s2)
                .frame(minHeight: Size.row)
                .raised(.float, .pill)
                .padding(.horizontal, Space.s4)
                .gesture(DragGesture(minimumDistance: Space.s2).onEnded { if $0.translation.height > Space.s4 { dismiss() } })
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(toast.undo != nil ? Self.seconds.undo : toast.problem ? Self.seconds.problem : Self.seconds.done))
                    if model.toast?.id == toast.id { dismiss() }
                }
                .frame(maxHeight: .infinity, alignment: top ? .top : .bottom)
                .padding(.top, top ? Space.s2 : 0)
                .floatingBottom(top ? 0 : above)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboard = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboard = false }
    }
}
