import SwiftUI
import TrackCore

/// After Finish, as the website's completion screen (app/styles/progress-loop.css): one card on a mint glow, the
/// check with its halo over WORKOUT SAVED, then the totals in one strip (volume against last time), the best set,
/// the observation, and what it earned as chips (records, achievements, rank ups, a level, XP), with Continue and
/// View workout at the end. Its parts rise in one after another. Anything earned gets a heavier haptic.
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
            GeometryReader { screen in ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.background)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(LinearGradient(colors: [Palette.primary.mix(with: .white, by: 0.12), Palette.primary],
                                                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
                            .background(Circle().fill(Palette.primary.opacity(0.12)).padding(-8))
                            .shadow(color: Palette.primary.opacity(0.28), radius: 12, y: 10)
                            .scaleEffect(shown ? 1 : 0.75).opacity(shown ? 1 : 0)
                        VStack(spacing: 4) {
                            Text("WORKOUT SAVED").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Palette.accent)
                            Text("Nice workout!").font(.largeTitle.weight(.bold)).foregroundStyle(Palette.text)
                            Text("\(Text(recap.session.name).bold().foregroundStyle(Palette.text)) is safely in your history.")
                                .font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        .multilineTextAlignment(.center)
                        .rise(shown, 0.07)
                    }
                    .padding(.bottom, 4)
                    metrics(recap, unit).rise(shown, 0.1)
                    if let best = recap.best {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Best set").font(.footnote).foregroundStyle(Palette.muted)
                            Text(best.exercise).font(.headline).foregroundStyle(Palette.text)
                            Text("\(TrainingSet.display(kg: best.set.kg, unit: unit)) \(unit.rawValue) × \(best.set.reps ?? 0) · RIR \(best.set.rir ?? 0)"
                                 + (best.set.side.map { $0 == .left ? " · Left" : " · Right" } ?? ""))
                                .font(.footnote).monospacedDigit().foregroundStyle(Palette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 12)
                        .glass(radius: 14, fill: Palette.control, lifted: false)
                        .rise(shown, 0.13)
                    }
                    Text(recap.observation).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 12)
                        .background(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 12, topTrailingRadius: 12)
                            .fill(Palette.primary.opacity(0.09)))
                        .overlay(alignment: .leading) { Rectangle().fill(Palette.accent).frame(width: 3) }
                        .rise(shown, 0.13)
                    highlights(recap, awards: awards).frame(maxWidth: .infinity, alignment: .leading).rise(shown, 0.16)
                    VStack(spacing: 2) {
                        Button("Continue") { model.finished = nil }.buttonStyle(PrimaryButtonStyle())
                        Button { let session = recap.session; model.finished = nil; model.tab = .history
                            DispatchQueue.main.asyncAfter(deadline: .now() + Motion.sheetAway) { model.history = session }
                        } label: { Label("View workout", systemImage: "arrow.up.right").labelStyle(TrailingIcon()) }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text).frame(minHeight: 44)
                    }
                    .padding(.top, 4).rise(shown, 0.19)
                }
                .padding(16)
                .glass(radius: 24, fill: Palette.dialog)
                .padding(.horizontal, 12).padding(.vertical, 14)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
                .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14).scaleEffect(shown ? 1 : 0.985)
                .frame(minHeight: screen.size.height)
            }
            .scrollBounceBehavior(.basedOnSize) }
            .background {
                ZStack {
                    Palette.background
                    RadialGradient(colors: [Palette.primary.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.08), startRadius: 0, endRadius: 340)
                }
                .ignoresSafeArea()
            }
            .sensoryFeedback(.success, trigger: shown) { _, now in now }
            .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: landed) { _, now in now && celebrate }
            .onAppear {
                withAnimation(.smooth(duration: Motion.slow)) { shown = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { landed = true }
            }
        }
    }

    /// Volume (with the change against last time), sets, reps and time, in one strip split by hairlines.
    private func metrics(_ recap: Recap, _ unit: TrackCore.Settings.Unit) -> some View {
        let note = volumeNote(recap.volumeDelta, unit)
        return HStack(alignment: .top, spacing: 0) {
            metric("Volume", weight(recap.volume, unit), small: unit.rawValue) {
                Text(note.0).font(.caption2.weight(.semibold)).foregroundStyle(note.1 ?? Palette.muted).lineLimit(1)
                    .padding(.horizontal, note.1 == nil ? 0 : 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 8).fill((note.1 ?? .clear).opacity(0.12)))
            }.frame(minWidth: 112)
            divider
            metric("Sets", "\(recap.sets)")
            divider
            metric("Reps", "\(recap.reps)")
            divider
            metric("Time", trainingDuration(recap.minutes))
        }
        // As tall as the numbers: the hairlines between them would otherwise stretch the strip.
        .fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
        .glass(radius: 14, fill: Palette.control, lifted: false)
    }

    private var divider: some View { Rectangle().fill(Palette.hairline).frame(width: 1).padding(.vertical, 2) }

    private func metric<Note: View>(_ label: String, _ value: String, small: String? = nil, @ViewBuilder note: () -> Note = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.headline).monospacedDigit().foregroundStyle(Palette.text)
                if let small { Text(small).font(.caption).foregroundStyle(Palette.muted) }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            note()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The change against last time, tinted green when up (nil: muted, untinted).
    private func volumeNote(_ delta: Double?, _ unit: TrackCore.Settings.Unit) -> (String, Color?) {
        guard let delta else { return ("First result", nil) }
        if delta == 0 { return ("Same as last", nil) }
        // Less than last time is said plainly, not in red: a shorter session is still a workout.
        return ("\(delta > 0 ? "+" : "−")\(weight(abs(delta), unit)) vs last", delta > 0 ? Palette.accent : nil)
    }

    /// Records, achievements (three, then "+N more"), rank ups, a new level and the XP, as glass chips.
    private func highlights(_ recap: Recap, awards: [String]) -> some View {
        let hidden = allAwards ? 0 : max(0, awards.count - 3)
        return FlowLayout(spacing: 8) {
            if !recap.records.isEmpty { chip(count(recap.records.count, "new record"), icon: "trophy") }
            ForEach(awards.prefix(awards.count - hidden), id: \.self) { chip($0, icon: "rosette") }
            if hidden > 0 {
                Button { withAnimation(.smooth) { allAwards = true } } label: { chip("+\(hidden) more", icon: nil, muted: true) }.buttonStyle(PressStyle())
            }
            ForEach(finished.rankUps, id: \.self) { chip($0, icon: "medal") }
            if finished.leveledUp { chip("Level \(finished.level)", icon: "star.fill") }
            if finished.xp > 0 { chip("+\(finished.xp.formatted()) XP", icon: nil, accent: true) }
        }
    }

    private func chip(_ text: String, icon: String?, accent: Bool = false, muted: Bool = false) -> some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).foregroundStyle(Palette.accent) }
            Text(text).foregroundStyle(accent ? Palette.accent : muted ? Palette.muted : Palette.text)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 12).frame(minHeight: 34).glass(radius: 17, fill: Palette.primary.opacity(0.09), lifted: false)
    }
}

private extension View {
    /// Rises 8pt and fades in, `delay` seconds after the card.
    func rise(_ shown: Bool, _ delay: Double) -> some View {
        opacity(shown ? 1 : 0).offset(y: shown ? 0 : 8).animation(.smooth(duration: Motion.slow).delay(delay), value: shown)
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
