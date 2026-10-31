import SwiftUI
import TrackCore

/// Home (the PWA's Today): the brand and Settings, the date over "Ready to train" (or "Keep going"), the week ring
/// beside what's next (or the workout in progress) with one main button, your splits, then this week's volume and the
/// next achievement.
struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var arranging = false

    var body: some View {
        let training = model.training
        let now = nowMillis()
        // Worked out once: it reads every past workout.
        let next = training.nextSplit
        TabPage {
            HStack(spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    TrackMark().foregroundStyle(Palette.text)
                    Text("track").type(.t20).foregroundStyle(Palette.text)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                RoundButton(icon: .settings, label: "Settings") { model.open(.settings) }
            }
            .frame(minHeight: Size.control)
            VStack(alignment: .leading, spacing: 0) {
                Text(Date.now.formatted(.gregorian.weekday(.wide).month(.abbreviated).day())).type(.t14).foregroundStyle(Palette.muted)
                Text(training.active == nil ? "Ready to train" : "Keep going").type(.t32).foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.top, Space.s2)
            if let error = model.loadError {
                Label(error, systemImage: Icon.warning.rawValue).type(.t14).foregroundStyle(Palette.danger).padding(.top, Space.s4)
            }
            UpNextCard(training: training, next: next, now: now).padding(.top, Space.s4)
            if !training.splits.isEmpty { splits(training, next: next?.split.id).padding(.top, Space.s6) }
            HomeTiles(training: training, now: now).padding(.top, Space.s3)
        }
        .sensoryFeedback(.selection, trigger: training.splits.map(\.id))
        .onChange(of: training.splits.count) { _, count in if count < 2 { arranging = false } }
    }

    private func splits(_ training: Training, next: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                Text("Your splits").type(.t20).foregroundStyle(Palette.text).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                HStack(spacing: Space.s1) {
                    if training.splits.count > 1 {
                        RoundButton(icon: arranging ? .check : .arrange, label: arranging ? "Done arranging splits" : "Arrange splits") { arranging.toggle() }
                    }
                    if !arranging { RoundButton(icon: .plus, label: "New split") { model.present(NewSplitSheet()) } }
                }
            }
            if arranging {
                ArrangeList(items: training.splits, name: \.name, onMove: { from, to in model.update { $0.splits = $0.splits.moved(from, to: to) } }) { split in
                    SplitLine(split: split)
                }
            } else {
                VStack(spacing: Space.s3) {
                    ForEach(training.splits) { split in
                        SplitCard(split: split, next: training.active == nil && next == split.id)
                    }
                }
            }
        }
    }
}

/// Home's first card: this week's training days on the ring beside what's next (a green label, the name, its facts as
/// lines), then one main button. The split trained longest ago and Start; or the workout in progress and Continue,
/// which a swipe left turns into Discard (Track asks first); or, with no splits, New split.
private struct UpNextCard: View {
    @Environment(AppModel.self) private var model
    let training: Training
    let next: (split: Split, lastDone: Int?)?
    let now: Int
    @State private var discarding = false

    var body: some View {
        VStack(spacing: Space.s4) {
            HStack(spacing: Space.s4) {
                VStack(spacing: Space.s1) {
                    WeekRing(done: model.derived("days", at: dayKey(now)) { $0.trainingDays(inWeekOf: now).count }, goal: training.settings.weeklyGoal)
                    Text("This week").type(.t12).foregroundStyle(Palette.muted).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    if let active = training.active {
                        Badge(text: "In progress").padding(.bottom, Space.s1)
                        Text(active.name).type(.t20)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(elapsed(active.startedAt, context.date)).type(.t14).monospacedDigit().foregroundStyle(Palette.muted)
                        }
                        Text("\(active.exercises.doneCount) of \(count(active.exercises.plannedCount, "set")) done")
                            .type(.t14).monospacedDigit().foregroundStyle(Palette.muted)
                    } else if let next {
                        Badge(text: "Up next").padding(.bottom, Space.s1)
                        Text(next.split.name).type(.t20)
                        Text(next.split.summary).type(.t14).foregroundStyle(Palette.muted)
                        Text(next.lastDone.map { "Last done " + ago($0, now: now) } ?? "Not done yet").type(.t14).foregroundStyle(Palette.muted)
                    } else {
                        Badge(text: "Get started").padding(.bottom, Space.s1)
                        Text("First split").type(.t20)
                        Text("A workout to repeat.").type(.t14).foregroundStyle(Palette.muted)
                    }
                }
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            button
        }
        .pad()
        .raised()
        .modifier(ArmIf(on: training.active != nil, armed: $discarding))
        .onChange(of: training.active == nil) { discarding = false }
    }

