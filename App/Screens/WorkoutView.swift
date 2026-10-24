import SwiftUI
import TrackCore

/// The workout in progress, as the PWA's: ⌄ keeps it for later (or a swipe in from the left edge), the name opens its
/// options, Finish; the progress bar; one exercise open at a time (the first with a set to do, unless you opened
/// another), each closed one a card to tap; Add exercise; the rest timer floating at the bottom. The keyboard's Next
/// walks weight → reps → RIR → next set.
struct WorkoutView: View {
    @Environment(AppModel.self) private var model
    @State private var sheet: WorkoutSheet?
    /// The exercise opened by hand; nil follows the workout (the first with a set to do).
    @State private var opened: String?
    @State private var arranging = false
    /// Picked in the swap picker: swapped (asking first when the split has it) once the picker has gone.
    @State private var picked: (exercise: Exercise, name: String)?
    /// How far the page is pulled right by the edge swipe: live while the finger is down (gone, animated, if the
    /// system cancels the swipe), then the slide away.
    @GestureState(resetTransaction: Transaction(animation: .smooth(duration: Motion.quick))) private var drag: CGFloat = 0
    @State private var pull: CGFloat = 0
    @State private var width: CGFloat = 400
    /// The set field being typed in ("<set id>.kg", ".reps" or ".rir"), on the workout's one keyboard (SetKeyboard).
    @State private var focus: String?

    var body: some View {
        if let active = model.training.active { page(active) }
    }

    private func page(_ active: Session) -> some View {
        let fields: [String] = active.exercises.flatMap { exercise in exercise.sets.flatMap { ["\($0.id).kg", "\($0.id).reps", "\($0.id).rir"] } }
        let expanded: String? = opened.flatMap { id in active.exercises.contains { $0.id == id } ? id : nil }
            ?? (active.exercises.first { $0.doneCount < $0.setCount } ?? active.exercises.first)?.id
        let expandedDone: Bool? = active.exercises.first { $0.id == expanded }.map { $0.doneCount == $0.setCount }
        let splitId = active.splitId
        let previous: Session? = model.derived("previous \(splitId)") { sessions in
            sessions.filter { $0.splitId == splitId }.max { ($0.finishedAt ?? 0) < ($1.finishedAt ?? 0) }
        }
        return ScrollView { content(active, expanded: expanded, previous: previous) }
            .scrollDismissesKeyboard(.interactively)
            .setKeyboard($focus)
            .background(Backdrop())
            // A bar (iOS 26), not an inset: the page fades behind it.
            .safeAreaBar(edge: .bottom) {
                // While typing, one bar over the keyboard (the rest's time, Next, Done) instead of the rest timer. Without
                // the keyboard the timer sits as far from the screen's edge as the nav pill.
                Group { if focus != nil { keyboardBar(fields) } else { RestCapsule().padding(.bottom, Space.s4 - homeIndicator) } }
                    .animation(.smooth(duration: Motion.quick), value: focus == nil)
            }
            .offset(x: pull + drag)
            .shadow(color: .black.opacity(pull + drag > 0 ? 0.25 : 0), radius: Space.s4)
            .overlay(alignment: .leading) { edgeSwipe }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            // It stays built while it's left for later (MainView): opening starts it afresh, leaving ends the typing.
            .onChange(of: model.workoutOpen) { _, open in if open { pull = 0; arranging = false } else { focus = nil } }
            // The keyboard's Next reaching a closed card opens it.
            .onChange(of: focus) { _, id in
                guard let id, let exercise = active.exercises.first(where: { ex in ex.sets.contains { id.hasPrefix($0.id) } }), exercise.id != expanded else { return }
                withAnimation(.smooth(duration: Motion.standard)) { opened = exercise.id }
            }
            // A card whose last set just got done hands over to the next with sets to do (the keyboard goes with it).
            .onChange(of: expandedDone) { was, now in
                guard was == false, now == true else { return }
                withAnimation(.smooth(duration: Motion.standard)) { opened = nil }
                focus = nil
            }
            // Settled back (let go short, or cancelled): the tabs underneath needn't be drawn again.
            .onChange(of: drag) { _, now in
                if now == 0 { DispatchQueue.main.asyncAfter(deadline: .now() + Motion.slow) { if pull == 0, drag == 0, model.workoutOpen { model.workoutCovers = true } } }
            }
            .task(id: model.workoutOpen) { try? await Task.sleep(for: .seconds(Motion.screen + 0.1)); if model.workoutOpen, !Task.isCancelled { model.workoutCovers = true } }
            .task { await FrameLog.driveNext(fields) { focus = $0 } }
            .sheet(item: $sheet, onDismiss: swapPicked) { sheetView($0).trackOverlays() }
    }

