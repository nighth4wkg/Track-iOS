import SwiftUI
import TrackCore

/// Home, as on the website: today's date over "Ready to train", the Up next card (this week's ring and one Start),
/// your splits (swipe one left to delete it, ↑↓ to arrange), then this week's volume and the next achievement.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var settingsOpen: Bool
    @State private var adding = false
    @State private var editing: Split?
    @State private var arranging = false
    @State private var deleting: Split?

    var body: some View {
        let training = model.training
        let now = nowMillis()
        Page(title: training.active == nil ? "Ready to train" : "Keep going",
             caption: Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), settingsOpen: $settingsOpen) {
            if let error = model.loadError {
                Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(Palette.danger)
            }
            UpNextCard(training: training, now: now) { adding = true }
            SectionHeading(title: "Your splits", count: training.splits.isEmpty ? nil : training.splits.count) {
                if training.splits.count > 1 {
                    GlassCircleButton(icon: "arrow.up.arrow.down", label: arranging ? "Done arranging" : "Arrange splits", active: arranging) {
                        withAnimation(.smooth) { arranging.toggle() }
                    }
                }
                GlassCircleButton(icon: "plus", label: "Add split") { adding = true }
            }
            if training.splits.isEmpty {
                EmptyCard(icon: "dumbbell", title: "No splits yet", detail: "Add one to start training.")
            } else {
                GlassList {
                    ForEach(Array(training.splits.enumerated()), id: \.element.id) { index, split in
                        SwipeToDelete(onDelete: { deleting = split }) {
                            Button { if !arranging { editing = split } } label: {
                                ListRow(mark: true, title: split.name, detail: split.summary) {
                                    if arranging { arrange(index, of: training.splits.count) }
                                    else if split.id == training.nextSplit?.split.id { Chip(text: "Next", accent: true) }
                                    else { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
            }
            Tiles(training: training, now: now)
        }
        .sensoryFeedback(.selection, trigger: arranging)
        .sensoryFeedback(.selection, trigger: training.splits.map(\.id))
        .sheet(isPresented: $adding) { NewSplitView { editing = $0 } }
        .sheet(item: $editing) { SplitEditor(splitId: $0.id) }
        .confirmationDialog("Delete \(deleting?.name ?? "split")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete split", role: .destructive) {
                if let id = deleting?.id { withAnimation(.smooth) { model.update { $0.splits.removeAll { $0.id == id } } } }
            }
        } message: { Text("Your finished workouts stay in History.") }
        .sensoryFeedback(.warning, trigger: deleting?.id) { _, now in now != nil }
    }

    /// ↑ ↓ for one split while arranging.
    private func arrange(_ index: Int, of total: Int) -> some View {
        HStack(spacing: 8) {
            GlassCircleButton(icon: "arrow.up", label: "Move up") { move(index, -1) }.disabled(index == 0).opacity(index == 0 ? 0.35 : 1)
            GlassCircleButton(icon: "arrow.down", label: "Move down") { move(index, 1) }.disabled(index == total - 1).opacity(index == total - 1 ? 0.35 : 1)
        }
    }

    private func move(_ index: Int, _ direction: Int) {
        withAnimation(.smooth(duration: 0.3)) { model.update { $0.splits = $0.splits.moving(index, by: direction) } }
    }
}

/// The home screen's one answer to "what now?": this week's ring, the split up next (or the active workout), and one
/// prominent Start.
private struct UpNextCard: View {
    @Environment(AppModel.self) private var model
    let training: Training
    let now: Int
    let add: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                WeekRing(done: training.sessions.inWeek(of: now).count, goal: training.settings.weeklyGoal)
                VStack(alignment: .leading, spacing: 4) {
                    if let active = training.active {
                        line("In progress", active.name,
                             "\(active.completedSets.count) of \(count(active.exercises.reduce(0) { $0 + $1.sets.count }, "set"))", nil)
                    } else if let next = training.nextSplit {
                        line("Up next", next.split.name, next.split.summary, lastDone(next.lastDone))
                    } else {
                        line("Get started", "Add a split", "Pick a starter or build your own.", nil)
                    }
                }
                Spacer(minLength: 0)
            }
            if training.active != nil {
                Button { model.workoutOpen = true } label: { Label("Resume workout", systemImage: "play.fill") }.buttonStyle(PrimaryButtonStyle())
            } else if let next = training.nextSplit {
                Button { model.start(next.split) } label: { Label("Start workout", systemImage: "play") }.buttonStyle(PrimaryButtonStyle())
            } else {
                Button(action: add) { Label("Add a split", systemImage: "plus") }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20)
        .glass()
        .sensoryFeedback(.impact(weight: .medium), trigger: model.workoutOpen) { _, open in open }
    }

    @ViewBuilder private func line(_ caption: String, _ title: String, _ detail: String, _ extra: String?) -> some View {
        Text(caption).font(.subheadline).foregroundStyle(Palette.muted)
        Text(title).font(.title2.weight(.bold)).foregroundStyle(Palette.text).lineLimit(1)
        Text(detail).font(.subheadline).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        if let extra { Text(extra).font(.subheadline).foregroundStyle(Palette.muted) }
    }

    private func lastDone(_ last: Int?) -> String {
        guard let last else { return "Not done yet" }
        let days = (now - last) / 86_400_000
        return days < 1 ? "Done today" : days == 1 ? "Last done yesterday" : "Last done \(days) days ago"
    }
}

/// This week's volume against last week, and the achievement you're nearest.
private struct Tiles: View {
    let training: Training
    let now: Int

    var body: some View {
        let week = training.sessions.weekVolumeChange(at: now)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Volume this week").font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(weight(week.volume, training.settings.unit)).font(.title2.weight(.bold)).monospacedDigit()
                    Text(training.settings.unit.rawValue).font(.subheadline).foregroundStyle(Palette.muted)
                }
                .foregroundStyle(Palette.text)
                if let change = week.change {
                    Label("\(abs(change))% vs last week", systemImage: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(change >= 0 ? Palette.accent : Palette.muted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading).padding(16).glass()
            VStack(alignment: .leading, spacing: 8) {
                Text("Next achievement").font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                if let next = training.sessions.nearestQuest() {
                    Text(next.quest.title).font(.headline).foregroundStyle(Palette.text).lineLimit(2)
                    ProgressView(value: Double(next.value), total: Double(next.quest.threshold)).tint(Palette.primary)
                } else {
                    Text("All earned").font(.headline).foregroundStyle(Palette.text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading).padding(16).glass()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension Split {
    /// "3 exercises · 9 sets"
    var summary: String {
        "\(count(exercises.count, "exercise")) · \(count(exercises.reduce(0) { $0 + $1.sets.count }, "set"))"
    }
}
