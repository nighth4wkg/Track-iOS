import SwiftUI

/// The first screen: where to keep your training. Sync (an account shared with the website) or this iPhone only.
/// Only the sync card carries the accent. Local can turn on sync later in Settings.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var syncSoon = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Brand().padding(.bottom, 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your training space").font(.body).foregroundStyle(Palette.muted)
                    Text("Welcome to Track").font(.largeTitle.weight(.bold)).foregroundStyle(Palette.text)
                }
                Text("Choose where your workouts live.").font(.body).foregroundStyle(Palette.muted).padding(.bottom, 8)
                ChoiceCard(icon: "arrow.triangle.2.circlepath.icloud", title: "Sync across devices",
                           detail: "Sign up or log in. Your workouts on iPhone, iPad and the web.", accent: true, badge: "Soon") {
                    syncSoon = true
                }
                ChoiceCard(icon: "iphone", title: "Keep it on this iPhone",
                           detail: "No account. Everything stays on this device.") {
                    withAnimation(.smooth) { model.choose(.local) }
                }
                Text("You can turn on sync later in Settings.")
                    .font(.footnote).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity).padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Backdrop())
        .alert("Sync is coming soon", isPresented: $syncSoon) {
            Button("Keep it on this iPhone") { withAnimation(.smooth) { model.choose(.local) } }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Signing in with your Track account arrives in an upcoming build. Start on this iPhone now and turn on sync later; nothing is lost.")
        }
    }
}

/// One choice: an icon tile, a title over one line of detail, and a chevron, on a glass card.
private struct ChoiceCard: View {
    let icon: String
    let title: String
    let detail: String
    var accent = false
    var badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent ? Palette.accent : Palette.text)
                    .frame(width: 48, height: 48)
                    .glass(radius: 14, fill: Palette.control, lifted: false)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline).foregroundStyle(Palette.text)
                        if let badge {
                            Text(badge).font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .glass(radius: 10, fill: Palette.control, lifted: false)
                        }
                    }
                    Text(detail).font(.subheadline).foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 88)
            .glass()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// A gentle press: the card dims a touch, it doesn't jump.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