    @ViewBuilder private var button: some View {
        if training.active != nil {
            if discarding {
                Button { discarding = false; model.discard() } label: { Label { Text("Discard workout") } icon: { Icon.trash.image(IconSize.small, bold: true) } }
                    .buttonStyle(SecondaryStyle(danger: true, height: Size.primary))
            } else {
                Button { model.workoutOpen = true } label: { Label { Text("Continue workout") } icon: { Icon.play.image(IconSize.small) } }
                    .buttonStyle(PrimaryStyle())
            }
        } else if let next {
            Button { model.start(next.split) } label: { Label { Text("Start workout") } icon: { Icon.play.image(IconSize.small) } }
                .buttonStyle(PrimaryStyle())
        } else {
            Button { model.present(NewSplitSheet()) } label: { Label { Text("New split") } icon: { Icon.plus.image(IconSize.small) } }
                .buttonStyle(PrimaryStyle())
        }
    }
}

/// Swipe to arm, only while there's something to arm (the workout in progress).
private struct ArmIf: ViewModifier {
    let on: Bool
    @Binding var armed: Bool

    func body(content: Content) -> some View {
        if on { content.swipeToArm($armed) } else { content }
    }
}

/// The week's training days against the goal: "2/3" over "days".
private struct WeekRing: View {
    let done: Int
    let goal: Int

    var body: some View {
        Ring(value: Double(done) / Double(max(1, goal)), size: Rings.week.size, stroke: Rings.week.stroke,
             label: "\(done) of \(count(goal, "training day")) this week") {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(done)").type(.t28).foregroundStyle(Palette.text)
                    Text("/\(goal)").type(.t14).foregroundStyle(Palette.muted)
                }
                .monospacedDigit()
                Text(goal == 1 ? "day" : "days").type(.t12).foregroundStyle(Palette.muted)
            }
        }
    }
}

/// This week's volume against last week up to the same moment, and the achievement you're nearest.
private struct HomeTiles: View {
    @Environment(AppModel.self) private var model
    let training: Training
    let now: Int

    var body: some View {
        Tiles { volume } second: { achievement }
    }

    private var volume: some View {
        let week = model.derived("volume W", at: minuteStamp(now)) { $0.change(of: .volume, per: .week, at: now) }
        return VStack(alignment: .leading, spacing: 0) {
            Text("Volume this week").type(.t14).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                Text(weight(week.value, training.settings.unit)).type(.t20).monospacedDigit().foregroundStyle(Palette.text)
                Text(training.settings.unit.rawValue).type(.t14).foregroundStyle(Palette.muted)
            }
            .padding(.top, Space.s2)
            if let change = week.change {
                Text(week.value == 0 ? "Nothing logged yet" : change == 0 ? "Same as last week" : "\(change > 0 ? "▲" : "▼") \(abs(change))% vs last week")
                    .type(.t14).foregroundStyle(week.value > 0 && change > 0 ? Palette.accent : Palette.muted)
            }
        }
        .tileCard()
    }

    private var achievement: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Next achievement").type(.t14).foregroundStyle(Palette.muted)
            if let next = model.derived("nearest quest", { $0.nearestQuest() }) {
                let ratio = Double(next.value) / Double(max(1, next.quest.threshold))
                Text(next.quest.title).type(.t16).foregroundStyle(Palette.text)
                Bar(value: ratio).accessibilityLabel("\(next.quest.title): \(Int((ratio * 100).rounded()))%")
            } else {
                Text("All earned").type(.t16).foregroundStyle(Palette.text)
            }
        }
        .tileCard()
    }
}

