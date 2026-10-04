import SwiftUI
import TrackCore

/// The active workout, as on the website: ‹ (or a swipe in from the left edge) keeps it for later, the name opens its
/// options, Finish; the progress bar; a one-line guide until the first workout is finished; a card per exercise (hold
/// a name and drag to move it); Add exercise; and the rest timer floating at the bottom. The keyboard's Next walks
/// weight → reps → RIR → next set.
struct WorkoutView: View {
    @Environment(AppModel.self) private var model
    @State private var addingExercise = false
    @State private var options = false
    @State private var dragging: String?
    @State private var box = ReorderBox()
    /// How far the page is pulled right by the edge swipe.
    @State private var pull: CGFloat = 0
    @State private var width: CGFloat = 400
    @FocusState private var focus: String?

    var body: some View {
        if let active = model.training.active {
            let fields = active.exercises.flatMap { exercise in exercise.sets.flatMap { ["\($0.id).kg", "\($0.id).reps", "\($0.id).rir"] } }
            let total = active.exercises.reduce(0) { $0 + $1.sets.count }
            let bests = model.bests
            NavigationStack {
                ScrollView {
                    VStack(spacing: 12) {
                        Color.clear.frame(height: 0).id("top")
                        ProgressView(value: Double(active.completedSets.count), total: Double(max(total, 1)))
                            .tint(Palette.primary).scaleEffect(x: 1, y: 1.6, anchor: .center)
                            .animation(.smooth, value: active.completedSets.count)
                            .padding(.bottom, 4)
                        if model.training.sessions.isEmpty {
                            Text((model.training.settings.logSets == .manual ? "Tap ✓ when a set is done." : "Fill in a set’s numbers down to RIR to log it, or tap ✓ to repeat last time.")
                                 + " Swipe a set left to delete it.")
                                .font(.footnote).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(active.exercises) { exercise in
                            ExerciseCard(exercise: exercise, unit: model.training.settings.unit, autoLog: model.training.settings.logSets != .manual,
                                         box: box, bests: bests, focus: $focus,
                                         focusHere: focus.flatMap { id in exercise.sets.contains { id.hasPrefix($0.id) } ? id : nil },
                                         dragging: $dragging).equatable()
                        }
                        Button { addingExercise = true } label: { Label("Add exercise", systemImage: "plus") }
                            .font(.body.weight(.semibold)).foregroundStyle(Palette.text).frame(minHeight: 44)
                            .buttonStyle(PressStyle())
                            .id("bottom")
                    }
                    .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
                    // While an exercise is held the cards wait unseen, moved without animating (ReorderList shows the moves).
                    .transaction { if dragging != nil { $0.animation = nil } }
                    .animation(.smooth(duration: 0.3), value: active.exercises.map(\.id))
                    .animation(.smooth(duration: 0.3), value: active.exercises.map { $0.sets.allSatisfy(\.done) }) // a card folding moves the rest
                    .opacity(dragging == nil ? 1 : 0).allowsHitTesting(dragging == nil)
                    .sensoryFeedback(.selection, trigger: active.exercises.map(\.id))
                }
                .scrollDisabled(dragging != nil).onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { box.viewport = $0 }
                // A drag the system cancelled leaves the list up: a tap puts the cards back.
                .overlay { if let held = dragging { ReorderList(exercises: active.exercises, held: held, box: box).transition(.opacity)
                    .onTapGesture { withAnimation(.smooth(duration: 0.3)) { dragging = nil } } } }
                .scrollDismissesKeyboard(.interactively)
                .background(Backdrop())
                .navigationTitle(active.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar(active, done: active.completedSets.count, total: total, fields: fields) }
                .safeAreaInset(edge: .bottom) { RestCapsule() }
            }
            .onDrop(of: [.text], delegate: drop(active))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { box.height = $0 }
            .background(Backdrop())
            .offset(x: pull)
            .shadow(color: .black.opacity(pull > 0 ? 0.25 : 0), radius: 20)
            .overlay(alignment: .leading) { edgeSwipe }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onAppear { dragging = nil; pull = 0 }
            .task { try? await Task.sleep(for: .seconds(0.6)); model.workoutCovers = true }
            .onDisappear { model.workoutCovers = false }
            .sheet(isPresented: $addingExercise) {
                ExercisePicker { name in model.update { $0.active?.exercises.append(Exercise.new(named: name)) } }
            }
            .sheet(isPresented: $options) { WorkoutOptions().trackOverlays() }
        }
    }

    private func drop(_ active: Session) -> ReorderDrop {
        ReorderDrop(ids: active.exercises.map(\.id), box: box, dragging: $dragging, scroll: { edge in
            withAnimation(.smooth(duration: 0.6)) { box.scroll?(edge) }
        }, move: { from, to in
            model.update { training in
                guard let moved = training.active?.exercises.moved(from, to: to) else { return }
                training.active?.exercises = moved
            }
        })
    }

    /// The website's swipe back: from the left edge, the page follows the finger; past a third (or a flick) it slides
    /// away and the workout is kept for later, otherwise it settles back.
    private var edgeSwipe: some View {
        Color.clear.frame(width: 16).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onChanged { pull = max(0, $0.translation.width); if model.workoutCovers { model.workoutCovers = false } }
                .onEnded { drag in
                    guard drag.translation.width > width / 3 || drag.predictedEndTranslation.width > width / 2 else {
                        withAnimation(.smooth(duration: 0.25)) { pull = 0 } completion: { model.workoutCovers = true }
                        return
                    }
                    withAnimation(.smooth(duration: 0.25)) { pull = width } completion: {
                        var instant = Transaction()
                        instant.disablesAnimations = true
                        withTransaction(instant) { model.workoutOpen = false }
                    }
                })
    }

