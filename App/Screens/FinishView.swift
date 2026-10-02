import SwiftUI
import TrackCore

/// After Finish: what the workout added up to, and the reward. A level up or a new record gets the celebration: the
/// success haptic, then a second, heavier one as the badge lands. Smooth motion, no bounce.
struct FinishView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let summary: FinishSummary
    @State private var shown = false
    @State private var landed = false

    var body: some View {
        let celebrate = summary.leveledUp || !summary.records.isEmpty || !summary.rankUps.isEmpty
        VStack(spacing: 24) {
            Spacer(minLength: 12)
            ZStack {
                Circle().fill(Palette.primary.opacity(0.16)).frame(width: 132, height: 132).scaleEffect(shown ? 1 : 0.4)
                Image(systemName: summary.leveledUp ? "star.fill" : "checkmark")
                    .font(.system(size: 52, weight: .bold)).foregroundStyle(Palette.accent)
                    .scaleEffect(shown ? 1 : 0.2)
            }
            VStack(spacing: 6) {
                Text(summary.leveledUp ? "Level \(summary.level)!" : "Nice workout!").font(.largeTitle.weight(.bold)).foregroundStyle(Palette.text)
                Text(summary.leveledUp ? "You levelled up with \(summary.name)." : "\(summary.name) is saved.")
                    .font(.body).foregroundStyle(Palette.muted)
            }
            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 12)
            HStack(spacing: 12) {
                stat("\(summary.sets)", "sets")
                stat(weight(summary.volume, model.training.settings.unit), model.training.settings.unit.rawValue)
                stat("\(summary.minutes)", "min")
                stat("+\(summary.xp)", "XP", accent: true)
            }
            .opacity(shown ? 1 : 0)
            if !summary.rankUps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Rank up", systemImage: "medal.fill").font(.headline).foregroundStyle(Palette.accent)
                    ForEach(summary.rankUps, id: \.self) { Text($0).font(.subheadline).foregroundStyle(Palette.text) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16).glass()
                .opacity(shown ? 1 : 0)
            }
            if !summary.records.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("New \(summary.records.count == 1 ? "record" : "records")", systemImage: "trophy.fill")
                        .font(.headline).foregroundStyle(Palette.accent)
                    ForEach(summary.records, id: \.self) { Text($0).font(.subheadline).foregroundStyle(Palette.text) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16).glass()
                .opacity(shown ? 1 : 0)
            }
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(Backdrop())
        .sensoryFeedback(.success, trigger: shown) { _, now in now }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: landed) { _, now in now && celebrate }
        .onAppear {
            withAnimation(.smooth(duration: 0.6).delay(0.15)) { shown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { landed = true }
        }
        .presentationDetents([.large])
    }

    private func stat(_ value: String, _ label: String, accent: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(accent ? Palette.accent : Palette.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12).glass(radius: 16)
    }
}