    /// The header, the progress bar, then the cards (or the list being arranged) and Add exercise.
    private func content(_ active: Session, expanded: String?, previous: Session?) -> some View {
        let done = active.exercises.doneCount, planned = active.exercises.plannedCount
        let unit = model.training.settings.unit
        return VStack(alignment: .leading, spacing: 0) {
            header(active, done: done, planned: planned)
            RankBar(progress: Double(done) / Double(max(1, planned)), color: Palette.accent)
                .padding(.top, Space.s3)
                .accessibilityLabel("Workout completion").accessibilityValue("\(done) of \(planned) sets")
            if arranging {
                arrangeList(active, previous: previous, unit: unit).padding(.top, Space.s4).transition(.opacity)
            } else {
                cards(active, expanded: expanded, previous: previous, unit: unit).padding(.top, Space.s4).transition(.opacity)
            }
        }
        .padding(.horizontal, Space.s4).padding(.top, Space.s4).padding(.bottom, Space.s6)
        .frame(maxWidth: Measure.page).frame(maxWidth: .infinity)
        .animation(.smooth(duration: Motion.standard), value: active.exercises.map(\.id))
        .animation(.smooth(duration: Motion.standard), value: expanded)
        .animation(.smooth(duration: Motion.standard), value: arranging)
        .sensoryFeedback(.selection, trigger: active.exercises.map(\.id))
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
                    Text(ExerciseCard.detail(exercise, previous, unit)).type(.t14).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
        }
    }

    private func cards(_ active: Session, expanded: String?, previous: Session?, unit: TrackCore.Settings.Unit) -> some View {
        let settings = model.training.settings
        let bests = model.bests
        return VStack(spacing: Space.s3) {
            ForEach(Array(active.exercises.enumerated()), id: \.element.id) { index, exercise in
                let muscle: String = LiftTable.ranking(for: exercise.name, choices: settings.lifts ?? [:])?.groups.first ?? "Exercise"
                let here: String? = focus.flatMap { id in exercise.sets.contains { id.hasPrefix($0.id) } ? id : nil }
                ExerciseCard(exercise: exercise, number: index + 1, open: expanded == exercise.id, unit: unit,
                             autoLog: settings.logSets != .manual, bests: bests,
                             last: previous?.exercises.first { $0.id == exercise.id || $0.name == exercise.name },
                             restSeconds: settings.restSeconds, muscle: muscle, focus: $focus, focusHere: here,
                             onOpen: { withAnimation(.smooth(duration: Motion.standard)) { opened = exercise.id } },
                             onOptions: { sheet = .exercise(exercise.id) })
                    .equatable()
            }
            Button { sheet = .add } label: { Label("Add exercise", systemImage: "plus") }
                .buttonStyle(SecondaryButtonStyle())
                .id("bottom")
        }
    }

    @ViewBuilder private func sheetView(_ kind: WorkoutSheet) -> some View {
        switch kind {
        case .add: ExercisePicker { name in model.update { $0.active?.exercises.append(Exercise.new(named: name)) } }
        case .swap(let exercise): ExercisePicker(replacing: exercise.name) { picked = (exercise, $0) }
        case .workout: WorkoutOptions(arrange: { sheet = nil; withAnimation(.smooth(duration: Motion.standard)) { arranging = true } },
                                      rename: { sheet = .rename })
        case .rename: RenameWorkout()
        case .exercise(let id): ExerciseOptions(exerciseId: id, swap: { sheet = .swap($0) })
        }
    }

    private func swapPicked() {
        guard let picked else { return }
        self.picked = nil
        model.swap(picked.exercise, for: picked.name, inWorkout: true, splitId: model.training.active?.splitId)
    }

    /// ⌄, the name over the time and sets (it opens the options), Finish (Done while arranging).
    private func header(_ active: Session, done: Int, planned: Int) -> some View {
        HStack(spacing: Space.s3) {
            RoundButton(icon: "chevron.down", label: "Keep for later") { model.workoutOpen = false }
                .accessibilityHint("Keeps the workout going for later").accessibilityIdentifier("keep-for-later")
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { sheet = .workout } label: {
                VStack(spacing: 0) {
                    HStack(spacing: Space.s1) {
                        Text(active.name).type(.t16).foregroundStyle(Palette.text).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: IconSize.small, weight: .semibold)).foregroundStyle(Palette.muted)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(elapsed(active.startedAt, context.date)) · \(done)/\(planned) sets").type(.t14).monospacedDigit()
                            .foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
            }
            .buttonStyle(PressStyle())
            .layoutPriority(1)
            .accessibilityLabel("\(active.name): workout options")
            Group {
                if arranging {
                    Button("Done") { withAnimation(.smooth(duration: Motion.standard)) { arranging = false } }.buttonStyle(SecondaryButtonStyle(hug: true))
                } else {
                    Button("Finish") { model.finish() }.buttonStyle(PrimaryButtonStyle(compact: true)).accessibilityLabel("Finish workout")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: Size.control)
    }

    /// The home indicator's strip at the bottom of the screen (0 on a phone with a home button), never the keyboard.
    private var homeIndicator: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets.bottom ?? 0
    }

    /// The swipe back: from the left edge, the page follows the finger; past a third (or a flick) it slides away and
    /// the workout is kept for later, otherwise it settles back.
    private var edgeSwipe: some View {
        Color.clear.frame(width: Space.s4).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: Space.s2, coordinateSpace: .global)
                .updating($drag) { value, drag, _ in drag = max(0, value.translation.width) }
                .onChanged { _ in if model.workoutCovers { model.workoutCovers = false } }
                .onEnded { drag in
                    guard drag.translation.width > width / 3 || drag.predictedEndTranslation.width > width / 2 else { return }
                    pull = max(0, drag.translation.width)
                    withAnimation(.smooth(duration: Motion.quick)) { pull = width } completion: {
                        var instant = Transaction()
                        instant.disablesAnimations = true
                        withTransaction(instant) { model.workoutOpen = false }
                    }
                })
    }

    /// While typing: one bar just over the keyboard with the rest's time on the left, then Next (weight → reps → RIR →
    /// next set) and Done. It replaces the rest timer meanwhile, so the two never stack up.
    private func keyboardBar(_ fields: [String]) -> some View {
        let resting = (model.training.restUntil ?? 0) > nowMillis()
        return HStack(spacing: Space.s2) {
            if resting {
                RestCapsule(compact: true).padding(.leading, Space.s2)
                Spacer(minLength: Space.s2)
            }
            if let focus, let index = fields.firstIndex(of: focus), index + 1 < fields.count {
                Button("Next") { self.focus = fields[index + 1] }.buttonStyle(SecondaryButtonStyle(hug: true))
            }
            Button("Done") { focus = nil }.buttonStyle(PrimaryButtonStyle(compact: true))
        }
        .padding(Space.s1)
        .raised(.float, .pill)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, Space.s4).padding(.bottom, Space.s2)
        .transition(.opacity)
    }
}

/// The workout's one sheet at a time: what each tap opens (opening another replaces the one up).
enum WorkoutSheet: Identifiable {
    case add, workout, rename
    case swap(Exercise)
    case exercise(String)

    var id: String {
        switch self {
        case .add: "add"
        case .workout: "workout"
        case .rename: "rename"
        case .swap(let exercise): "swap \(exercise.id)"
        case .exercise(let id): "exercise \(id)"
        }
    }
}
