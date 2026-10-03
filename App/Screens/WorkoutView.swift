import SwiftUI
import TrackCore

/// The active workout, as on the website: ‹ keeps it for later, the name opens its options, Finish (Done while
/// arranging); the progress bar; a one-line guide until the first workout is finished; a card per exercise; Add
/// exercise; and the rest timer floating at the bottom. The keyboard's Next walks weight → reps → RIR → next set.
struct WorkoutView: View {
    @Environment(AppModel.self) private var model
    @State private var addingExercise = false
    @State private var options = false
    @FocusState private var focus: String?

    var body: some View {
        if let active = model.training.active {
            let fields = active.exercises.flatMap { exercise in exercise.sets.flatMap { ["\($0.id).kg", "\($0.id).reps", "\($0.id).rir"] } }
            let total = active.exercises.reduce(0) { $0 + $1.sets.count }
            let bests = RecordBests(model.training.sessions)
            NavigationStack {
                ScrollView {
                    VStack(spacing: 12) {
                        ProgressView(value: Double(active.completedSets.count), total: Double(max(total, 1)))
                            .tint(Palette.primary).scaleEffect(x: 1, y: 1.6, anchor: .center)
                            .animation(.smooth, value: active.completedSets.count)
                            .padding(.bottom, 4)
                        if model.training.sessions.isEmpty {
                            Text((model.training.settings.logSets == .manual ? "Tap ✓ when a set is done." : "Change a set’s numbers to log it, or tap ✓ to repeat last time.")
                                 + " Swipe a set left to delete it.")
                                .font(.footnote).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(Array(active.exercises.enumerated()), id: \.element.id) { index, exercise in
                            ExerciseCard(exercise: exercise, first: index == 0, last: index == active.exercises.count - 1, bests: bests, focus: $focus)
                        }
                        Button { addingExercise = true } label: { Label("Add exercise", systemImage: "plus") }
                            .font(.body.weight(.semibold)).foregroundStyle(Palette.text).frame(minHeight: 44)
                            .buttonStyle(PressStyle())
                    }
                    .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
                    .animation(.smooth(duration: 0.3), value: active.exercises.map(\.id))
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Backdrop())
                .navigationTitle(active.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar(active, done: active.completedSets.count, total: total, fields: fields) }
                .safeAreaInset(edge: .bottom) { RestCapsule() }
            }
            .sheet(isPresented: $addingExercise) {
                ExercisePicker { name in model.update { $0.active?.exercises.append(Exercise.new(named: name)) } }
            }
            .sheet(isPresented: $options) { WorkoutOptions().trackOverlays() }
        }
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
            if model.arrangingExercises {
                Button("Done") { withAnimation(.smooth) { model.arrangingExercises = false } }.fontWeight(.semibold)
            } else if #available(iOS 26, *) {
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

/// The workout's options, as the website's: rename, arrange exercises, switch kg ⇄ lb, start a rest, discard the
/// workout, delete its split.
struct WorkoutOptions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false

    var body: some View {
        let active = model.training.active
        let split = model.training.splits.first { $0.id == active?.splitId }
        let unit = model.training.settings.unit
        VStack(alignment: .leading, spacing: 10) {
            Text("Workout options").font(.title3.weight(.bold)).foregroundStyle(Palette.text)
            Text(active?.name ?? "").font(.subheadline).foregroundStyle(Palette.muted).padding(.bottom, 6)
            option(split != nil ? "Rename split" : "Rename workout", "pencil") { renaming = true }
            option(model.arrangingExercises ? "Finish arranging" : "Arrange exercises", "arrow.up") {
                withAnimation(.smooth) { model.arrangingExercises.toggle() }
                dismiss()
            }
            option(unit == .kg ? "Use pounds (lb)" : "Use kilograms (kg)", "arrow.left.arrow.right") {
                model.update { $0.settings.unit = unit == .kg ? .lb : .kg }
            }
            option("Start rest timer", "timer") { model.startRest(); dismiss() }
            option("Discard workout", "trash", danger: true) { dismiss(); later { model.discard() } }
            if let split {
                option("Delete split", "trash", danger: true) { dismiss(); later { model.deleteSplit(split) } }
            }
        }
        .padding(24)
        .presentationDetents([.height(split != nil ? 470 : 410)])
        .presentationBackground(.ultraThinMaterial)
        .sheet(isPresented: $renaming) {
            NameSheet(title: split != nil ? "Rename split" : "Rename workout", name: active?.name ?? "", action: "Save") { name in
                model.update { $0.active?.name = name }
            }
        }
    }

    /// After this sheet has gone, so the dialog shows over the workout.
    private func later(_ action: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action) }

    private func option(_ title: String, _ icon: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(danger ? Palette.danger : Palette.text)
                .frame(maxWidth: .infinity, minHeight: 48)
                .glass(radius: 24, fill: danger ? .clear : Palette.control, lifted: false)
        }
        .buttonStyle(PressStyle())
    }
}
