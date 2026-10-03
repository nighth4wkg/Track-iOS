import SwiftUI
import TrackCore
import UIKit

/// The website's dialog (components/confirm-dialog): a glass card over a dimmed page with the question, what it
/// means, and Cancel beside the action (green, or red when it can't be undone). It fades and scales in smoothly.
struct ConfirmOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if let confirm = model.confirm {
                Color.black.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { withAnimation(.smooth(duration: 0.2)) { model.confirm = nil } }
                    .transition(.opacity)
                VStack(alignment: .leading, spacing: 12) {
                    Text(confirm.title).font(.title3.weight(.bold)).foregroundStyle(Palette.text)
                    Text(confirm.message).font(.subheadline).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button("Cancel") { withAnimation(.smooth(duration: 0.2)) { model.confirm = nil } }
                            .buttonStyle(SecondaryButtonStyle())
                        if confirm.destructive {
                            Button(confirm.label) { resolve(confirm) }
                                .font(.headline).foregroundStyle(Palette.danger)
                                .frame(maxWidth: .infinity, minHeight: 50).contentShape(Rectangle())
                                .buttonStyle(PressStyle())
                        } else {
                            Button(confirm.label) { resolve(confirm) }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: 420)
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial))
                .glass(radius: 28, fill: Palette.card)
                .padding(24)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
                .sensoryFeedback(confirm.destructive ? .warning : .impact(weight: .light), trigger: confirm.id)
            }
        }
        .animation(.smooth(duration: 0.25), value: model.confirm?.id)
    }

    private func resolve(_ confirm: Confirm) {
        withAnimation(.smooth(duration: 0.2)) { model.confirm = nil }
        confirm.action()
    }
}

/// A short note at the bottom ("Set removed · Undo"), gone after a few seconds or a swipe down.
struct ToastOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack {
            Spacer()
            if let toast = model.toast {
                HStack(spacing: 12) {
                    Text(toast.text).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    Spacer(minLength: 8)
                    if let undo = toast.undo {
                        Button("Undo") { undo(); withAnimation(.smooth) { model.toast = nil } }
                            .font(.subheadline.weight(.bold)).foregroundStyle(Palette.accent)
                    }
                }
                .padding(.horizontal, 18).frame(minHeight: 52)
                .background(Capsule().fill(.ultraThinMaterial))
                .glass(radius: 26, fill: .clear)
                .padding(.horizontal, 16).padding(.bottom, 92)
                .gesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.height > 20 { withAnimation(.smooth) { model.toast = nil } } })
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(4))
                    if model.toast?.id == toast.id { withAnimation(.smooth) { model.toast = nil } }
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: model.toast)
    }
}

extension View {
    /// Track's dialog and toast over this screen (each presented screen carries its own, so they show above it).
    func trackOverlays() -> some View {
        overlay { ToastOverlay() }.overlay { ConfirmOverlay() }
    }
}

/// Light, Dark or System for every window at once, sheets included, the moment it changes.
enum Appearance {
    static func apply(_ theme: TrackCore.Settings.Theme) {
        let style: UIUserInterfaceStyle = theme == .light ? .light : theme == .dark ? .dark : .unspecified
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] { window.overrideUserInterfaceStyle = style }
        }
    }
}