/// A split's tile, name and size, as a row on Home and in Arrange.
struct SplitLine: View {
    let split: Split

    var body: some View {
        HStack(spacing: Space.s3) {
            TrackMark(size: IconSize.medium).foregroundStyle(Palette.text)
                .frame(width: Size.tile, height: Size.tile).raised(.control, .inner)
            VStack(alignment: .leading, spacing: 0) {
                Text(split.name).type(.t16).foregroundStyle(Palette.text)
                Text(split.exercises.isEmpty ? "Tap to add exercises" : split.summary).type(.t14).foregroundStyle(Palette.muted)
            }
        }
    }
}

/// One split on its own card: tap it for its page; swipe it left (or hold it) and its end becomes a red trash, which
/// asks first. The one up next says so.
private struct SplitCard: View {
    @Environment(AppModel.self) private var model
    let split: Split
    let next: Bool
    @State private var armed = false

    var body: some View {
        HStack(spacing: 0) {
            Button { if armed { armed = false } else { model.open(.split(split.id)) } } label: {
                HStack(spacing: Space.s3) {
                    SplitLine(split: split)
                    Spacer(minLength: 0)
                    if next && !armed { Badge(text: "Next") }
                }
                .pad()
                .frame(minHeight: Size.controlRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowStyle())
            if armed {
                RoundButton(icon: .trash, label: "Delete \(split.name)", tint: Palette.danger) { armed = false; model.deleteSplit(split) }
                    .padding(.trailing, Space.s4)
            }
        }
        .clipShape(Corner.card.shape)
        .raised()
        .swipeToArm($armed)
    }
}

/// New split: a name and Create, or one of the starter templates. Made, it opens its page.
struct NewSplitSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeSheet) private var close
    @State private var name = ""
    /// A template whose name is taken isn't added twice: its message shows under the templates.
    @State private var templateProblem: String?

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let problem = trimmed.isEmpty ? nil : model.splitNameTaken(trimmed)
        let save = { if !trimmed.isEmpty, problem == nil { create(Split(name: String(trimmed.prefix(Limits.name)))) } }
        SheetFrame(title: "New split", closeLabel: "Cancel") {
            VStack(alignment: .leading, spacing: Space.s4) {
                Field(placeholder: "Name, like Push A", text: $name, label: "Split name", submit: save)
                    .onChange(of: name) { templateProblem = nil }
                if let problem { Text(problem).type(.t14).foregroundStyle(Palette.danger) }
                Button("Create", action: save).buttonStyle(PrimaryStyle()).disabled(trimmed.isEmpty || problem != nil)
            }
            .padding(.top, Space.s3)
            Text("Or start from a template").type(.t14).foregroundStyle(Palette.muted).padding(.top, Space.s6)
            RowCard {
                ForEach(SplitTemplate.all) { template in
                    Button { create(template.makeSplit()) } label: {
                        HStack(spacing: Space.s3) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(template.name).type(.t16).foregroundStyle(Palette.text)
                                Text(template.exercises.joined(separator: ", ")).type(.t14).foregroundStyle(Palette.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Icon.plus.image(IconSize.medium).foregroundStyle(Palette.muted)
                        }
                        .pad()
                        .frame(minHeight: Size.row)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowStyle())
                }
            }
            .padding(.top, Space.s2)
            if let templateProblem { Text(templateProblem).type(.t14).foregroundStyle(Palette.danger).padding(.top, Space.s2) }
        }
    }

    private func create(_ split: Split) {
        if let taken = model.splitNameTaken(split.name) { templateProblem = taken; return }
        model.update { $0.splits.append(split) }
        close()
        model.open(.split(split.id))
    }
}

extension Split {
    /// "3 exercises · 9 sets"
    var summary: String { count(exercises.count, "exercise") + dot + count(exercises.plannedCount, "set") }
}
