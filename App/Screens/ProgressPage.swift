import SwiftUI
import TrackCore

/// Progress: this week's volume over the last eight weeks, the streak and level, then personal records.
struct ProgressPage: View {
    @Environment(AppModel.self) private var model
    @Binding var settingsOpen: Bool

    var body: some View {
        let training = model.training
        let now = nowMillis()
        let unit = training.settings.unit
        let week = training.sessions.weekVolumeChange(at: now)
        let volumes = training.sessions.weeklyVolumes(8, at: now)
        let level = Experience.progress(of: training.sessions)
        let records = training.sessions.latestRecords
        Page(title: "Progress", settingsOpen: $settingsOpen) {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Volume this week").font(.subheadline).foregroundStyle(Palette.muted)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(weight(week.volume, unit)).font(.largeTitle.weight(.bold)).monospacedDigit()
                                Text(unit.rawValue).font(.subheadline).foregroundStyle(Palette.muted)
                            }
                            .foregroundStyle(Palette.text)
                        }
                        Spacer()
                        if let change = week.change { Chip(text: "\(change >= 0 ? "▲" : "▼") \(abs(change))% vs last week", accent: change >= 0) }
                    }
                    WeekBars(volumes: volumes)
                    HStack { Text("8 weeks ago"); Spacer(); Text("This week") }.font(.caption).foregroundStyle(Palette.muted)
                }
                .padding(20).glass().bareRow()
            }
            Section {
                HStack(spacing: 10) {
                    tile(icon: "flame", value: "\(training.sessions.weeklyStreak(at: now))", label: "Week streak")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) { Image(systemName: "rosette"); Text("Lv \(level.level)").monospacedDigit() }
                            .font(.title3.weight(.bold)).foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(level.current)/\(level.required) XP").font(.subheadline).foregroundStyle(Palette.muted).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.8)
                        ProgressView(value: Double(level.current), total: Double(level.required)).tint(Palette.primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading).padding(14).glass()
                    tile(icon: "medal", value: "\(training.sessions.questAwards.count)/\(Quest.all.count)", label: "Achievements")
                }
                .bareRow()
            }
            Section {
                if records.isEmpty {
                    Text("Beat a weight or rep count you’ve logged before and it shows up here.")
                        .font(.subheadline).foregroundStyle(Palette.muted).glassRow()
                }
                ForEach(records.prefix(20), id: \.after.exercise) { record in
                    let after = record.after
                    ListRow(icon: "trophy", title: after.exercise,
                            detail: "\(TrainingSet.display(kg: after.kg, unit: unit)) \(unit.rawValue) × \(after.reps) · \(Date(timeIntervalSince1970: Double(after.date) / 1000).formatted(.dateTime.month(.abbreviated).day()))") {
                        Text(record.kind == .weight ? "+\(TrainingSet.display(kg: after.kg - record.before.kg, unit: unit)) \(unit.rawValue)" : "+\(after.reps - record.before.reps) reps")
                            .font(.headline).monospacedDigit().foregroundStyle(Palette.accent)
                    }
                    .glassRow()
                }
            } header: { Header(title: "Personal records") }
        }
    }

    private func tile(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(icon == "flame" ? Palette.streak : Palette.text)
                Text(value).monospacedDigit().foregroundStyle(Palette.text)
            }
            .font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading).padding(14).glass()
    }
}

/// Eight weekly bars, this week's in the accent and the rest glass, growing in smoothly.
private struct WeekBars: View {
    let volumes: [Double]
    @State private var grown = false

    var body: some View {
        let top = max(volumes.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(volumes.enumerated()), id: \.offset) { index, volume in
                let last = index == volumes.count - 1
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(last ? Palette.primary : Palette.control)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.rim.opacity(0.4), lineWidth: 1))
                    .frame(height: max(12, 140 * (grown ? volume / top : 0)))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 140, alignment: .bottom)
        .onAppear { withAnimation(.smooth(duration: 0.7)) { grown = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly volume, last eight weeks")
    }
}
