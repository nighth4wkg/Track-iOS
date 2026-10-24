import SwiftUI
import TrackCore

/// After Finish, as the PWA's: "Nice workout!" over its name and day, the XP card (the level ring, +XP rolling up, Level
/// up, what's left to the next level and its bar), Duration · Volume · Streak tiles, each exercise's best set (new
/// records marked), and Continue docked at the bottom.
struct CompletionView: View {
    @Environment(AppModel.self) private var model
    let finished: Finished
    @State private var shown = false

    var body: some View {
        let sessions = model.training.sessions
        let unit = model.training.settings.unit
        if let session = sessions.first(where: { $0.id == finished.id }), let at = session.finishedAt {
            let level = Experience.progress(of: sessions)
            let before = Dictionary(sessions.filter { $0.id != session.id }.personalRecords.map { ($0.name, $0.kg) }, uniquingKeysWith: max)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Workout complete").type(.t14).foregroundStyle(Palette.muted)
                    Text("Nice workout!").type(.t32).foregroundStyle(Palette.text)
                    Text("\(session.name) · \(Date(timeIntervalSince1970: Double(at) / 1000).formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))")
                        .type(.t14).foregroundStyle(Palette.muted)
                    xpCard(level).padding(.top, Space.s4)
                    HStack(spacing: Space.s3) {
                        tile("Duration", "\(session.minutes)", "min")
                        tile("Volume", weight(session.volume, unit), unit.rawValue)
                        tile("Streak", "\(sessions.weeklyStreak(at: at))", "wk")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s3)
                    let bests = session.exercises.compactMap { exercise -> (name: String, set: TrainingSet, fresh: Bool)? in
                        guard let set = exercise.sets.filter(\.isValid).max(by: { ($0.kg ?? 0, $0.reps ?? 0) < ($1.kg ?? 0, $1.reps ?? 0) }) else { return nil }
                        return (exercise.name, set, before[exercise.name].map { (set.kg ?? 0) > $0 } ?? false)
                    }
                    if !bests.isEmpty {
                        Text("Best sets").type(.t20).foregroundStyle(Palette.text).padding(.top, Space.s6)
                        RowCard {
                            ForEach(bests, id: \.name) { best in
                                Row(title: best.name) {
                                    if best.fresh { Badge(text: "New best") }
                                    Text("\(TrainingSet.display(kg: best.set.kg ?? 0, unit: unit)) \(unit.rawValue) × \(best.set.reps ?? 0)")
                                        .type(.t14).monospacedDigit().foregroundStyle(Palette.text)
                                }
                            }
                        }
                        .padding(.top, Space.s2)
                    }
                    // Room for the dock, so the last card scrolls clear of it.
                    Color.clear.frame(height: Size.primary + Space.s4)
                }
                .padding(.horizontal, Space.s4).padding(.top, Space.s4).padding(.bottom, Space.s6)
                .frame(maxWidth: Measure.page).frame(maxWidth: .infinity)
                .opacity(shown ? 1 : 0).offset(y: shown ? 0 : Space.s2)
            }
            .background(Backdrop())
            .overlay(alignment: .bottom) {
                Button("Continue") { model.finished = nil }.buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
                    .frame(maxWidth: Measure.page)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
            .sensoryFeedback(.success, trigger: shown) { _, now in now }
            .onAppear { withAnimation(.smooth(duration: Motion.slow)) { shown = true } }
        }
    }

    /// The level ring with the level (rolling up on a level up), +XP rolling up from 0, and the bar to the next level.
    private func xpCard(_ level: Experience.Progress) -> some View {
        let fraction = Double(level.current) / Double(max(1, level.required))
        let levelBefore = finished.leveledUp ? level.level - 1 : level.level
        return HStack(spacing: Space.s4) {
            ZStack {
                Circle().stroke(Palette.input, lineWidth: Size.ringStroke)
                Circle().trim(from: 0, to: shown ? fraction : 0).stroke(Palette.primary, style: StrokeStyle(lineWidth: Size.ringStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("Level").type(.t12).foregroundStyle(Palette.muted)
                    Text("\(shown ? level.level : levelBefore)").type(.t28).monospacedDigit().foregroundStyle(Palette.text)
                        .contentTransition(.numericText())
                }
            }
            .frame(width: Size.levelRing, height: Size.levelRing)
            .accessibilityElement(children: .ignore).accessibilityLabel("Level \(level.level)")
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s2) {
                    Text("+\(shown ? finished.xp : 0) XP").type(.t28).monospacedDigit().foregroundStyle(Palette.accent)
                        .contentTransition(.numericText()).lineLimit(1)
                    if finished.leveledUp { Badge(text: "Level up") }
                }
                Text("\(level.required - level.current) XP to Level \(level.level + 1)").type(.t14).foregroundStyle(Palette.muted)
                RankBar(progress: shown ? fraction : 0, color: Palette.accent).padding(.top, Space.s2)
                    .accessibilityLabel("Level \(level.level + 1) progress")
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raised()
        .animation(.smooth(duration: Motion.slow).delay(Motion.standard), value: shown)
    }

    private func tile(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).type(.t14).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                Text(value).type(.t20).monospacedDigit().foregroundStyle(Palette.text)
                Text(unit).type(.t14).foregroundStyle(Palette.muted)
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .raised()
    }
}

/// "View workout ↗": the icon after the title.
struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 4) { configuration.title; configuration.icon } }
}

/// Chips that wrap onto as many lines as they need, each at most a line wide (a long one wraps its text).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing; line = max(line, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; line = max(line, size.height)
        }
    }
}
