import SwiftUI
import TrackCore

/// After Finish, as the website's completion screen: WORKOUT SAVED, the totals against last time, the best set, one
/// observation, then what it earned (records, achievements, rank ups, a level, XP). Continue goes to Progress, where
/// the level bar fills; View workout opens it in History. Anything earned gets the success haptic, then a heavier one.
struct CompletionView: View {
    @Environment(AppModel.self) private var model
    let finished: Finished
    @State private var shown = false
    @State private var landed = false
    @State private var allAwards = false

    var body: some View {
        let unit = model.training.settings.unit
        if let recap = model.training.sessions.recap(of: finished.id) {
            let awards = (recap.session.questAwards ?? []).compactMap { award in Quest.all.first { $0.id == award.questId }?.title }
            let celebrate = finished.leveledUp || !recap.records.isEmpty || !awards.isEmpty || !finished.rankUps.isEmpty
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.primaryText)
                            .frame(width: 60, height: 60).background(Circle().fill(Palette.primary))
                            .scaleEffect(shown ? 1 : 0.5).opacity(shown ? 1 : 0)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WORKOUT SAVED").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(Palette.accent)
                            Text("Nice workout!").font(.largeTitle.weight(.bold)).foregroundStyle(Palette.text)
                            (Text(recap.session.name).bold().foregroundStyle(Palette.text) + Text(" is safely in your history."))
                                .font(.subheadline).foregroundStyle(Palette.muted)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metric("Volume", "\(weight(recap.volume, unit)) \(unit.rawValue)", note: volumeNote(recap.volumeDelta, unit))
                        metric("Sets", "\(recap.sets)")
                        metric("Reps", "\(recap.reps)")
                        metric("Time", trainingDuration(recap.minutes))
                    }
                    if let best = recap.best {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Best set").font(.subheadline).foregroundStyle(Palette.muted)
                            Text(best.exercise).font(.headline).foregroundStyle(Palette.text)
                            Text("\(TrainingSet.display(kg: best.set.kg, unit: unit)) \(unit.rawValue) × \(best.set.reps ?? 0) · RIR \(best.set.rir ?? 0)"
                                 + (best.set.side.map { $0 == .left ? " · Left" : " · Right" } ?? ""))
                                .font(.subheadline).foregroundStyle(Palette.text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16).glass()
                    }
                    Text(recap.observation).font(.body).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                    highlights(recap, awards: awards)
                }
                .padding(24).padding(.top, 12)
                .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 12)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    Button("Continue") { model.finished = nil }.buttonStyle(PrimaryButtonStyle())
                    Button { let session = recap.session; model.finished = nil; model.tab = .history
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { model.history = session }
                    } label: { Label("View workout", systemImage: "arrow.up.right").labelStyle(TrailingIcon()) }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text).frame(minHeight: 44)
                }
                .padding(.horizontal, 24).padding(.bottom, 8).frame(maxWidth: 560)
            }
            .background(Backdrop())
            .sensoryFeedback(.success, trigger: shown) { _, now in now }
            .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: landed) { _, now in now && celebrate }
            .onAppear {
                withAnimation(.smooth(duration: 0.5).delay(0.1)) { shown = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { landed = true }
            }
        }
    }

    private func metric(_ label: String, _ value: String, note: (String, Color)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline).foregroundStyle(Palette.muted)
            Text(value).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.7)
            if let note { Text(note.0).font(.caption.weight(.semibold)).foregroundStyle(note.1) }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading).padding(14).glass(radius: 18)
    }

    private func volumeNote(_ delta: Double?, _ unit: TrackCore.Settings.Unit) -> (String, Color) {
        guard let delta else { return ("First result", Palette.muted) }
        if delta == 0 { return ("Same as last", Palette.muted) }
        return ("\(delta > 0 ? "+" : "−")\(weight(abs(delta), unit)) vs last", delta > 0 ? Palette.accent : Palette.danger)
    }

    /// Records, achievements (three, then "+N more"), rank ups, a new level and the XP, as glass chips.
    private func highlights(_ recap: Recap, awards: [String]) -> some View {
        let hidden = allAwards ? 0 : max(0, awards.count - 3)
        return FlowLayout(spacing: 8) {
            if !recap.records.isEmpty { chip(count(recap.records.count, "new record"), icon: "trophy") }
            ForEach(awards.prefix(awards.count - hidden), id: \.self) { chip($0, icon: "rosette") }
            if hidden > 0 { Button("+\(hidden) more") { withAnimation(.smooth) { allAwards = true } }.font(.subheadline.weight(.semibold)).padding(.horizontal, 10) }
            ForEach(finished.rankUps, id: \.self) { chip($0, icon: "medal") }
            if finished.leveledUp { chip("Level \(finished.level)", icon: "star.fill") }
            if finished.xp > 0 { chip("+\(finished.xp) XP", icon: nil, accent: true) }
        }
    }

    private func chip(_ text: String, icon: String?, accent: Bool = false) -> some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.subheadline.weight(.semibold)).foregroundStyle(accent ? Palette.accent : Palette.text)
        .padding(.horizontal, 12).frame(minHeight: 36).glass(radius: 18, fill: Palette.control, lifted: false)
    }
}

/// "View workout ↗": the icon after the title.
struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 4) { configuration.title; configuration.icon } }
}

/// Chips that wrap onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing; line = max(line, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; line = max(line, size.height)
        }
    }
}
