import SwiftUI
import TrackCore

/// Settings, a sheet like the website's: workout preferences, where your data lives, and the version. Choices tick
/// with a selection haptic.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let settings = model.training.settings
        NavigationStack {
            List {
                Section {
                    Picker("Weight unit", selection: binding(\.unit)) {
                        Text("Kilograms (kg)").tag(TrackCore.Settings.Unit.kg)
                        Text("Pounds (lb)").tag(TrackCore.Settings.Unit.lb)
                    }
                    .glassRow()
                    Stepper("Weekly goal: \(count(settings.weeklyGoal, "day"))", value: binding(\.weeklyGoal), in: 1...7).glassRow()
                    Picker("Log sets", selection: Binding(get: { settings.logSets ?? .auto }, set: { value in model.update { $0.settings.logSets = value } })) {
                        Text("Automatically").tag(TrackCore.Settings.LogSets.auto)
                        Text("With the ✓ only").tag(TrackCore.Settings.LogSets.manual)
                    }
                    .glassRow()
                    Stepper("Rest timer: \(String(format: "%d:%02d", settings.restSeconds / 60, settings.restSeconds % 60))",
                            value: binding(\.restSeconds), in: 15...600, step: 15).glassRow()
                } header: { Header(title: "Workouts") }
                Section {
                    ListRow(icon: model.mode == .sync ? "icloud" : "iphone",
                            title: model.mode == .sync ? "Synced with your account" : "Saved on this iPhone",
                            detail: "\(count(model.training.sessions.count, "workout")) · \(count(model.training.splits.count, "split"))") { EmptyView() }
                        .glassRow()
                    ListRow(icon: "arrow.triangle.2.circlepath.icloud", title: "Turn on sync", detail: "Arrives in an upcoming build") { EmptyView() }
                        .opacity(0.6).glassRow()
                } header: { Header(title: "Your data") }
                Section {
                    ListRow(mark: true, title: "Track for iPhone", detail: "Version \(Self.version)") { EmptyView() }.glassRow()
                } header: { Header(title: "About") }
            }
            .scrollContentBackground(.hidden)
            .background(Backdrop())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sensoryFeedback(.selection, trigger: settings)
        }
    }

    private func binding<Value>(_ path: WritableKeyPath<TrackCore.Settings, Value>) -> Binding<Value> {
        Binding(get: { model.training.settings[keyPath: path] }, set: { value in model.update { $0.settings[keyPath: path] = value } })
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}
