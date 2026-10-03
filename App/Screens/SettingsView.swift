import SwiftUI
import TrackCore

/// Settings, as the website's sheet: "Settings" with ✕, the Training · Data · Account · About tabs, and rows of a
/// label with its glass select. Every choice ticks.
struct SettingsView: View {
    enum Tab: String, CaseIterable { case training = "Training", data = "Data", account = "Account", about = "About" }
    @Environment(\.dismiss) private var dismiss
    @State private var tab = Tab.training
    @Namespace private var highlight

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 0) {
                        ForEach(Tab.allCases, id: \.self) { item in
                            Button { withAnimation(.smooth(duration: 0.3)) { tab = item } } label: {
                                Text(item.rawValue).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(tab == item ? Palette.accent : Palette.muted)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background {
                                        if tab == item {
                                            Capsule().fill(Palette.control).glass(radius: 20, fill: .clear, lifted: false)
                                                .matchedGeometryEffect(id: "tab", in: highlight)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .glass(radius: 24, fill: Palette.input, lifted: false)
                    .sensoryFeedback(.selection, trigger: tab)
                    switch tab {
                    case .training: TrainingSettings()
                    case .data: DataSettings()
                    case .account: AccountSettings()
                    case .about: AboutSettings()
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Backdrop())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Palette.text) }.accessibilityLabel("Close")
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

/// A setting: its name (and a line of help) with its control at the end.
struct SettingRow<Control: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.body).foregroundStyle(Palette.text)
                if let detail { Text(detail).font(.caption).foregroundStyle(Palette.muted) }
            }
            Spacer(minLength: 8)
            control
        }
        .frame(minHeight: 44)
    }
}

private struct TrainingSettings: View {
    @Environment(AppModel.self) private var model
    private static let rests = [30, 60, 90, 120, 180, 300]
    /// A rest that isn't one of the presets is typed in seconds (15–600), as on the website.
    @State private var custom = false
    @State private var draft = ""
    @State private var error: String?
    @FocusState private var typing: Bool

    private func saveCustom() {
        guard let seconds = Int(draft), (15...600).contains(seconds) else { error = "Enter 15–600 seconds."; return }
        error = nil
        model.update { $0.settings.restSeconds = seconds }
    }

    var body: some View {
        let settings = model.training.settings
        GlassList {
            SettingRow(label: "Weight unit") {
                GlassMenu(selection: settings.unit, options: [(.kg, "kg"), (.lb, "lb")]) { value in model.update { $0.settings.unit = value } }
            }
            SettingRow(label: "Weekly goal") {
                GlassMenu(selection: settings.weeklyGoal, options: (1...7).map { ($0, count($0, "day")) }) { value in
                    model.update { $0.settings.weeklyGoal = value }
                }
            }
            SettingRow(label: "Log sets", detail: settings.logSets == .manual ? "Only the ✓ logs a set" : "Changing a number logs the set") {
                GlassMenu(selection: settings.logSets ?? .auto, options: [(.auto, "Auto"), (.manual, "Manual")]) { value in
                    model.update { $0.settings.logSets = value }
                }
            }
            SettingRow(label: "Rest timer") {
                GlassMenu(selection: custom ? -1 : settings.restSeconds,
                          options: Self.rests.map { ($0, String(format: "%d:%02d", $0 / 60, $0 % 60)) } + [(-1, "Custom")]) { value in
                    if value == -1 { custom = true; draft = String(settings.restSeconds) } else { custom = false; model.update { $0.settings.restSeconds = value } }
                }
            }
            if custom {
                VStack(alignment: .leading, spacing: 6) {
                    SettingRow(label: "Duration") {
                        HStack(spacing: 6) {
                            TextField("90", text: $draft).keyboardType(.numberPad).multilineTextAlignment(.center)
                                .font(.body.weight(.semibold)).monospacedDigit().frame(width: 72, height: 40)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.input))
                                .focused($typing).onSubmit(saveCustom)
                                .onChange(of: typing) { _, now in if !now { saveCustom() } }
                            Text("sec").foregroundStyle(Palette.muted)
                        }
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(Palette.danger) }
                }
            }
            SettingRow(label: "Appearance") {
                GlassMenu(selection: settings.theme == .liquid ? .system : settings.theme,
                          options: [(.system, "System"), (.light, "Light"), (.dark, "Dark")]) { value in model.update { $0.settings.theme = value } }
            }
        }
        .onAppear { if !Self.rests.contains(settings.restSeconds) { custom = true; draft = String(settings.restSeconds) } }
        .animation(.smooth(duration: 0.3), value: custom)
    }
}

private struct DataSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text("Your data").font(.headline).foregroundStyle(Palette.text)
        Text("Your workouts are saved on this iPhone only. Export a backup before deleting Track or moving to another phone.")
            .font(.subheadline).foregroundStyle(Palette.muted)
        GlassList {
            ListRow(icon: model.mode == .sync ? "icloud" : "iphone", title: "Sync status",
                    detail: "Saved on this iPhone · \(count(model.training.sessions.count, "workout"))") { EmptyView() }
            BackupSection()
        }
    }
}

private struct AccountSettings: View {
    var body: some View {
        Text("Sync with your account").font(.headline).foregroundStyle(Palette.text)
        Text("Signing in to keep your iPhone and the website in step arrives in an upcoming build. Your workouts stay safe on this iPhone until then.")
            .font(.subheadline).foregroundStyle(Palette.muted)
        GlassList {
            ListRow(icon: "arrow.triangle.2.circlepath.icloud", title: "Turn on sync", detail: "Coming soon") { EmptyView() }
                .opacity(0.6)
        }
    }
}

private struct AboutSettings: View {
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
            Link(destination: URL(string: "https://trackk.pages.dev/privacy")!) {
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
