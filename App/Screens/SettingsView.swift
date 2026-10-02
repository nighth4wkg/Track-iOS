import SwiftUI
import TrackCore

/// Settings, as a sheet like the website's. For now: where your data lives and the app version.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(title: "Your data")
                    GroupedList {
                        ListRow(icon: model.mode == .sync ? "icloud" : "iphone",
                                title: model.mode == .sync ? "Synced with your account" : "Saved on this iPhone",
                                detail: "\(model.training.sessions.count) workouts · \(model.training.splits.count) splits") { EmptyView() }
                        ListRow(icon: "arrow.triangle.2.circlepath.icloud", title: "Turn on sync",
                                detail: "Arrives in an upcoming build") { EmptyView() }
                            .opacity(0.6)
                    }
                    SectionTitle(title: "About")
                    GroupedList {
                        ListRow(icon: "info.circle", title: "Track for iPhone", detail: "Version \(Self.version)") { EmptyView() }
                    }
                }
                .padding(16)
            }
            .background(Backdrop())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}
