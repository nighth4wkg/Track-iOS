import SwiftUI
import TrackCore

/// Home, as on the website: today's date over "Ready to train" (or "Keep going"), the workout in progress or the Up
/// next card, your splits (tap one for its page, swipe it left to delete it, hold and drag to move it), then this week's volume
/// and the next achievement.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var settingsOpen: Bool
    @State private var open: String?

    var body: some View {
        let training = model.training
        let now = nowMillis()
        let nextId = training.active == nil ? training.nextSplit?.split.id : nil
        Page(title: training.active == nil ? "Ready to train" : "Keep going",
             caption: Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), settingsOpen: $settingsOpen) {
            if let error = model.loadError {
                Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(Palette.danger)
            }
            if let active = training.active {
                SwipeToDelete(label: "Discard", onDelete: { model.discard() }) { ResumeCard(active: active) }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .transition(.opacity)
            } else if training.nextSplit != nil {
                UpNextCard(training: training, now: now)
            }
            SectionHeading(title: "Your splits") {
                if !training.splits.isEmpty { GlassCircleButton(icon: "plus", label: "Create split", action: create) }
            }
            if training.splits.isEmpty {
                FirstSplitCard(create: create)
            } else {
                SplitList(nextId: nextId) { open = $0 }
                .navigationDestination(item: $open) { SplitPage(splitId: $0) }
            }
            HomeTiles(training: training, now: now)
        }
        .animation(.smooth(duration: 0.3), value: training.active?.id)
        .sensoryFeedback(.selection, trigger: training.splits.map(\.id))
    }

    private func create() {
        model.naming = Naming(title: "Create a split", action: "Create split") { name in
            let split = Split(name: name)
            model.update { $0.splits.append(split) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { open = split.id }
        }
    }
}

/// Your splits on one glass card: tap one for its page, swipe it left to delete it, hold and drag it to move it. The
/// end of each row says In progress, Next, or ›.
private struct SplitList: View {
    @Environment(AppModel.self) private var model
    let nextId: String?
    let open: (String) -> Void
    @State private var dragging: String?

    var body: some View {
        let ids = model.training.splits.map(\.id)
        GlassList {
            ForEach(model.training.splits) { split in
                SwipeToDelete(onDelete: { model.deleteSplit(split) }) {
                    Button { open(split.id) } label: { row(split).contentShape(Rectangle()) }
                        .buttonStyle(PressStyle())
                        .reorderHandle(split.id, dragging: $dragging) { row(split).padding(.horizontal, 16).padding(.vertical, 10).frame(width: 340).glass(fill: Palette.dialog) }
                }
                .reorderTarget(split.id, in: ids, dragging: $dragging) { from, to in model.update { $0.splits = $0.splits.moved(from, to: to) } }
            }
        }
    }

    private func row(_ split: Split) -> some View {
        ListRow(mark: true, title: split.name, detail: split.exercises.isEmpty ? "Tap to add exercises" : split.summary) { end(split) }
    }

    @ViewBuilder private func end(_ split: Split) -> some View {
        if model.training.active?.splitId == split.id {
            Chip(text: "In progress")
        } else if split.id == nextId {
            Chip(text: "Next", accent: true)
        } else {
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
        }
    }
}

/// The workout in progress: a live dot, its name, elapsed · sets logged · exercises, and Resume (Home's one primary).
/// Swipe it left to discard it; Track asks first.
private struct ResumeCard: View {
    @Environment(AppModel.self) private var model
    let active: Session

    var body: some View {
        Button { model.workoutOpen = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.primary).frame(width: 8, height: 8)
                        Text("Workout in progress").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent)
                    }
                    Text(active.name).font(.title2.weight(.bold)).foregroundStyle(Palette.text).lineLimit(1)
                }
                HStack(spacing: 0) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        stat(elapsed(active.startedAt, context.date), "Elapsed")
                    }
                    stat("\(active.completedSets.count)", "Sets logged")
                    stat("\(active.exercises.count)", "Exercises")
                }
                Label("Resume workout", systemImage: "play.fill").font(.headline).foregroundStyle(Palette.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(Palette.primary))
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading).glass()
        }
        .buttonStyle(PressStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: model.workoutOpen) { _, open in open }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline).monospacedDigit().foregroundStyle(Palette.text)
            Text(label).font(.caption).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "0:42" or "1:05:09" since the start.
func elapsed(_ start: Int, _ now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince1970) - start / 1000)
    return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        : String(format: "%d:%02d", seconds / 60, seconds % 60)
}

/// The first-run card: create a split, or start from a template in one tap.
private struct FirstSplitCard: View {
    @Environment(AppModel.self) private var model
    let create: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            TrackMark(size: 28).foregroundStyle(Palette.text).frame(width: 56, height: 56).glass(radius: 16, fill: Palette.control, lifted: false)
            Text("Create your first split.").font(.title3.weight(.bold)).foregroundStyle(Palette.text)
            Text("Build a routine you can reuse for every session.").font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            Button(action: create) { Label("Create split", systemImage: "plus") }.buttonStyle(PrimaryButtonStyle())
            Text("Or start from a template").font(.caption).foregroundStyle(Palette.muted).padding(.top, 4)
            FlowLayout(spacing: 8) {
                ForEach(SplitTemplate.all) { template in
                    Button(template.name) { withAnimation(.smooth) { model.update { $0.splits.append(template.makeSplit()) } } }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                        .padding(.horizontal, 14).frame(minHeight: 40).glass(radius: 20, fill: Palette.control, lifted: false)
                        .buttonStyle(PressStyle())
                }
            }
        }
        .padding(24).frame(maxWidth: .infinity).glass()
    }
}
