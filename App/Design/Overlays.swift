import SwiftUI
import TrackCore
import UIKit

/// Track's dialogs (components/confirm-dialog, split-name-dialog) live in their own window above everything, so
/// the dim covers the tab bar and any sheet too. The window lets touches through until a dialog is up.
enum DialogWindow {
    private static var window: UIWindow?
    private static weak var main: UIWindow?

    static func install(_ model: AppModel) {
        MainActor.assumeIsolated {
            guard window == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
            main = scene.keyWindow
            let host = UIHostingController(rootView: DialogLayer().environment(model))
            host.view.backgroundColor = .clear
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert
            window.rootViewController = host
            window.overrideUserInterfaceStyle = main?.overrideUserInterfaceStyle ?? .unspecified
            window.isUserInteractionEnabled = false
            window.isHidden = false
            Self.window = window
        }
    }

    /// Takes touches while a dialog is up, and the keyboard while one asks for a name.
    static func update(open: Bool, typing: Bool) {
        MainActor.assumeIsolated {
            if main == nil { main = window?.windowScene?.windows.first { $0 !== window } }
            window?.isUserInteractionEnabled = open
            if typing { window?.makeKey() } else if window?.isKeyWindow == true { main?.makeKey() }
        }
    }
}

/// The dim and the one dialog showing: a question (Cancel beside the action, green or red), or a name to type.
/// It fades and scales in smoothly; tapping around it cancels. A card taller than the space left (a small iPhone,
/// large text, the keyboard up) scrolls.
private struct DialogLayer: View {
    @Environment(AppModel.self) private var model
    @State private var height: CGFloat = 0

    var body: some View {
        let open = model.confirm != nil || model.naming != nil
        let cancel = { model.confirm = nil; model.naming = nil }
        ZStack {
            if open { Palette.dim.ignoresSafeArea().transition(.opacity) }
            ScrollView {
                Group {
                    if let confirm = model.confirm {
                        ConfirmCard(confirm: confirm).id(confirm.id).dialogCard()
                            .sensoryFeedback(confirm.destructive ? .warning : .impact(weight: .light), trigger: confirm.id)
                    } else if let naming = model.naming {
                        NameCard(naming: naming).id(naming.id).dialogCard()
                    }
                }
                .accessibilityAction(.escape, cancel)
                .frame(maxWidth: .infinity, minHeight: height)
                .background { if open { Color.clear.contentShape(Rectangle()).onTapGesture(perform: cancel) } }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .animation(.smooth(duration: Motion.quick), value: model.confirm?.id)
        .animation(.smooth(duration: Motion.quick), value: model.naming?.id)
    }
}

private struct ConfirmCard: View {
    @Environment(AppModel.self) private var model
    let confirm: Confirm

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(confirm.title).font(.title3.weight(.bold)).foregroundStyle(Palette.text)
            Text(confirm.message).font(.subheadline).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Cancel") { model.confirm = nil }.buttonStyle(SecondaryButtonStyle())
                if confirm.destructive {
                    Button(confirm.label, action: resolve).buttonStyle(SecondaryButtonStyle(danger: true)).accessibilityIdentifier("dialog-action")
                } else {
                    Button(confirm.label, action: resolve).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("dialog-action")
                }
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.top, 10)
        }
    }

    private func resolve() { model.confirm = nil; confirm.action() }
}

/// Naming a split or workout: "Give your routine a name that makes sense to you.", the field, Cancel and the action.
private struct NameCard: View {
    @Environment(AppModel.self) private var model
    let naming: Naming
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(naming.title).font(.title3.weight(.bold)).foregroundStyle(Palette.text)
                Spacer()
                GlassCircleButton(icon: "xmark", label: "Close") { model.naming = nil }.padding(.top, -6).padding(.trailing, -6)
            }
            Text(naming.message).font(.subheadline).foregroundStyle(Palette.muted)
            Text(naming.label).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text).padding(.top, 6).accessibilityHidden(true) // read as the field's own name (a filled field had none)
            TextField(naming.placeholder, text: $name).focused($focused).submitLabel(.done).onSubmit(save).accessibilityLabel(naming.label)
                .keyboardType(naming.number ? .decimalPad : .default)
                .font(.body.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.input))
                .onChange(of: name) { _, value in if value.count > Limits.name { name = String(value.prefix(Limits.name)) } }
            Button(action: save) { Label(naming.action, systemImage: "arrow.up.right").labelStyle(TrailingIcon()) }
                .buttonStyle(PrimaryButtonStyle()).disabled(trimmed.isEmpty).padding(.top, 6)
                .accessibilityIdentifier("dialog-action")
        }
        .onAppear { name = naming.name; DispatchQueue.main.async { focused = true } }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.naming = nil
        naming.onSave(trimmed)
    }
}

private extension View {
    /// A solid card with the glass rim, centred, that scales in.
    func dialogCard() -> some View {
        padding(24)
            .frame(maxWidth: 420)
            .glass(radius: 28, fill: Palette.dialog)
            .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
            .padding(20)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
    }
}

/// A short note at the bottom ("Set removed · Undo"), gone after a few seconds or a swipe down.
/// Each screen carries one, and only the topmost screen's shows it (the last to appear), so a toast over the
/// workout isn't also drawn on Home behind it.
struct ToastOverlay: View {
    @Environment(AppModel.self) private var model
    @State private var host = UUID()
    /// While typing, the toast shows at the top instead, off the rows being filled in.
    @State private var keyboard = false

    var body: some View {
        VStack {
            if let toast = model.toast, model.toastHosts.last == host {
                HStack(spacing: 12) {
                    Text(toast.text).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
                    Spacer(minLength: 8)
                    if let undo = toast.undo {
                        Button("Undo") { undo(); withAnimation(.smooth) { model.toast = nil } }
                            .font(.subheadline.weight(.bold)).foregroundStyle(Palette.accent)
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                }
                .accessibilityElement(children: .contain)
                .padding(.horizontal, 18).frame(minHeight: 52)
                .background(Capsule().fill(.ultraThinMaterial))
                .glass(radius: 26, fill: .clear)
                .padding(.horizontal, 16).padding(keyboard ? .top : .bottom, keyboard ? 52 : 92) // under the navigation bar while typing
                .gesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.height > 20 { withAnimation(.smooth) { model.toast = nil } } })
                .transition(.move(edge: keyboard ? .top : .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(toast.undo == nil ? 4 : 6)) // a little longer to reach Undo
                    if model.toast?.id == toast.id { withAnimation(.smooth) { model.toast = nil } }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: keyboard ? .top : .bottom)
        .animation(.smooth(duration: Motion.standard), value: model.toast)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboard = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboard = false }
        .onAppear { model.toastHosts.append(host) }
        .onDisappear { model.toastHosts.removeAll { $0 == host } }
    }
}

extension View {
    /// Track's toast over this screen (each presented screen carries its own, so it shows above it), and the chosen
    /// Light or Dark: a sheet is its own presentation, so an open Settings sheet switches the moment it's changed.
    func trackOverlays() -> some View { modifier(Presented()) }
}

private struct Presented: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        let theme = model.training.settings.theme
        content.overlay { ToastOverlay() }.preferredColorScheme(theme == .light ? .light : theme == .dark ? .dark : nil)
    }
}
