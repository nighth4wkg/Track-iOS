import SwiftUI
import TrackCore

/// Progress, as on the website: volume by day, week or month (D W M; Home keeps just the week), then three tiles that each open where
/// their number comes from (the streak goes Home, the level explains XP, achievements lists all 24), then each
/// exercise's latest personal record (a row opens its workout).
struct ProgressPage: View {
    @Environment(AppModel.self) private var model
    @Binding var settingsOpen: Bool
    @State private var xpHelp = false
    @State private var quests = false
    @AppStorage("track.volumePeriod") private var period = Period.week

    var body: some View {
        let training = model.training
        let now = nowMillis()
        let unit = training.settings.unit
        let change = training.sessions.volumeChange(per: period, at: now)
        let records = Array(training.sessions.latestRecords.prefix(5))
        Page(title: "Progress", settingsOpen: $settingsOpen) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Volume \(period.now)").font(.subheadline).foregroundStyle(Palette.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(weight(change.volume, unit)).font(.largeTitle.weight(.bold)).monospacedDigit().contentTransition(.numericText())
                            Text(unit.rawValue).font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        .foregroundStyle(Palette.text)
                    }
                    Spacer()
                    Picker("Volume by", selection: $period.animation(.smooth(duration: 0.35))) {
                        ForEach(Period.allCases, id: \.self) { Text($0.rawValue).accessibilityLabel($0.name) }
                    }
                    .pickerStyle(.segmented).fixedSize()
                }
                if let change = change.change {
                    Chip(text: change == 0 ? "Same as \(period.last)" : "\(change > 0 ? "▲" : "▼") \(abs(change))% vs \(period.last)", accent: change > 0)
                }
                VolumeBars(volumes: training.sessions.volumes(period.bars, per: period, at: now), label: period.name)
                HStack { Text(period.first); Spacer(); Text(period.now.capitalized) }.font(.caption).foregroundStyle(Palette.muted)
            }
            .padding(20).glass()
            HStack(spacing: 10) {
                tile(icon: "flame", value: "\(training.sessions.weeklyStreak(at: now))", label: "Week streak") { model.tab = .home }
                LevelTile { xpHelp = true }
                tile(icon: "medal", value: "\(training.sessions.questAwards.count)/\(Quest.all.count)", label: "Achievements") { quests = true }
            }
            .fixedSize(horizontal: false, vertical: true)
            SectionHeading(title: "Personal records")
            if records.isEmpty {
                EmptyCard(icon: "chart.line.uptrend.xyaxis",
                          title: training.sessions.isEmpty ? "Your next workout starts the story" : "No records yet",
                          detail: training.sessions.isEmpty ? "Complete a workout to set your first baseline."
                              : "Beat a weight or rep count from an earlier workout to set one.")
                if training.sessions.isEmpty {
                    Button { model.tab = .home } label: { Label("Go to your splits", systemImage: "arrow.up.right").labelStyle(TrailingIcon()) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                GlassList {
                    ForEach(records, id: \.after.exercise) { record in
                        let after = record.after
                        Button { model.history = training.sessions.first { $0.id == after.sessionId } } label: {
                            ListRow(icon: "trophy", title: after.exercise,
                                    detail: "\(TrainingSet.display(kg: after.kg, unit: unit)) \(unit.rawValue) × \(after.reps) · \(Date(timeIntervalSince1970: Double(after.date) / 1000).formatted(.dateTime.month(.abbreviated).day()))") {
                                Text(record.kind == .weight ? "+\(TrainingSet.display(kg: after.kg - record.before.kg, unit: unit)) \(unit.rawValue)"
                                     : "+\(count(after.reps - record.before.reps, "rep"))")
                                    .font(.headline).monospacedDigit().foregroundStyle(Palette.accent)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
        .sheet(isPresented: $xpHelp) { XpHelp().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $quests) { QuestList().trackOverlays() }
    }

    private func tile(icon: String, value: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
        .buttonStyle(PressStyle())
    }
}

/// The level, its XP so far, and the bar. After a workout the bar fills from where it was to the new total (across
/// a level, it fills, empties and fills again), with "+N XP" beside it.
private struct LevelTile: View {
    @Environment(AppModel.self) private var model
    let action: () -> Void
    @State private var shown: Double?
    @State private var earned: Int?
    @State private var played: String?

    var body: some View {
        let progress = Experience.progress(of: model.training.sessions)
        let fraction = Double(progress.current) / Double(progress.required)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { Image(systemName: "rosette"); Text("Lv \(progress.level)").monospacedDigit() }
                    .font(.title3.weight(.bold)).foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.7)
                Text(earned.map { "+\($0) XP" } ?? "\(progress.current)/\(progress.required) XP")
                    .font(.subheadline.weight(earned == nil ? .regular : .bold)).monospacedDigit()
                    .foregroundStyle(earned == nil ? Palette.muted : Palette.accent).lineLimit(1).minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
                RankBar(progress: shown ?? fraction, color: Palette.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading).padding(14).glass()
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Level \(progress.level): \(progress.current) of \(progress.required) XP. How XP works")
        .task(id: fillKey) {
            guard let fill = model.xpFill, model.finished == nil, played != fillKey else { return }
            played = fillKey
            shown = Self.fraction(fill.from)
            earned = fill.to - fill.from
            try? await Task.sleep(for: .milliseconds(350))
            if Self.level(fill.from) < Self.level(fill.to) {
                withAnimation(.smooth(duration: 0.25)) { shown = 1 }
                try? await Task.sleep(for: .milliseconds(260))
                shown = 0
            }
            withAnimation(.smooth(duration: 0.4)) { shown = Self.fraction(fill.to) }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.smooth) { earned = nil; shown = nil }
        }
        .sensoryFeedback(.success, trigger: earned) { _, now in now != nil }
    }

    /// Changes when there's a new fill to play, and once the recap over it has closed.
    private var fillKey: String {
        guard let fill = model.xpFill else { return "none" }
        return "\(fill.from)-\(fill.to)-\(model.finished == nil)"
    }

    /// A total's place within its level (0–1) and the level it's in, by the website's level table.
    static func fraction(_ total: Int) -> Double {
        var level = 1, current = max(0, total)
        while current >= Experience.requirement(for: level) { current -= Experience.requirement(for: level); level += 1 }
        return Double(current) / Double(Experience.requirement(for: level))
    }

    static func level(_ total: Int) -> Int {
        var level = 1, current = max(0, total)
        while current >= Experience.requirement(for: level) { current -= Experience.requirement(for: level); level += 1 }
        return level
    }
}

/// The volume bars, the present one in the accent and the rest glass, growing in smoothly and reshaping when the
/// period changes.
private struct VolumeBars: View {
    let volumes: [Double]
    let label: String
    @State private var grown = false

    var body: some View {
        let top = max(volumes.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(volumes.enumerated()), id: \.offset) { index, volume in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(index == volumes.count - 1 ? Palette.primary : Palette.control)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.rim.opacity(0.4), lineWidth: 1))
                    .frame(height: 140 * (grown ? max(0.04, volume / top) : 0.04))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 140, alignment: .bottom)
        .onAppear { withAnimation(.smooth(duration: 0.7)) { grown = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume by \(label.lowercased()), last \(volumes.count)")
    }
}

extension Period {
    var name: String { self == .day ? "Day" : self == .week ? "Week" : "Month" }
    /// "today", "this week", "this month".
    var now: String { self == .day ? "today" : "this \(name.lowercased())" }
    var last: String { self == .day ? "yesterday" : "last \(name.lowercased())" }
    var bars: Int { self == .day ? 7 : self == .week ? 8 : 6 }
    var first: String { "\(bars - 1) \(name.lowercased())s ago" }
}
