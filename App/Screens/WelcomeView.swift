import SwiftUI

/// The first screen, as the PWA's sign-in page: the mark, "Welcome to Track" and what it's for, then the ways in.
/// Local works today (primary); sync with a Track account is marked Soon and says so. Local can turn on sync later.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var syncSoon = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    TrackMark(size: IconSize.emblem).foregroundStyle(Palette.text)
                        .frame(width: Size.emblem, height: Size.emblem).raised(.control, .inner).accessibilityHidden(true)
                    Text("Welcome to Track").type(.t32).foregroundStyle(Palette.text).padding(.top, Space.s4)
                    Text("Your splits, sets and progress.").type(.t14).foregroundStyle(Palette.muted)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                VStack(spacing: Space.s3) {
                    Button("Continue locally") { withAnimation(.smooth(duration: Motion.standard)) { model.choose(.local) } }
                        .buttonStyle(PrimaryButtonStyle())
                    Button { syncSoon = true } label: {
                        HStack(spacing: Space.s2) { Text("Sync with an account"); Badge(text: "Soon", plain: true) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, Space.s6)
                Text("Local mode keeps everything on this device.").type(.t14).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center).padding(.top, Space.s2)
            }
            .padding(Space.s4)
            .frame(maxWidth: Measure.narrow)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center) { length, _ in length }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Backdrop())
        .alert("Sync is coming soon", isPresented: $syncSoon) {
            Button("Continue locally") { withAnimation(.smooth(duration: Motion.standard)) { model.choose(.local) } }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Signing in with your Track account arrives in an upcoming build. Start locally now and turn on sync later; nothing is lost.")
        }
    }
}

/// A gentle press: the card dims a touch, it doesn't jump.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Motion.press : 1)
            .animation(.smooth(duration: Motion.fast), value: configuration.isPressed)
    }
}

/// A whole row as the button, as the PWA's button.row: it doesn't shrink, its row lights a faint wash while pressed.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Palette.wash : .clear)
            .animation(.smooth(duration: Motion.fast), value: configuration.isPressed)
    }
}
