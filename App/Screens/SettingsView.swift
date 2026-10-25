import SwiftUI
import TrackCore
import UserNotifications

/// Settings on one page, as the PWA's: "Settings" with Done, then Training, Data, Account and About, each a card of rows.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var resting: Resting?
    /// Notifications turned off for Track: the rest timer can't alert with the phone locked.
    @State private var alertsOff = false

    enum Resting: String, Identifiable { case list, custom; var id: String { rawValue } }

    var body: some View {
        let settings = model.training.settings
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Settings").type(.t32).foregroundStyle(Palette.text)
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(SecondaryButtonStyle(hug: true))
                }
                section("Training") {
                    Row(title: "Weight unit") {
                        Seg(label: "Weight unit", options: [(value: TrackCore.Settings.Unit.kg, text: "kg"), (value: .lb, text: "lb")],
                            value: Binding(get: { settings.unit }, set: { unit in model.update { $0.settings.unit = unit } }), compact: true)
                    }
                    Button { resting = .list } label: { Row(title: "Rest timer", value: "\(restText(settings.restSeconds)) min", chevron: true) }
                        .buttonStyle(RowPressStyle())
                    Row(title: "Log sets") {
                        Seg(label: "Log sets", options: [(value: TrackCore.Settings.LogSets.auto, text: "Auto"), (value: .manual, text: "Tap")],
                            value: Binding(get: { settings.logSets ?? .auto }, set: { mode in model.update { $0.settings.logSets = mode } }), compact: true)
                    }
                    goal(settings.weeklyGoal)
                    if alertsOff {
                        Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                            Row(title: "Rest alerts are off", value: "Allow", chevron: true)
                        }
                    }
                }
                section("Data") {
                    Row(title: "Cloud sync", value: "On this device only")
                    BackupSection()
                }
                section("Account") {
                    Row(title: "Signed in", value: "Local only")
                    Button { model.leaveLocal() } label: { Row(title: "Leave local mode") { EmptyView() } }.buttonStyle(RowPressStyle())
                }
                Text("About").type(.t14).foregroundStyle(Palette.muted).padding(.top, Space.s6)
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("A personal project").type(.t16).foregroundStyle(Palette.text)
                    Text("Built with AI for my own training. Expect rough edges.").type(.t14).foregroundStyle(Palette.muted)
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .raised()
                .padding(.top, Space.s2)
                AboutSettings().padding(.top, Space.s3)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s6)
            .frame(maxWidth: Measure.page)
            .frame(maxWidth: .infinity)
        }
        .background(Backdrop())
        .presentationDragIndicator(.visible)
        .sheet(item: $resting) { kind in
            switch kind {
            case .list: RestList { resting = .custom }
            case .custom: CustomRest(seconds: settings.restSeconds)
            }
        }
        .task { alertsOff = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied }
    }

    private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).type(.t14).foregroundStyle(Palette.muted)
            RowCard(content: rows)
        }
        .padding(.top, title == "Training" ? Space.s4 : Space.s6)
    }

    /// Weekly goal: the days a week, one fewer or one more.
    private func goal(_ days: Int) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Weekly goal").type(.t16).foregroundStyle(Palette.text).lineLimit(1)
                Text("\(count(days, "day")) a week").type(.t14).monospacedDigit().foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            RoundButton(icon: "minus", label: "One day fewer") { model.update { $0.settings.weeklyGoal -= 1 } }
                .disabled(days <= Limits.weeklyGoal.lowerBound)
            RoundButton(icon: "plus", label: "One day more") { model.update { $0.settings.weeklyGoal += 1 } }
                .disabled(days >= Limits.weeklyGoal.upperBound)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(minHeight: Size.row)
        .sensoryFeedback(.selection, trigger: days)
    }
}

/// "1:30"
func restText(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

/// The rest presets, and Custom for any other time (checked once it's set).
private struct RestList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let custom: () -> Void
    private static let presets = [60, 90, 120, 150, 180, 240, 300]

    var body: some View {
        let current = model.training.settings.restSeconds
        SheetFrame(title: "Rest timer") {
            RowCard {
                ForEach(Self.presets, id: \.self) { seconds in
                    Button { model.update { $0.settings.restSeconds = seconds }; dismiss() } label: {
                        Row(title: "\(restText(seconds)) min") { if seconds == current { Check() } }
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityAddTraits(seconds == current ? .isSelected : [])
                }
                Button(action: custom) {
                    Row(title: "Custom") {
                        if Self.presets.contains(current) { RowValue(text: "", chevron: true) } else { RowValue(text: "\(restText(current)) min"); Check() }
                    }
                }
                .buttonStyle(RowPressStyle())
            }
            .padding(.top, Space.s3)
        }
    }
}

/// The green tick of a chosen row.
struct Check: View {
    var body: some View {
        Image(systemName: "checkmark").font(.system(size: IconSize.medium, weight: .semibold)).foregroundStyle(Palette.accent)
    }
}

/// Any rest time in the allowed range, as minutes and seconds.
private struct CustomRest: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let seconds: Int
    @State private var minutes = ""
    @State private var secs = ""

    var body: some View {
        let whole = { (text: String) -> Int? in text.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : Int(text.trimmingCharacters(in: .whitespaces)) }
        let total = whole(minutes).flatMap { m in whole(secs).flatMap { $0 < 60 ? m * 60 + $0 : nil } }
        let valid = total.map(Limits.restSeconds.contains) == true
        let save = { if let total, valid { model.update { $0.settings.restSeconds = total }; dismiss() } }
        SheetFrame(title: "Custom rest", closeLabel: "Cancel") {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(alignment: .top, spacing: Space.s3) {
                    field("Minutes", $minutes, save)
                    field("Seconds", $secs, save)
                }
                if !valid {
                    Text("Enter \(restText(Limits.restSeconds.lowerBound)) to \(restText(Limits.restSeconds.upperBound)) min.")
                        .type(.t14).foregroundStyle(Palette.danger)
                }
                Button("Save", action: save).buttonStyle(PrimaryButtonStyle()).disabled(!valid)
            }
            .padding(.top, Space.s3)
        }
        .onAppear { minutes = String(seconds / 60); secs = String(seconds % 60) }
    }

    private func field(_ label: String, _ text: Binding<String>, _ save: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).type(.t14).foregroundStyle(Palette.muted)
            Field(placeholder: "0", text: text, label: label, limit: 2, keyboard: .numberPad, submit: save)
        }
    }
}