    @ToolbarContentBuilder private func toolbar(_ active: Session, done: Int, total: Int, fields: [String]) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { model.workoutOpen = false } label: { Image(systemName: "chevron.left").foregroundStyle(Palette.text) }
                .accessibilityLabel("Keep for later")
        }
        ToolbarItem(placement: .principal) {
            Button { options = true } label: {
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        Text(active.name).font(.headline).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
                    }
                    .foregroundStyle(Palette.text)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(elapsed(active.startedAt, context.date)) · \(done) of \(count(total, "set"))")
                            .font(.caption).monospacedDigit().foregroundStyle(Palette.muted)
                    }
                }
            }
            .accessibilityLabel("\(active.name): workout options")
        }
        ToolbarItem(placement: .topBarTrailing) {
            if #available(iOS 26, *) {
                Button("Finish") { model.finish() }.fontWeight(.bold).foregroundStyle(Palette.primaryText)
                    .buttonStyle(.glassProminent).tint(Palette.primary).accessibilityLabel("Finish workout")
            } else {
                Button("Finish") { model.finish() }.fontWeight(.bold).foregroundStyle(Palette.primaryText)
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(Palette.primary)
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            if let focus, let index = fields.firstIndex(of: focus), index + 1 < fields.count {
                Button("Next") { self.focus = fields[index + 1] }.fontWeight(.semibold)
            }
            Button("Done") { focus = nil }.fontWeight(.semibold)
        }
    }
}

/// The workout's options, as the website's: rename, switch kg ⇄ lb, start a rest, discard the workout.
struct WorkoutOptions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let active = model.training.active
        let split = model.training.splits.first { $0.id == active?.splitId }
        let unit = model.training.settings.unit
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("Workout options").font(.title3.weight(.bold)).foregroundStyle(Palette.text)
                Spacer()
                GlassCircleButton(icon: "xmark", label: "Close") { dismiss() }.padding(.top, -6).padding(.trailing, -6)
            }
            Text(active?.name ?? "").font(.subheadline).foregroundStyle(Palette.muted).padding(.bottom, 6)
            option(split != nil ? "Rename split" : "Rename workout", "pencil") {
                dismiss()
                model.naming = Naming(title: split != nil ? "Rename split" : "Rename workout", name: active?.name ?? "",
                                      label: split != nil ? "Split name" : "Workout name", action: "Save name") { name in model.update { $0.active?.name = name } }
            }
            option(unit == .kg ? "Use pounds (lb)" : "Use kilograms (kg)", "arrow.left.arrow.right") {
                model.update { $0.settings.unit = unit == .kg ? .lb : .kg }
            }
            option("Start rest timer", "timer") { model.startRest(); dismiss() }
            option("Discard workout", "trash", danger: true) { dismiss(); model.discard() }
        }
        .padding(24)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    private func option(_ title: String, _ icon: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(danger ? Palette.danger : Palette.text)
                .frame(maxWidth: .infinity, minHeight: 48)
                .glass(radius: 24, fill: danger ? .clear : Palette.control, lifted: false)
        }
        .buttonStyle(PressStyle())
    }
}
