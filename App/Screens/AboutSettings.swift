import SafariServices
import SwiftUI

/// Settings → About's rows: where to report a problem (tap to copy the name), the privacy page and the version.
struct AboutSettings: View {
    @State private var copied = false
    @State private var privacy = false
    private static let discord = "n1ghthawq"

    var body: some View {
        RowCard {
            Button {
                UIPasteboard.general.string = Self.discord
                copied = true
            } label: { Row(title: "Found a problem?", value: copied ? "Copied" : Self.discord) }
                .buttonStyle(RowPressStyle())
                .accessibilityLabel(copied ? "Discord username copied" : "Copy Discord username \(Self.discord)")
                .sensoryFeedback(.success, trigger: copied) { _, now in now }
                .task(id: copied) { if copied { try? await Task.sleep(for: .seconds(2)); copied = false } }
            // Inside Track, as iOS apps show a web page, rather than switching to Safari.
            Button { privacy = true } label: { Row(title: "Privacy", value: "", chevron: true) }
                .buttonStyle(RowPressStyle())
                .sheet(isPresented: $privacy) { SafariView(url: URL(string: "https://trackk.pages.dev/privacy#iphone")!).ignoresSafeArea() }
            Row(title: "Version", value: Self.version)
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
