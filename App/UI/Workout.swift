import SwiftUI
import TrackCore

/// The workout in progress (the PWA's Workout): ⌄ keeps it for later (or a swipe right), the name opens
/// its options, Finish; the progress bar; one exercise open at a time (the first with a set to do, unless you opened
/// another), each closed one a card to tap; Add exercise; the rest timer floating at the bottom. The keyboard's Next
/// walks weight → reps → RIR → next set.
struct WorkoutScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.shown) private var shown
    /// The exercise opened by hand; nil follows the workout (the first with a set to do).
    @State private var opened: String?
    /// The card the workout follows (the first with a set to do), a beat behind: a card whose last set was just done
    /// stays open while its ✓ pops, then hands over (owner: it closed before the ✓ showed).
    @State private var following: String?
    @State private var arranging = false
    /// A card and its arranging row are one row: going in and out of arranging, each glides to where the other is.
    @Namespace private var rows
    /// The set field being typed in ("<set id>.kg", ".reps" or ".rir"), on the workout's one keyboard (SetKeyboard).
    @State private var focus: String?
    /// The rest timer's (or the keyboard bar's) height over the page's bottom.
    @State private var dock: CGFloat = 0

    var body: some View {
        if let active = model.training.active ?? model.leaving {
            let fields: [String] = active.exercises.flatMap { exercise in exercise.sets.flatMap { ["\($0.id).kg", "\($0.id).reps", "\($0.id).rir"] } }
            // Once every set is done none opens by itself: the page goes up to Finish instead.
            let current = active.exercises.first { $0.doneCount < $0.setCount }?.id
            let here = { (id: String?) -> String? in id.flatMap { id in active.exercises.contains { $0.id == id } ? id : nil } }
            let expanded: String? = here(opened) ?? here(following) ?? current
            let splitId = active.splitId
            let previous: Session? = model.derived("previous \(splitId)") { _ in model.training.latestSession(of: splitId) }
            ScrollViewReader { proxy in
                ZStack {
                    if AB.uikitList {
                        // To the screen's edge under the rest timer, as the PWA's page runs under its floating timer.
                        // Kept while the cards are arranged, out of sight: made again on Done it cost ~30 ms (build 107).
                        // The jump key rests while typing and while a done card hands over (its ✓, then the glide).
                        CardList(rows: rows(active, expanded: expanded, current: current, previous: previous), model: model, dock: dock, frozen: arranging,
                                 quiet: focus != nil || (here(following) ?? current) != current) {
                            focus = nil
                            Motion.tap { opened = nil; following = current }
                            if let current { reveal(proxy, current, anchor: .top) }
                        }
                            .ignoresSafeArea(.container, edges: .bottom)
                            .opacity(arranging ? 0 : 1).allowsHitTesting(!arranging).accessibilityHidden(arranging)
                    }
                    if !AB.uikitList || arranging {
                        ScrollView { content(active, expanded: expanded, current: current, previous: previous).arrives(forward: true) }
                    }
                }
                    .feedback(active)
                    .scrollDismissesKeyboard(.interactively)
                    .setKeyboard($focus)
                    .background(Backdrop())
                    // While typing, one bar over the keyboard (the rest's time, Next, Done) instead of the rest timer.
                    // Without the keyboard the timer sits as far from the screen's edge as the nav pill.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Group { if focus != nil { keyboardBar(fields) } else { RestTimer().floatingBottom() } }
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { dock = $0 }
                    }
                    .swipeBack(true) { model.workoutOpen = false }
                    // The keyboard's Next reaching a closed card opens it.
                    .onChange(of: focus) { _, id in
                        guard let id, let exercise = active.exercises.first(where: { ex in ex.sets.contains { id.hasPrefix($0.id) } }), exercise.id != expanded else { return }
                        Motion.tap { opened = exercise.id }
                    }
                    // As the PWA's moveOn: a set done in a card with more to do shows its next set; the card's last set
                    // hands over to the next card with sets to do (also one opened by hand; the keyboard goes with it)
                    // and the page goes to it, or after the last one up to Finish. Each side counts here: L done shows R.
                    // By exercise, not place: arranging the cards moved the counts and read as a set done.
                    .onChange(of: Dictionary(active.exercises.map { ($0.id, $0.sets.filter(\.done).count) }, uniquingKeysWith: { first, _ in first })) { was, now in
                        guard Set(was.keys) == Set(now.keys), let card = active.exercises.first(where: { (now[$0.id] ?? 0) > (was[$0.id] ?? 0) }) else { return }
                        if let set = card.sets.first(where: { !$0.done }) {
                            if focus == nil { reveal(proxy, set.id, anchor: nil) } // while typing, the keyboard keeps its set in view
                            return
                        }
                        focus = nil
                        // Its ✓ pops (Motion.normal), then a beat (Motion.fast), then the next card opens as this one closes.
                        DispatchQueue.main.asyncAfter(deadline: .now() + (Motion.still ? 0 : Motion.normal + Motion.fast)) {
                            let next = model.training.active?.exercises.first { $0.doneCount < $0.setCount }?.id
                            Motion.tap {
                                if opened == card.id { opened = nil }
                                following = next
                            }
                            reveal(proxy, next ?? Self.top, anchor: .top)
                        }
                    }
                    // Anything else that changes which card the workout is on (a set undone, an exercise added, removed
                    // or arranged) shows at once; a card just finished hands over above, once its ✓ has popped.
                    .onChange(of: current) { was, now in
                        let finished = active.exercises.first { $0.id == was }.map { $0.doneCount >= $0.setCount } ?? false
                        if !finished { Motion.tap { following = now } }
                    }
            }
            .onAppear { following = current }
            // Kept for later, the screen stays made (made again on Continue it cost ~30 ms: build 107) but comes back as
            // it did made anew: on the workout's card, not arranging, the keyboard down.
            .onChange(of: shown) { _, on in
                guard !on else { return }
                focus = nil; opened = nil; arranging = false; following = current
            }
            // The motion check's moves, as the taps that make them.
            .onChange(of: model.bench) { _, move in
                switch move {
                case .card(let id)?: Motion.tap { opened = id }
                case .focus(let id)?: focus = id
                case .arrange(true)?: focus = nil; Motion.tap { opened = nil; arranging = true }
                case .arrange(false)?: Motion.tap { arranging = false }
                case nil: break
                }
            }
            .onDisappear { focus = nil }
        }
    }

    /// The page's top, where Finish is.
    private static let top = "top"

    /// Glides the page to it (nil anchor: just enough), once the cards have their new heights.
    private func reveal(_ proxy: ScrollViewProxy, _ id: String, anchor: UnitPoint?) {
        DispatchQueue.main.async {
            if AB.uikitList { CardList.reveal(id, top: anchor == .top) } else { Motion.tap { proxy.scrollTo(id, anchor: anchor) } }
        }
    }

    /// The header, the progress bar, then the cards (or the list being arranged) and Add exercise.
    private func content(_ active: Session, expanded: String?, current: String?, previous: Session?) -> some View {
        let done = active.exercises.doneCount, planned = active.exercises.plannedCount
        let unit = model.training.settings.unit
        return VStack(alignment: .leading, spacing: 0) {
            header(active, done: done, planned: planned)
            Bar(value: Double(done) / Double(max(1, planned)))
                .padding(.top, Space.s3)
                .accessibilityLabel("Workout completion").accessibilityValue("\(done) of \(planned) sets")
            Group {
                if arranging {
                    arrangeList(active, current: current, previous: previous, unit: unit)
                } else {
                    cards(active, expanded: expanded, current: current, previous: previous, unit: unit)
                }
            }
            .padding(.top, Space.s4)
        }
        .padding(.horizontal, Space.s4).padding(.top, Space.s4).padding(.bottom, Space.s6)
        // The top with its padding: on the header, going up to Finish stopped 16 short of the page's top.
        .id(Self.top)
        .frame(maxWidth: Size.column).frame(maxWidth: .infinity)
    }

    /// The page as CardList's rows: the header and bar, each card, Add exercise; spaced as `content` spaces them, each
    /// row keeping its own share of the gap (a card's shadow stays inside its row, whose edge uncovers it as it grows).
    private func rows(_ active: Session, expanded: String?, current: String?, previous: Session?) -> [CardList.Row] {
        let done = active.exercises.doneCount, planned = active.exercises.plannedCount
        let unit = model.training.settings.unit
        let heading = VStack(alignment: .leading, spacing: 0) {
            header(active, done: done, planned: planned)
            Bar(value: Double(done) / Double(max(1, planned)))
                .padding(.top, Space.s3)
                .accessibilityLabel("Workout completion").accessibilityValue("\(done) of \(planned) sets")
        }
        var rows = [CardList.Row(id: Self.top, value: "\(active.name) \(done) \(planned)", view: column(heading, Space.s4, Space.s4 - Space.s1), pinned: true)]
        for (index, exercise) in active.exercises.enumerated() where !AB.emptyScreens {
            let card = card(index, exercise, active, expanded: expanded, current: current, previous: previous, unit: unit)
            if AB.uikitCard {
                rows.append(CardList.Row(id: exercise.id, value: card, view: AnyView(EmptyView()), card: card))
            } else {
                rows.append(CardList.Row(id: exercise.id, value: card, view: column(card.equatable(), Space.s1, Space.s3 - Space.s1)))
            }
        }
        rows.append(CardList.Row(id: "add", value: 0, view: column(addExercise, Space.s1, Space.s6)))
        return rows
    }

    /// A CardList row in the page's column, with its share of the gaps above and below.
    private func column(_ view: some View, _ top: CGFloat, _ bottom: CGFloat) -> AnyView {
        AnyView(view.padding(.top, top).padding(.bottom, bottom).padding(.horizontal, Space.s4)
            .frame(maxWidth: Size.column).frame(maxWidth: .infinity))
    }

    private func arrangeList(_ active: Session, current: String?, previous: Session?, unit: TrackCore.Settings.Unit) -> some View {
        // The held row settles from the finger itself (ArrangeList), so the move shows at once.
        ArrangeList(items: active.exercises, name: \.name, glides: rows, onMove: { from, to in
            model.update(moving: false) { training in
                guard let moved = training.active?.exercises.moved(from, to: to) else { return }
                training.active?.exercises = moved
            }
        }) { exercise in
            HStack(spacing: Space.s3) {
                ExerciseCard.number((active.exercises.firstIndex { $0.id == exercise.id } ?? 0) + 1, current: exercise.id == current)
                VStack(alignment: .leading, spacing: 0) {
                    Text(exercise.name).type(.t16).foregroundStyle(Palette.text)
                    Text(ExerciseCard.detail(exercise, last: previous?.match(exercise), unit)).type(.t14).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    @ViewBuilder private func cards(_ active: Session, expanded: String?, current: String?, previous: Session?, unit: TrackCore.Settings.Unit) -> some View {
        if AB.lazyCards {
            LazyVStack(spacing: Space.s3) { cardList(active, expanded: expanded, current: current, previous: previous, unit: unit) }
        } else {
            VStack(spacing: Space.s3) { cardList(active, expanded: expanded, current: current, previous: previous, unit: unit) }
        }
    }

    private func card(_ index: Int, _ exercise: Exercise, _ active: Session, expanded: String?, current: String?, previous: Session?,
                      unit: TrackCore.Settings.Unit) -> ExerciseCard {
        let settings = model.training.settings
        let muscle = muscleLabel(LiftTable.muscles(for: exercise.name, choices: settings.lifts ?? [:]))
        let here: String? = focus.flatMap { id in exercise.sets.contains { id.hasPrefix($0.id) } ? id : nil }
        return ExerciseCard(exercise: exercise, number: index + 1, current: current == exercise.id, open: expanded == exercise.id, unit: unit,
                            autoLog: settings.logSets != .manual, bests: model.bests,
                            last: previous?.match(exercise),
                            restSeconds: settings.restSeconds, muscle: muscle, focus: $focus, focusHere: here,
                            onOpen: { Motion.tap { opened = exercise.id } },
                            onOptions: { focus = nil; model.present(ExerciseOptions(exerciseId: exercise.id)) },
                            onArrange: active.exercises.count < 2 ? nil : { focus = nil; Motion.tap { opened = nil; arranging = true } })
    }

    @ViewBuilder private func cardList(_ active: Session, expanded: String?, current: String?, previous: Session?, unit: TrackCore.Settings.Unit) -> some View {
        ForEach(Array(active.exercises.enumerated()), id: \.element.id) { index, exercise in
            card(index, exercise, active, expanded: expanded, current: current, previous: previous, unit: unit)
                .equatable()
                // A card moving as another opens or closes moves as one piece: without it every text and surface in
                // it got its own animated frame, each frame, on every card below the one that changed.
                .geometryGroup(when: !AB.noGeometryGroup)
                .id(exercise.id)
                .matched(exercise.id, in: AB.noGlide ? nil : rows)
                .transition(.row)
        }
        addExercise
    }

    private var addExercise: some View {
        Button {
            focus = nil
            model.present(ExercisePicker { name in model.update { $0.active?.exercises.append(Exercise.new(named: name)) } }, tall: true)
        } label: { Label { Text("Add exercise") } icon: { Icon.plus.image(IconSize.medium) } }
        .buttonStyle(SecondaryStyle())
    }

    /// ‹, the name over the time and sets (it opens the options), Finish (Done while arranging).
    private func header(_ active: Session, done: Int, planned: Int) -> some View {
        HStack(spacing: Space.s3) {
            RoundButton(icon: .back, label: "Keep for later") { model.workoutOpen = false }
                .accessibilityHint("Keeps the workout going for later").accessibilityIdentifier("keep-for-later")
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                focus = nil
                model.present(WorkoutOptions(arrange: { Motion.tap { arranging = true } }))
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
                    Button("Done") { Motion.tap { arranging = false } }.buttonStyle(SecondaryStyle(hug: true))
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
        HStack(spacing: 0) {
            // The rest's time takes the free room (with its own room round it); with no rest the pill hugs its buttons,
            // Next as near its edge as Done is to the other.
            RestTimer(compact: true)
            HStack(spacing: Space.s2) {
                if let focus, let index = fields.firstIndex(of: focus), index + 1 < fields.count {
                    Button("Next") { self.focus = fields[index + 1] }.buttonStyle(SecondaryStyle(hug: true))
                }
                Button("Done") { focus = nil }.buttonStyle(PrimaryStyle(compact: true))
            }
        }
        .padding(Space.s1)
        .raised(.float, .pill)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, Space.s4).padding(.bottom, Space.s2)
    }
}

private extension View {
    /// The workout's haptics: an exercise added, removed or arranged; a set done (or undone), each side of a pair too.
    func feedback(_ active: Session) -> some View {
        sensoryFeedback(.selection, trigger: active.exercises.map(\.id))
            .sensoryFeedback(trigger: active.exercises.reduce(0) { $0 + $1.sets.filter(\.done).count }) { was, now in now > was ? .impact(weight: .medium) : .selection }
    }
}

/// One exercise (the PWA's card). Closed: its number, name and "1 of 3 sets · last 60×8", tapped to open. Open: its
/// name over its muscle and rest, ⋯ for its options (swipe the name left and ⋯ becomes a red ✕ that removes it, with
/// Undo), the Set · Last · kg · Reps · RIR · Done columns, a row per set and Add set.
struct ExerciseCard: View, Equatable {
    @Environment(AppModel.self) private var model
    let exercise: Exercise
    let number: Int
    /// The exercise the workout is on: its number is green, as the next set's is (the PWA's .tile.green).
    let current: Bool
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
    /// Holding the closed card arranges the exercises, as an iPhone list's row (nil: only one exercise).
    let onArrange: (() -> Void)?
    @State private var armed = false
    /// The hold that just arranged: its lift isn't a tap.
    @State private var held = false

    /// One card either way (the PWA's resize): its line swaps at once, and what's under it is uncovered as the edge
    /// grows, or closed over as it shrinks. Nothing fades: the two lines crossing showed the name twice (owner, build 71).
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if open { heading.transition(.identity) } else { closed.transition(.identity) }
            if AB.builtSets {
                // Shut, it keeps its height for itself and lays out none, as the transition's leaving part does.
                sets.fixedSize(horizontal: false, vertical: true).uncovered(open)
                    .frame(height: open ? nil : 0, alignment: .top)
                    .allowsHitTesting(open).accessibilityHidden(!open)
            } else if open { sets.transition(.uncover) }
        }
        .pad()
        .raised()
        .opacity(pressed ? Press.dim : 1)
        .onChange(of: open) { if !open { armed = false } }
    }

    @State private var pressed = false

    private var closed: some View {
        Button { if held { held = false } else { onOpen() } } label: {
            HStack(spacing: Space.s3) {
                Self.number(number, current: current)
                VStack(alignment: .leading, spacing: 0) {
                    Text(exercise.name).type(.t16).foregroundStyle(Palette.text).multilineTextAlignment(.leading)
                    Text(Self.detail(exercise, last: last, unit)).type(.t14).monospacedDigit().foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon.down.image(IconSize.medium).foregroundStyle(Palette.muted)
            }
            .contentShape(Rectangle())
        }
        // The whole card darkens when pressed, as a card button does (CardStyle), though its edge is outside the button.
        .buttonStyle(Press { pressed = $0 })
        .simultaneousGesture(LongPressGesture(minimumDuration: SwipeToArm.hold).onEnded { _ in
            guard let onArrange else { return }
            held = true
            onArrange()
        }, isEnabled: onArrange != nil)
        .sensoryFeedback(.impact(weight: .medium), trigger: held) { _, now in now }
        .accessibilityValue("Closed")
        .accessibilityAction(named: "Arrange exercises") { onArrange?() }
    }

    private var heading: some View {
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
    }

    private var sets: some View {
        let labels = exercise.setLabels
        let next = exercise.sets.firstIndex { !$0.done }
        return VStack(alignment: .leading, spacing: 0) {
            SetColumns {
                Text("Set"); Text("Last"); Text(unit.rawValue); Text("Reps"); Text("RIR"); Text("Done")
            }
            .type(.t12).foregroundStyle(Palette.muted)
            .padding(.top, Space.s4)
            .accessibilityHidden(true)
            VStack(spacing: Space.s2) {
                ForEach(AB.noRows ? [] : Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                    SetRow(exercise: exercise, set: set, label: labels[index], next: index == next, unit: unit, autoLog: autoLog, bests: bests,
                           last: last.flatMap { $0.sets.indices.contains(index) ? $0.sets[index] : nil },
                           focus: focus,
                           focused: focusHere.flatMap { $0.hasPrefix("\(set.id).") ? String($0.dropFirst(set.id.count + 1)) : nil })
                        .id(set.id) // what the keyboard scrolls to (SetKeyboard)
                        .transition(.row)
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
    }

    /// Saving a set redraws only its card, not every card in the workout (the keyboard focus updates each by itself).
    static func == (a: Self, b: Self) -> Bool {
        a.exercise == b.exercise && a.number == b.number && a.current == b.current && a.open == b.open && a.unit == b.unit && a.autoLog == b.autoLog
            && a.bests.id == b.bests.id && a.last == b.last && a.restSeconds == b.restSeconds && a.muscle == b.muscle && a.focusHere == b.focusHere
            && (a.onArrange == nil) == (b.onArrange == nil) // a second exercise lets the first one's hold arrange
    }

    /// A closed card's (and its arranging row's) number tile.
    static func number(_ number: Int, current: Bool) -> some View {
        Text("\(number)").type(.t16).monospacedDigit().foregroundStyle(current ? Palette.accent : Palette.text)
            .frame(width: Size.tile, height: Size.tile).raised(.control, .inner)
    }

    /// "1 of 3 sets · last 60×8": done of the sets as counted, and last time's first set.
    static func detail(_ exercise: Exercise, last: Exercise?, _ unit: TrackCore.Settings.Unit) -> String {
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
