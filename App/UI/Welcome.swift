import SwiftUI

/// The first screen (the PWA's sign-in page): the mark, "Welcome to Track" and what it's for, then the ways in. Local
/// works today (primary); sync with a Track account is marked Soon and says so. Local can turn on sync later.
struct WelcomeScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        TrackMark(size: IconSize.mark).foregroundStyle(Palette.text)
                            .frame(width: Size.emblem, height: Size.emblem).raised(.control, .inner).accessibilityHidden(true)
                        Text("Welcome to Track").type(.t32).foregroundStyle(Palette.text).padding(.top, Space.s4)
                        Text("Your splits, sets and progress.").type(.t14).foregroundStyle(Palette.muted)
                    }
                    .multilineTextAlignment(.center)
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                    VStack(spacing: Space.s3) {
                        Button("Continue locally") { model.choose(.local) }.buttonStyle(PrimaryStyle())
                        Button(action: soon) {
                            HStack(spacing: Space.s2) { Text("Sync with an account"); Badge(text: "Soon", plain: true) }
                        }
                        .buttonStyle(SecondaryStyle())
                    }
                    .padding(.top, Space.s6)
                    Text("Local mode keeps everything on this device.").type(.t14).foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center).padding(.top, Space.s2)
                }
                .pad()
                .frame(maxWidth: Size.narrow)
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical, alignment: .center) { length, _ in length }
            }
            .scrollBounceBehavior(.basedOnSize)
            AskLayer()
        }
        .background(Backdrop())
        .transaction { $0.disablesAnimations = true }
    }

    private func soon() {
        model.confirm = Confirm(title: "Sync is coming soon",
                                message: "Signing in with your Track account arrives in an upcoming build. Start locally now and turn on sync later; nothing is lost.",
                                label: "Continue locally") { model.choose(.local) }
    }
}
