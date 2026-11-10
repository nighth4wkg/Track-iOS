import CoreTransferable
import SwiftUI
import TrackCore
import UniformTypeIdentifiers
import UserNotifications

/// Settings (the PWA's): "Settings" with Done, then a bar of its sections (Training, Data, Account, About) drawn as
/// the nav pill, and the chosen one's cards.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    /// Notifications turned off for Track: the rest timer can't alert with the phone locked.
    @State private var alertsOff = false
    @State private var importing = false
    @State private var restored = 0
    @State private var copied = false
    @State private var part = Part.training
    @AppStorage(Motion.speedKey) private var motion = Motion.defaultSpeed
    static let contact = "n1ghthawq"
    /// How long "Copied" shows before the row reads as before (the PWA's COPIED_MS).
    private static let copiedFor = Duration.seconds(2)

    var body: some View {
        let settings = model.training.settings
        DeepPage {
            TitleBar(title: "Settings")
            PillTabs(label: "Settings sections", items: Self.parts, chosen: part, width: .infinity) { part = $0 }
                .padding(.top, Space.s4)
            Group {
                switch part {
                case .training: training(settings)
                case .data: data
                case .account: account
                case .about: about
                }
            }
            .padding(.top, Space.s6)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in restore(result) }
        .sensoryFeedback(.success, trigger: restored)
        .task { alertsOff = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied }
    }

    private func training(_ settings: TrackCore.Settings) -> some View {
        RowCard {
            Row(title: "Weight unit") {
                Seg(label: "Weight unit", options: [(value: TrackCore.Settings.Unit.kg, text: "kg"), (value: .lb, text: "lb")],
                    value: Binding(get: { settings.unit }, set: { unit in model.update { $0.settings.unit = unit } }), compact: true)
            }
            Button { model.present(RestList()) } label: { Row(title: "Rest timer", value: "\(clock(settings.restSeconds)) min", chevron: true) }
                .buttonStyle(RowStyle())
                .readies { model.ready(RestList()) }
            Row(title: "Log sets") {
                Seg(label: "Log sets", options: [(value: TrackCore.Settings.LogSets.auto, text: "Auto"), (value: .manual, text: "Tap")],
                    value: Binding(get: { settings.logSets ?? .auto }, set: { mode in model.update { $0.settings.logSets = mode } }), compact: true)
            }
            goal(settings.weeklyGoal)
            if alertsOff, let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) { Row(title: "Rest alerts are off", value: "Allow", chevron: true) }.buttonStyle(RowStyle())
            }
        }
    }

    private var data: some View {
        RowCard {
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
    }

    private var account: some View {
        RowCard {
            Row(title: "Signed in", value: "Local only")
            // Asks first, in red, as every way out does (the PWA's leave()).
            Button {
                model.confirm = Confirm(title: "Leave local mode?", message: "Workouts stay on this device for when you come back.",
                                        label: "Leave local mode", destructive: true) { model.leaveLocal() }
            } label: { Row(title: "Leave local mode") { EmptyView() } }
                .buttonStyle(RowStyle())
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("A personal project").type(.t16).foregroundStyle(Palette.text)
                Text("Built with AI for my own training. Expect rough edges.").type(.t14).foregroundStyle(Palette.muted)
            }
            .pad()
            .frame(maxWidth: .infinity, alignment: .leading)
            .raised()
            RowCard {
                Button {
                    UIPasteboard.general.string = Self.contact
                    copied = true
                } label: {
                    // Where to write, not only a name (owner: say it's Discord).
                    HStack(spacing: Space.s3) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Found a problem?").type(.t16).foregroundStyle(Palette.text)
                            Text("Message \(Self.contact) on Discord").type(.t14).foregroundStyle(Palette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        RowValue(text: copied ? "Copied" : "Copy")
                    }
                    .padding(Space.s4)
                    .frame(minHeight: Size.row)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowStyle())
                .accessibilityLabel("Found a problem? " + (copied ? "Discord username copied" : "Copy Discord username \(Self.contact)"))
                .sensoryFeedback(.success, trigger: copied) { _, now in now }
                .task(id: copied) { if copied { try? await Task.sleep(for: Self.copiedFor); copied = false } }
                Button { model.present(PrivacyPage()) } label: { Row(title: "Privacy", value: "", chevron: true) }
                    .buttonStyle(RowStyle())
                    .readies { model.ready(PrivacyPage()) }
                Button { model.present(MotionList()) } label: {
                    Row(title: "Motion", value: Motion.speeds.first { $0.scale == Motion.picked(motion) }?.name ?? "", chevron: true)
                }
                .buttonStyle(RowStyle())
                .readies { model.ready(MotionList()) }
                Row(title: "Version", value: Self.version)
                    // Hidden, for checking motion on this iPhone: every motion run by itself on a copy that's never saved.
                    .onLongPressGesture(minimumDuration: Self.holdForCheck) { MotionCheck.run(model) }
                    .accessibilityAction(named: "Motion check") { MotionCheck.run(model) }
            }
        }
    }

    /// The page's sections, one shown at a time under a bar drawn as the nav pill (the PWA's PARTS).
    enum Part { case training, data, account, about }
    private static var parts: [(value: Part, text: String, icon: (Bool) -> AnyView)] {
        [(value: .training, text: "Training", icon: { (_: Bool) -> AnyView in AnyView(TrackMark(size: IconSize.logo)) }),
         (value: .data, text: "Data", icon: { (on: Bool) -> AnyView in AnyView(Icon.data.image(IconSize.logo, bold: on)) }),
         (value: .account, text: "Account", icon: { (on: Bool) -> AnyView in AnyView(Icon.account.image(IconSize.logo, bold: on)) }),
         (value: .about, text: "About", icon: { (on: Bool) -> AnyView in AnyView(Icon.about.image(IconSize.logo, bold: on)) })]
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

    /// How long Version is held to start the motion check.
    private static let holdForCheck = 1.0

    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}

