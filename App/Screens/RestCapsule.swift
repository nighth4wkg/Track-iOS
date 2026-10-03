import SwiftUI
import TrackCore

/// Rest, as the website's capsule floating at the bottom: a ring running down, the time left, +30s and Skip. When it
/// runs out it says "Go · Ready for your next set" with Done, and buzzes; it rises in and sinks out.
struct RestCapsule: View {
    @Environment(AppModel.self) private var model
    @State private var ended = 0

    var body: some View {
        let until = model.training.restUntil
        Group {
            if let until {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let left = max(0, Double(until) / 1000 - context.date.timeIntervalSince1970)
                    let total = Double(max(1, model.training.settings.restSeconds))
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(Palette.input, lineWidth: 5)
                            Circle().trim(from: 0, to: min(1, left / total)).stroke(Palette.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90)).animation(.linear(duration: 0.5), value: left)
                        }
                        .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(left > 0 ? String(format: "%d:%02d", Int(left.rounded(.up)) / 60, Int(left.rounded(.up)) % 60) : "Go")
                                .font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Palette.text)
                            Text(left > 0 ? "Rest" : "Ready for your next set").font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if left > 0 { pill("+30s") { model.changeRest(by: 30) } }
                        pill(left > 0 ? "Skip" : "Done") { model.changeRest(by: 0) }
                    }
                    .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .glass(radius: 32, fill: .clear)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: until) {
                    let wait = Double(until) / 1000 - Date.now.timeIntervalSince1970
                    guard wait > 0 else { return }
                    try? await Task.sleep(for: .seconds(wait))
                    if !Task.isCancelled, model.training.restUntil == until { ended += 1 }
                }
            }
        }
        .animation(.smooth(duration: 0.35), value: until)
        .sensoryFeedback(.success, trigger: ended)
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .glass(radius: 22, fill: Palette.control, lifted: false)
            .buttonStyle(PressStyle())
    }
}
