import SwiftUI
import TrackCore
import UIKit

/// Track's question (the PWA's ask sheet) lives in their own window above everything, so
/// the dim covers the tab bar and any sheet too. The window lets touches through until a dialog is up.
enum DialogWindow {
    private static var window: UIWindow?

    static func install(_ model: AppModel) {
        MainActor.assumeIsolated {
            guard window == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
            let host = UIHostingController(rootView: DialogLayer().environment(model))
            host.view.backgroundColor = .clear
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert
            window.rootViewController = host
            window.overrideUserInterfaceStyle = .dark
            window.isUserInteractionEnabled = false
            window.isHidden = false
            Self.window = window
        }
    }

    /// Takes touches while a dialog is up.
    static func update(open: Bool) {
        MainActor.assumeIsolated { window?.isUserInteractionEnabled = open }
    }
}

/// The dim and the question showing, as the PWA's ask sheet: its title and what happens, then the action (green, or
/// red when it can't be taken back) over Cancel, rising from the bottom. Tapping around it cancels.
private struct DialogLayer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cancel = { model.confirm = nil }
        ZStack(alignment: .bottom) {
            if model.confirm != nil { Palette.dim.ignoresSafeArea().onTapGesture(perform: cancel).transition(.opacity) }
            if let confirm = model.confirm {
                ConfirmCard(confirm: confirm).id(confirm.id)
                    .padding(.horizontal, Space.s4).padding(.top, Space.s6).padding(.bottom, Space.s6)
                    .frame(maxWidth: Measure.page)
                    .raised(.sheet, .sheet)
                    .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape, cancel)
                    .transition(.move(edge: .bottom))
                    .sensoryFeedback(confirm.destructive ? .warning : .impact(weight: .light), trigger: confirm.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(.container, edges: .bottom)
        .animation(.smooth(duration: Motion.standard), value: model.confirm?.id)
    }
}

private struct ConfirmCard: View {
    @Environment(AppModel.self) private var model
    let confirm: Confirm

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(confirm.title).type(.t20).foregroundStyle(Palette.text).accessibilityAddTraits(.isHeader)
            Text(confirm.message).type(.t14).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s2)
            VStack(spacing: Space.s3) {
                if confirm.destructive {
                    Button(confirm.label, action: resolve).buttonStyle(SecondaryButtonStyle(danger: true)).accessibilityIdentifier("dialog-action")
                } else {
                    Button(confirm.label, action: resolve).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("dialog-action")
                }
                Button("Cancel") { model.confirm = nil }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resolve() { model.confirm = nil; confirm.action() }
}

/// A pill over the bottom ("Set removed." Undo ✕), as the PWA's: a tick when it just says something worked, Undo when
/// there's something to bring back. Gone after a few seconds, ✕, or a swipe down. Each screen carries one and only
/// the topmost screen's shows it (the last to appear), so a toast over the workout isn't drawn on Home behind it.
struct ToastOverlay: View {
    @Environment(AppModel.self) private var model
    /// The nav pill is showing: the toast sits above it.
    var nav = false
    @State private var host = UUID()
    /// While typing, the toast shows at the top instead, off the rows being filled in.
    @State private var keyboard = false

    var body: some View {
        let dismiss = { withAnimation(.smooth(duration: Motion.standard)) { model.toast = nil } }
        VStack {
            if let toast = model.toast, model.toastHosts.last == host {
                HStack(spacing: Space.s3) {
                    if toast.undo == nil {
                        Image(systemName: "checkmark").font(.system(size: IconSize.medium, weight: .bold)).foregroundStyle(Palette.accent)
                            .accessibilityHidden(true)
                    }
                    Text(toast.text).type(.t14).fontWeight(.semibold).foregroundStyle(Palette.text).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let undo = toast.undo {
                        Button("Undo") { undo(); dismiss() }
                            .buttonStyle(SecondaryButtonStyle(height: Size.tile, hug: true)).foregroundStyle(Palette.accent)
                    }
                    Button(action: dismiss) {
                        Image(systemName: "xmark").font(.system(size: IconSize.medium, weight: .semibold)).foregroundStyle(Palette.muted)
                            .frame(width: Size.control, height: Size.control).contentShape(Circle())
                    }
                    .buttonStyle(PressStyle()).accessibilityLabel("Dismiss")
                }
                .accessibilityElement(children: .contain)
                .padding(.leading, Space.s4).padding(.trailing, Space.s1).padding(.vertical, Space.s1)
                .frame(minHeight: Size.row)
                .raised(.float, .pill)
                .padding(.horizontal, Space.s4)
                .padding(keyboard ? .top : .bottom, keyboard ? Space.s2 : Space.s4 + (nav ? Size.nav + Space.s3 : 0))
                .gesture(DragGesture(minimumDistance: Space.s2).onEnded { if $0.translation.height > Space.s4 { dismiss() } })
                .transition(.move(edge: keyboard ? .top : .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(toast.undo == nil ? 4 : 6)) // a little longer to reach Undo
                    if model.toast?.id == toast.id { dismiss() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: keyboard ? .top : .bottom)
        .ignoresSafeArea(.container, edges: keyboard ? [] : .bottom)
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
    func trackOverlays(nav: Bool = false) -> some View { overlay { ToastOverlay(nav: nav) } }
}