/// What the iPhone app keeps and where it goes, in Track's own sheet (the website's page is the web app's own).
struct PrivacyPage: View {
    private static let sections = [
        (title: "What Track keeps", body: "The workouts, splits, settings and bodyweight you enter. There is no account: no name, email or password."),
        (title: "Where it goes", body: "Nowhere: it stays on this iPhone and in its iCloud or computer backups. It is never sold, shared for advertising, or used to train AI."),
        (title: "Your control", body: "Export a full backup any time in Settings › Data. Deleting the app deletes its data."),
        (title: "Questions", body: "Message \(SettingsScreen.contact) on Discord."),
    ]

    var body: some View {
        SheetFrame(title: "Privacy", subtitle: "Your data, plainly") {
            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(Self.sections.indices, id: \.self) { at in
                    let section = Self.sections[at]
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text(section.title).type(.t16).foregroundStyle(Palette.text).accessibilityAddTraits(.isHeader)
                        Text(section.body).type(.t14).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    .pad()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .raised()
                }
            }
            .padding(.top, Space.s3)
        }
    }
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
struct RestList: View {
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
                .readies { model.ready(CustomRest(seconds: current)) }
                .accessibilityAddTraits(Self.presets.contains(current) ? [] : .isSelected)
            }
            .padding(.top, Space.s3)
        }
    }

    private var tick: some View { Icon.check.image(IconSize.medium).foregroundStyle(Palette.accent) }
}

/// How fast the app moves: Default, or a step slower or faster (Motion.speeds), as the rest presets are picked.
struct MotionList: View {
    @Environment(\.closeSheet) private var close
    @AppStorage(Motion.speedKey) private var motion = Motion.defaultSpeed

    var body: some View {
        SheetFrame(title: "Motion", subtitle: "How fast Track moves") {
            RowCard {
                ForEach(Motion.speeds.indices, id: \.self) { at in
                    let speed = Motion.speeds[at]
                    Button { motion = speed.scale; close() } label: {
                        Row(title: speed.name) { if speed.scale == Motion.picked(motion) { Icon.check.image(IconSize.medium).foregroundStyle(Palette.accent) } }
                    }
                    .buttonStyle(RowStyle())
                    .accessibilityAddTraits(speed.scale == Motion.picked(motion) ? .isSelected : [])
                }
            }
            .padding(.top, Space.s3)
        }
    }
}

/// Any rest time in the allowed range, as minutes and seconds.
struct CustomRest: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeSheet) private var close
    /// Filled from the first frame (SetRow's init says why).
    @State private var minutes: String
    @State private var secs: String
    init(seconds: Int) { (_minutes, _secs) = (State(initialValue: String(seconds / 60)), State(initialValue: String(seconds % 60))) }
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
