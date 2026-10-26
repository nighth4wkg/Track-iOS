import CoreTransferable
import SafariServices
import SwiftUI
import TrackCore
import UniformTypeIdentifiers
import UserNotifications

/// Settings on one page (the PWA's): "Settings" with Done, then Training, Data, Account and About, each a card of rows.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    /// Notifications turned off for Track: the rest timer can't alert with the phone locked.
    @State private var alertsOff = false
    @State private var importing = false
    @State private var restored = 0
    @State private var copied = false
    private static let contact = "n1ghthawq"
    private static let privacy = URL(string: "https://trackk.pages.dev/privacy#iphone")

    var body: some View {
        let settings = model.training.settings
        DeepPage {
            HStack(spacing: Space.s3) {
                Text("Settings").type(.t32).foregroundStyle(Palette.text).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Button("Done") { model.back() }.buttonStyle(SecondaryStyle(hug: true))
            }
            .frame(minHeight: Size.control)
            section("Training") {
                Row(title: "Weight unit") {
                    Seg(label: "Weight unit", options: [(value: TrackCore.Settings.Unit.kg, text: "kg"), (value: .lb, text: "lb")],
                        value: Binding(get: { settings.unit }, set: { unit in model.update { $0.settings.unit = unit } }), compact: true)
                }
                Button { model.present(RestList()) } label: { Row(title: "Rest timer", value: "\(clock(settings.restSeconds)) min", chevron: true) }
                    .buttonStyle(RowStyle())
                Row(title: "Log sets") {
                    Seg(label: "Log sets", options: [(value: TrackCore.Settings.LogSets.auto, text: "Auto"), (value: .manual, text: "Tap")],
                        value: Binding(get: { settings.logSets ?? .auto }, set: { mode in model.update { $0.settings.logSets = mode } }), compact: true)
                }
                goal(settings.weeklyGoal)
                if alertsOff, let url = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: url) { Row(title: "Rest alerts are off", value: "Allow", chevron: true) }.buttonStyle(RowStyle())
                }
            }
            section("Data") {
                Row(title: "Cloud sync", value: "On this device only")
                // While the saved copy can't be read, the export is that file as it is (the website's recovery
                // export), not the empty app.
                if let unreadable = model.unreadableFile {
                    ShareLink(item: unreadable) { Row(title: "Export unreadable data", value: "The copy Track couldn’t read") }
                        .buttonStyle(RowStyle())
                } else {
                    ShareLink(item: BackupFile(training: model.training), preview: SharePreview("Track backup")) {
                        Row(title: "Export backup", value: "JSON file")
                    }
                    .buttonStyle(RowStyle())
                }
                Button { importing = true } label: { Row(title: "Restore backup", value: "Replaces your data") }.buttonStyle(RowStyle())
            }
            section("Account") {
                Row(title: "Signed in", value: "Local only")
                Button { model.leaveLocal() } label: { Row(title: "Leave local mode") { EmptyView() } }.buttonStyle(RowStyle())
            }
            section("About") {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("A personal project").type(.t16).foregroundStyle(Palette.text)
                    Text("Built with AI for my own training. Expect rough edges.").type(.t14).foregroundStyle(Palette.muted)
                }
                .pad()
                .frame(maxWidth: .infinity, alignment: .leading)
                .raised()
            }
            RowCard {
                Button {
                    UIPasteboard.general.string = Self.contact
                    copied = true
                } label: { Row(title: "Found a problem?", value: copied ? "Copied" : Self.contact) }
                    .buttonStyle(RowStyle())
                    .accessibilityLabel("Found a problem? " + (copied ? "Discord username copied" : "Copy Discord username \(Self.contact)"))
                    .sensoryFeedback(.success, trigger: copied) { _, now in now }
                    .task(id: copied) { if copied { try? await Task.sleep(for: .seconds(2)); copied = false } }
                // Inside Track, as iOS apps show a web page, rather than switching to Safari.
                Button { if let url = Self.privacy { showWebPage(url) } } label: { Row(title: "Privacy", value: "", chevron: true) }
                    .buttonStyle(RowStyle())
                Row(title: "Version", value: Self.version)
            }
            .padding(.top, Space.s3)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in restore(result) }
        .sensoryFeedback(.success, trigger: restored)
        .task { alertsOff = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied }
    }

    /// A section's label over its card. The About card is a plain card, not rows.
    private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).type(.t14).foregroundStyle(Palette.muted).accessibilityAddTraits(.isHeader)
            if title == "About" { rows() } else { RowCard(content: rows) }
        }
        .padding(.top, title == "Training" ? Space.s4 : Space.s6)
    }

    /// Weekly goal: the days a week, one fewer or one more.
    private func goal(_ days: Int) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Weekly goal").type(.t16).foregroundStyle(Palette.text)
                Text("\(count(days, "day")) a week").type(.t14).monospacedDigit().foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RoundButton(icon: .minus, label: "One day fewer", size: IconSize.medium) { model.update { $0.settings.weeklyGoal -= 1 } }
                .disabled(days <= Limits.weeklyGoal.lowerBound)
            RoundButton(icon: .plus, label: "One day more", size: IconSize.medium) { model.update { $0.settings.weeklyGoal += 1 } }
                .disabled(days >= Limits.weeklyGoal.upperBound)
        }
        .pad()
        .frame(minHeight: Size.row)
        .sensoryFeedback(.selection, trigger: days)
    }

    private func restore(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let backup = try? TrainingFile.decode(data), backup.isValid else {
            model.problem("Not a Track backup file.")
            return
        }
        model.confirm = Confirm(title: "Restore this backup?",
                                message: "It has \(count(backup.sessions.count, "workout")) and \(count(backup.splits.count, "split")), and replaces everything in Track now.",
                                label: "Replace my data", destructive: true) {
            model.restore(backup)
            restored += 1
            model.show("Backup restored")
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}

/// A web page over Track, as iOS apps show one (Safari's own view).
@MainActor private func showWebPage(_ url: URL) {
    let root = keyWindow?.rootViewController
    var top = root
    while let shown = top?.presentedViewController { top = shown }
    top?.present(SFSafariViewController(url: url), animated: true)
}

/// The training data as a backup file: the same JSON the website exports and restores ("track-backup-<day>.json").
struct BackupFile: Transferable {
    let training: Training

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { backup in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("track-backup-\(dayKey(nowMillis())).json")
            try TrainingFile.encode(backup.training).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// The rest presets, and Custom for any other time (checked once it's set).
private struct RestList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeSheet) private var close
    private static let presets = [60, 90, 120, 150, 180, 240, 300]

    var body: some View {
        let current = model.training.settings.restSeconds
        SheetFrame(title: "Rest timer") {
            RowCard {
                ForEach(Self.presets, id: \.self) { seconds in
                    Button { model.update { $0.settings.restSeconds = seconds }; close() } label: {
                        Row(title: "\(clock(seconds)) min") { if seconds == current { tick } }
                    }
                    .buttonStyle(RowStyle())
                    .accessibilityAddTraits(seconds == current ? .isSelected : [])
                }
                Button { close(); model.present(CustomRest(seconds: current)) } label: {
                    Row(title: "Custom") {
                        if Self.presets.contains(current) { RowValue(text: "", chevron: true) } else { RowValue(text: "\(clock(current)) min"); tick }
                    }
                }
                .buttonStyle(RowStyle())
                .accessibilityAddTraits(Self.presets.contains(current) ? [] : .isSelected)
            }
            .padding(.top, Space.s3)
        }
    }

    private var tick: some View { Icon.check.image(IconSize.medium).foregroundStyle(Palette.accent) }
}

/// Any rest time in the allowed range, as minutes and seconds.
private struct CustomRest: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeSheet) private var close
    let seconds: Int
    @State private var minutes = ""
    @State private var secs = ""
    /// Two digits each, as the PWA's maxlength.
    private static let digits = 2

    var body: some View {
        let whole = { (text: String) -> Int? in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? 0 : Int(trimmed)
        }
        let total = whole(minutes).flatMap { m in whole(secs).flatMap { $0 < 60 ? m * 60 + $0 : nil } }
        let valid = total.map(Limits.restSeconds.contains) == true
        let save = { if let total, valid { model.update { $0.settings.restSeconds = total }; close() } }
        SheetFrame(title: "Custom rest", closeLabel: "Cancel") {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(alignment: .top, spacing: Space.s3) {
                    field("Minutes", $minutes, save)
                    field("Seconds", $secs, save)
                }
                if !valid {
                    Text("Enter \(clock(Limits.restSeconds.lowerBound)) to \(clock(Limits.restSeconds.upperBound)) min.")
                        .type(.t14).foregroundStyle(Palette.danger)
                }
                Button("Save", action: save).buttonStyle(PrimaryStyle()).disabled(!valid)
            }
            .padding(.top, Space.s3)
        }
        .onAppear { minutes = String(seconds / 60); secs = String(seconds % 60) }
    }

    private func field(_ label: String, _ text: Binding<String>, _ save: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).type(.t14).foregroundStyle(Palette.muted)
            Field(placeholder: "0", text: text, label: label, keyboard: .numberPad, submit: save)
                .onChange(of: text.wrappedValue) { _, value in if value.count > Self.digits { text.wrappedValue = String(value.prefix(Self.digits)) } }
        }
        .frame(maxWidth: .infinity)
    }
}
