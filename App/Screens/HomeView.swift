import SwiftUI
import TrackCore

/// Home, as on the website: today's date over "Ready to train", the Up next card (this week's ring and one Start),
/// your splits, then this week's volume and your level.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var settingsOpen: Bool
    @State private var adding = false
    @State private var editing: Split?
    @State private var arranging = false

    var body: some View {
        let training = model.training
        let now = nowMillis()
        Page(title: training.active == nil ? "Ready to train" : "Keep going",
             caption: Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), settingsOpen: $settingsOpen) {
            if let error = model.loadError {
                Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(Palette.danger).bareRow()
            }
            Section { hero(training, now: now).bareRow() }
            Section {
                if training.splits.isEmpty {
                    Text("No splits yet. Add one to start training.").font(.subheadline).foregroundStyle(Palette.muted).glassRow()
                }
                ForEach(training.splits) { split in
                    Button { editing = split } label: {
                        ListRow(mark: true, title: split.name, detail: split.summary) {
                            if split.id == training.nextSplit?.split.id { Chip(text: "Next", accent: true) }
                            else { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted) }
                        }
                    }
                    .glassRow()
                }
                .onDelete { offsets in
                    let ids = offsets.map { training.splits[$0].id }
                    model.update { $0.splits.removeAll { ids.contains($0.id) } }
                }
                .onMove { from, to in model.update { $0.splits.move(fromOffsets: from, toOffset: to) } }
            } header: {
                HStack {
                    Header(title: "Your splits", count: training.splits.isEmpty ? nil : training.splits.count)
                    Spacer()
                    if training.splits.count > 1 {
                        GlassCircleButton(icon: "arrow.up.arrow.down", label: arranging ? "Done arranging" : "Arrange splits", active: arranging) {
                            withAnimation(.smooth) { arranging.toggle() }
                        }
                    }
                    GlassCircleButton(icon: "plus", label: "Add split") { adding = true }
                }
            }
            Section { tiles(training, now: now).bareRow() }
        }
        .environment(\.editMode, .constant(arranging ? .active : .inactive))
        .sensoryFeedback(.selection, trigger: arranging)
        .sheet(isPresented: $adding) { NewSplitView { editing = $0 } }
        .sheet(item: $editing) { SplitEditor(splitId: $0.id) }
    }

    @ViewBuilder private func hero(_ training: Training, now: Int) -> some View {
        let week = training.sessions.inWeek(of: now).count
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                WeekRing(done: week, goal: training.settings.weeklyGoal)
                VStack(alignment: .leading, spacing: 4) {
                    if let active = training.active {
                        Text("In progress").font(.subheadline).foregroundStyle(Palette.muted)
                        Text(active.name).font(.title2.weight(.bold)).foregroundStyle(Palette.text).lineLimit(1)
                        Text("\(active.completedSets.count) of \(active.exercises.reduce(0) { $0 + $1.sets.count }) sets")
                            .font(.subheadline).foregroundStyle(Palette.muted)
                    } else if let next = training.nextSplit {
                        Text("Up next").font(.subheadline).foregroundStyle(Palette.muted)
                        Text(next.split.name).font(.title2.weight(.bold)).foregroundStyle(Palette.text).lineLimit(1)
                        Text(next.split.summary).font(.subheadline).foregroundStyle(Palette.muted)
                        Text(lastDone(next.lastDone, now: now)).font(.subheadline).foregroundStyle(Palette.muted)
                    } else {
                        Text("Get started").font(.subheadline).foregroundStyle(Palette.muted)
                        Text("Add a split").font(.title2.weight(.bold)).foregroundStyle(Palette.text)
                        Text("Pick a starter or build your own.").font(.subheadline).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if training.active != nil {
                Button { model.workoutOpen = true } label: { Label("Resume workout", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle())
            } else if let next = training.nextSplit {
                Button { model.start(next.split) } label: { Label("Start workout", systemImage: "play") }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button { adding = true } label: { Label("Add a split", systemImage: "plus") }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20)
        .glass()
        .sensoryFeedback(.impact(weight: .medium), trigger: model.workoutOpen) { _, open in open }
    }

    @ViewBuilder private func tiles(_ training: Training, now: Int) -> some View {
        let week = training.sessions.weekVolumeChange(at: now)
        let level = Experience.progress(of: training.sessions)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Volume this week").font(.subheadline).foregroundStyle(Palette.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(weight(week.volume, training.settings.unit)).font(.title2.weight(.bold)).monospacedDigit()
                    Text(training.settings.unit.rawValue).font(.subheadline).foregroundStyle(Palette.muted)
                }
                .foregroundStyle(Palette.text)
                if let change = week.change {
                    Label("\(abs(change))% vs last week", systemImage: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(change >= 0 ? Palette.accent : Palette.muted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading).padding(16).glass()
            VStack(alignment: .leading, spacing: 8) {
                if let next = training.sessions.nearestQuest() {
                    Text("Next achievement").font(.subheadline).foregroundStyle(Palette.muted)
                    Text(next.quest.title).font(.headline).foregroundStyle(Palette.text).lineLimit(2)
                    ProgressView(value: Double(next.value), total: Double(next.quest.threshold)).tint(Palette.primary)
                } else {
                    Text("Level \(level.level)").font(.subheadline).foregroundStyle(Palette.muted)
                    Text("\(level.current) / \(level.required) XP").font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Palette.text)
                    ProgressView(value: Double(level.current), total: Double(level.required)).tint(Palette.primary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading).padding(16).glass()
        }
    }

    private func lastDone(_ last: Int?, now: Int) -> String {
        guard let last else { return "Not done yet" }
        let days = (now - last) / 86_400_000
        return days < 1 ? "Done today" : days == 1 ? "Last done yesterday" : "Last done \(days) days ago"
    }
}

extension Split {
    /// "3 exercises · 9 sets"
    var summary: String {
        "\(count(exercises.count, "exercise")) · \(count(exercises.reduce(0) { $0 + $1.sets.count }, "set"))"
    }
}
