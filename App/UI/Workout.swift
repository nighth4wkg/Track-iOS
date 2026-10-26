import SwiftUI
import TrackCore

/// The workout in progress (the PWA's Workout): ⌄ keeps it for later (or a swipe in from the left edge), the name opens
/// its options, Finish; the progress bar; one exercise open at a time (the first with a set to do, unless you opened
/// another), each closed one a card to tap; Add exercise; the rest timer floating at the bottom. The keyboard's Next
/// walks weight → reps → RIR → next set.
struct WorkoutScreen: View {
    @Environment(AppModel.self) private var model
    /// The exercise opened by hand; nil follows the workout (the first with a set to do).
    @State private var opened: String?
    @State private var arranging = false
    /// The set field being typed in ("<set id>.kg", ".reps" or ".rir"), on the workout's one keyboard (SetKeyboard).
    @State private var focus: String?

    var body: some View {
        if let active = model.training.active {
            let fields: [String] = active.exercises.flatMap { exercise in exercise.sets.flatMap { ["\($0.id).kg", "\($0.id).reps", "\($0.id).rir"] } }
            // Once every set is done none opens by itself: the page goes up to Finish instead.
            let expanded: String? = opened.flatMap { id in active.exercises.contains { $0.id == id } ? id : nil }
                ?? active.exercises.first { $0.doneCount < $0.setCount }?.id
            let splitId = active.splitId
            let previous: Session? = model.derived("previous \(splitId)") { sessions in
                sessions.filter { $0.splitId == splitId }.max { ($0.finishedAt ?? 0) < ($1.finishedAt ?? 0) }
            }
            ScrollViewReader { proxy in
                ScrollView { content(active, expanded: expanded, previous: previous) }
                    .scrollDismissesKeyboard(.interactively)
                    .setKeyboard($focus)
                    .background(Backdrop())
                    // While typing, one bar over the keyboard (the rest's time, Next, Done) instead of the rest timer.
                    // Without the keyboard the timer sits as far from the screen's edge as the nav pill.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if focus != nil { keyboardBar(fields) } else { RestTimer().floatingBottom() }
                    }
                    .edgeBack(true) { model.workoutOpen = false }
                    // The keyboard's Next reaching a closed card opens it.
                    .onChange(of: focus) { _, id in
                        guard let id, let exercise = active.exercises.first(where: { ex in ex.sets.contains { id.hasPrefix($0.id) } }), exercise.id != expanded else { return }
                        opened = exercise.id
                    }
                    // As the PWA's moveOn: a set done in a card with more to do shows its next set; the card's last set
                    // hands over to the next card with sets to do (also one opened by hand; the keyboard goes with it)
                    // and the page goes to it, or after the last one up to Finish. Each side counts here: L done shows R.
                    .onChange(of: active.exercises.map { $0.sets.filter(\.done).count }) { was, now in
                        guard was.count == now.count, let index = now.indices.first(where: { now[$0] > was[$0] }) else { return }
                        let card = active.exercises[index]
                        if let set = card.sets.first(where: { !$0.done }) {
                            if focus == nil { reveal(proxy, set.id, anchor: nil) } // while typing, the keyboard keeps its set in view
                            return
                        }
                        if opened == card.id { opened = nil }
                        focus = nil
                        reveal(proxy, active.exercises.first { $0.doneCount < $0.setCount }?.id ?? Self.top, anchor: .top)
                    }
                    .task { await FrameLog.driveNext(fields) { focus = $0 } }
            }
            .onDisappear { focus = nil }
        }
    }

    /// The page's top, where Finish is.
    private static let top = "top"

    /// Shows it (nil anchor: just enough), once the cards have their new heights.
    private func reveal(_ proxy: ScrollViewProxy, _ id: String, anchor: UnitPoint?) {
        DispatchQueue.main.async { proxy.scrollTo(id, anchor: anchor) }
    }

    /// The header, the progress bar, then the cards (or the list being arranged) and Add exercise.
    private func content(_ active: Session, expanded: String?, previous: Session?) -> some View {
        let done = active.exercises.doneCount, planned = active.exercises.plannedCount
        let unit = model.training.settings.unit
        return VStack(alignment: .leading, spacing: 0) {
            header(active, done: done, planned: planned).id(Self.top)
            Bar(value: Double(done) / Double(max(1, planned)))
                .padding(.top, Space.s3)
                .accessibilityLabel("Workout completion").accessibilityValue("\(done) of \(planned) sets")
            Group {
                if arranging { arrangeList(active, previous: previous, unit: unit) } else { cards(active, expanded: expanded, previous: previous, unit: unit) }
            }
            .padding(.top, Space.s4)
        }
        .padding(.horizontal, Space.s4).padding(.top, Space.s4).padding(.bottom, Space.s6)
        .frame(maxWidth: Size.column).frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: active.exercises.map(\.id))
        // A set done (or undone), each side of a pair too: here, since the last set's row goes with its card.
        .sensoryFeedback(trigger: active.exercises.reduce(0) { $0 + $1.sets.filter(\.done).count }) { was, now in now > was ? .impact(weight: .medium) : .selection }
    }

    private func arrangeList(_ active: Session, previous: Session?, unit: TrackCore.Settings.Unit) -> some View {
        ArrangeList(items: active.exercises, name: \.name, onMove: { from, to in
            model.update { training in
                guard let moved = training.active?.exercises.moved(from, to: to) else { return }
                training.active?.exercises = moved
            }
        }) { exercise in
            HStack(spacing: Space.s3) {
                Text("\((active.exercises.firstIndex { $0.id == exercise.id } ?? 0) + 1)").type(.t16).monospacedDigit()
                    .foregroundStyle(Palette.text).frame(width: Size.tile, height: Size.tile).raised(.control, .inner)
                VStack(alignment: .leading, spacing: 0) {
                    Text(exercise.name).type(.t16).foregroundStyle(Palette.text)
                    Text(ExerciseCard.detail(exercise, previous, unit)).type(.t14).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func cards(_ active: Session, expanded: String?, previous: Session?, unit: TrackCore.Settings.Unit) -> some View {
        let settings = model.training.settings
        let bests = model.bests
        return VStack(spacing: Space.s3) {
            ForEach(Array(active.exercises.enumerated()), id: \.element.id) { index, exercise in
                let muscle: String = LiftTable.muscles(for: exercise.name, choices: settings.lifts ?? [:]).first ?? "Exercise"
                let here: String? = focus.flatMap { id in exercise.sets.contains { id.hasPrefix($0.id) } ? id : nil }
                ExerciseCard(exercise: exercise, number: index + 1, open: expanded == exercise.id, unit: unit,
                             autoLog: settings.logSets != .manual, bests: bests,
                             last: previous?.exercises.first { $0.id == exercise.id || $0.name == exercise.name },
                             restSeconds: settings.restSeconds, muscle: muscle, focus: $focus, focusHere: here,
                             onOpen: { opened = exercise.id },
                             onOptions: { focus = nil; model.present(ExerciseOptions(exerciseId: exercise.id)) })
                    .equatable()
                    .id(exercise.id)
            }
            Button {
                focus = nil
                model.present(ExercisePicker { name in model.update { $0.active?.exercises.append(Exercise.new(named: name)) } }, tall: true)
            } label: { Label { Text("Add exercise") } icon: { Icon.plus.image(IconSize.medium) } }
            .buttonStyle(SecondaryStyle())
        }
    }

    /// ⌄, the name over the time and sets (it opens the options), Finish (Done while arranging).
    private func header(_ active: Session, done: Int, planned: Int) -> some View {
        HStack(spacing: Space.s3) {
            RoundButton(icon: .down, label: "Keep for later") { model.workoutOpen = false }
                .accessibilityHint("Keeps the workout going for later").accessibilityIdentifier("keep-for-later")
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                focus = nil
                model.present(WorkoutOptions(arrange: { arranging = true }))
            } label: {
                VStack(spacing: 0) {
                    HStack(spacing: Space.s1) {
                        Text(active.name).type(.t16).foregroundStyle(Palette.text).multilineTextAlignment(.center)
                        Icon.down.image(IconSize.small).foregroundStyle(Palette.muted)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsed(active.startedAt, context.date) + dot + "\(done)/\(planned) sets").type(.t14).monospacedDigit()
                            .foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    }
                }
            }
            .buttonStyle(CardStyle())
            .layoutPriority(1)
            .accessibilityLabel("\(active.name): workout options")
            Group {
                if arranging {
                    Button("Done") { arranging = false }.buttonStyle(SecondaryStyle(hug: true))
                } else {
                    Button("Finish") { focus = nil; model.finish() }.buttonStyle(PrimaryStyle(compact: true)).accessibilityLabel("Finish workout")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: Size.control)
    }

    /// While typing: one bar just over the keyboard with the rest's time on the left, then Next (weight → reps → RIR →
    /// next set) and Done. It replaces the rest timer meanwhile, so the two never stack up.
    private func keyboardBar(_ fields: [String]) -> some View {
        HStack(spacing: Space.s2) {
            // The rest's time takes the free room; with no rest the pill hugs its buttons.
            RestTimer(compact: true).padding(.leading, Space.s2)
            if let focus, let index = fields.firstIndex(of: focus), index + 1 < fields.count {
                Button("Next") { self.focus = fields[index + 1] }.buttonStyle(SecondaryStyle(hug: true))
            }
            Button("Done") { focus = nil }.buttonStyle(PrimaryStyle(compact: true))
        }
        .padding(Space.s1)
        .raised(.float, .pill)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, Space.s4).padding(.bottom, Space.s2)
    }
}

/// One exercise (the PWA's card). Closed: its number, name and "1 of 3 sets · last 60×8", tapped to open. Open: its
/// name over its muscle and rest, ⋯ for its options (swipe the name left and ⋯ becomes a red ✕ that removes it, with
/// Undo), the Set · Last · kg · Reps · RIR · Done columns, a row per set and Add set.
struct ExerciseCard: View, Equatable {
    @Environment(AppModel.self) private var model
    let exercise: Exercise
    let number: Int
    let open: Bool
    let unit: TrackCore.Settings.Unit
    let autoLog: Bool
    let bests: RecordBests
    /// This exercise in the split's last workout: the Last column.
    let last: Exercise?
    let restSeconds: Int
    let muscle: String
    var focus: Binding<String?>
    /// The field being typed in, when it's on this card: a card skipped as unchanged doesn't see the focus move, so
    /// this tells it (and its rows) when the keyboard comes or goes here.
    let focusHere: String?
    let onOpen: () -> Void
    let onOptions: () -> Void
    @State private var armed = false

    var body: some View {
        Group {
            if open { card } else { closed }
        }
        .onChange(of: open) { if !open { armed = false } }
    }

    private var closed: some View {
        Button(action: onOpen) {
            HStack(spacing: Space.s3) {
                Text("\(number)").type(.t16).monospacedDigit().foregroundStyle(Palette.text)
                    .frame(width: Size.tile, height: Size.tile).raised(.control, .inner)
                VStack(alignment: .leading, spacing: 0) {
                    Text(exercise.name).type(.t16).foregroundStyle(Palette.text).multilineTextAlignment(.leading)
                    Text(Self.detail(exercise, nil, unit, last: last)).type(.t14).monospacedDigit().foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon.down.image(IconSize.medium).foregroundStyle(Palette.muted)
            }
            .pad()
            .raised()
            .contentShape(Rectangle())
        }
        .buttonStyle(CardStyle())
        .accessibilityValue("Closed")
    }

    private var card: some View {
        let labels = exercise.setLabels
        let next = exercise.sets.firstIndex { !$0.done }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(exercise.name).type(.t20).foregroundStyle(Palette.text)
                    Text(muscle + dot + "Rest \(clock(restSeconds))").type(.t14).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { if armed { armed = false } }
                if armed {
                    RoundButton(icon: .close, label: "Remove \(exercise.name)", tint: Palette.danger) { armed = false; model.removeExercise(exercise) }
                } else {
                    RoundButton(icon: .more, label: "\(exercise.name) options", action: onOptions)
                }
            }
            .swipeToArm($armed)
            SetColumns {
                Text("Set"); Text("Last"); Text(unit.rawValue); Text("Reps"); Text("RIR"); Text("Done")
            }
            .type(.t12).foregroundStyle(Palette.muted)
            .padding(.top, Space.s4)
            .accessibilityHidden(true)
            VStack(spacing: Space.s2) {
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                    SetRow(exercise: exercise, set: set, label: labels[index], next: index == next, unit: unit, autoLog: autoLog, bests: bests,
                           last: last.flatMap { $0.sets.indices.contains(index) ? $0.sets[index] : nil },
                           focus: focus,
                           focused: focusHere.flatMap { $0.hasPrefix("\(set.id).") ? String($0.dropFirst(set.id.count + 1)) : nil })
                        .id(set.id) // what the keyboard scrolls to (SetKeyboard)
                }
            }
            .padding(.top, Space.s2)
            Button { model.update { $0.updateActive(exercise: exercise.id) { $0 = $0.addingSet() } } } label: {
                Label { Text("Add set") } icon: { Icon.plus.image(IconSize.medium) }
            }
            .buttonStyle(SecondaryStyle())
            .disabled(exercise.sets.count >= Limits.sets)
            .padding(.top, Space.s4)
        }
        .pad()
        .raised()
    }

    /// Saving a set redraws only its card, not every card in the workout (the keyboard focus updates each by itself).
    static func == (a: Self, b: Self) -> Bool {
        a.exercise == b.exercise && a.number == b.number && a.open == b.open && a.unit == b.unit && a.autoLog == b.autoLog
            && a.bests.id == b.bests.id && a.last == b.last && a.restSeconds == b.restSeconds && a.muscle == b.muscle && a.focusHere == b.focusHere
    }

    /// "1 of 3 sets · last 60×8": done of the sets as counted, and last time's first set.
    static func detail(_ exercise: Exercise, _ previous: Session?, _ unit: TrackCore.Settings.Unit, last: Exercise? = nil) -> String {
        let last = last ?? previous?.exercises.first { $0.id == exercise.id || $0.name == exercise.name }
        return "\(exercise.doneCount) of \(count(exercise.setCount, "set"))" + dot + "last \(lastText(last?.sets.first, unit))"
    }

    /// A set from last time, compact so it fits its column on the smallest phones: "60×8", or "–".
    static func lastText(_ set: TrainingSet?, _ unit: TrackCore.Settings.Unit) -> String {
        guard let set, set.isValid, let kg = set.kg, let reps = set.reps else { return "–" }
        return "\(TrainingSet.display(kg: kg, unit: unit))×\(reps)"
    }
}

/// The set grid's six columns (the PWA's .sets): each as wide as a cell at most, spread across the card.
struct SetColumns<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: Space.s1) {
            Group(subviews: content) { cells in
                ForEach(cells) { cell in cell.frame(maxWidth: Size.cell).frame(maxWidth: .infinity) }
            }
        }
    }
}
