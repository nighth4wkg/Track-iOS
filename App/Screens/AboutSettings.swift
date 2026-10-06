import SwiftUI

/// Settings → About: who made Track, where to report a problem, the privacy page and the version.
struct AboutSettings: View {
    @State private var copied = false
    private static let discord = "n1ghthawq"

    var body: some View {
        Text("A personal project").font(.headline).foregroundStyle(Palette.text)
        Text("Track is purely vibe-coded: built with AI assistance and made for my own personal training. It’s shared as-is, so there may be rough edges.")
            .font(.subheadline).foregroundStyle(Palette.muted)
        GlassList {
            Button {
                UIPasteboard.general.string = Self.discord
                copied = true
            } label: {
                ListRow(icon: "bubble.left", title: "Found a problem?", detail: "Message \(Self.discord) on Discord") {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").foregroundStyle(copied ? Palette.accent : Palette.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .sensoryFeedback(.success, trigger: copied) { _, now in now }
            Link(destination: URL(string: "https://trackk.pages.dev/privacy#iphone")!) {
                ListRow(icon: "shield", title: "Privacy", detail: "What Track stores and how to delete it") {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                }
            }
            ListRow(mark: true, title: "Track for iPhone", detail: "Version \(Self.version)") { EmptyView() }
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}
