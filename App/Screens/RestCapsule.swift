import SwiftUI
import TrackCore

/// Rest, as the PWA's timer floating where the nav pill sits: a ring running down, the time left, −15s, +15s and Skip.
/// It shows only while the rest runs, rising in and sinking out; running out buzzes. `compact` is just the ring and the
/// time, for the keyboard's bar while typing.
struct RestCapsule: View {
    @Environment(AppModel.self) private var model
    var compact = false
    @State private var ended = 0

    var body: some View {
        let until = model.training.restUntil
        Group {
            if let until {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let left = max(0, Double(until) / 1000 - context.date.timeIntervalSince1970)
                    let total = Double(max(1, model.training.settings.restSeconds))
                    if left > 0 {
                        if compact { ring(left, total).accessibilityLabel("Rest, \(clock(left)) left") } else { full(left, total) }
                    }
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
        .animation(.smooth(duration: Motion.slow), value: until)
        .sensoryFeedback(.warning, trigger: ended)
    }

    private func full(_ left: Double, _ total: Double) -> some View {
        HStack(spacing: Space.s2) {
            ring(left, total).accessibilityLabel("\(clock(left)) of rest left")
            Spacer(minLength: 0)
            pill("−15s", "15 seconds less") { model.shiftRest(by: -15) }
            pill("+15s", "15 seconds more") { model.shiftRest(by: 15) }
            Button("Skip") { model.changeRest(by: 0) }.buttonStyle(PrimaryButtonStyle(compact: true))
        }
        .padding(.horizontal, Space.s2)
        .frame(height: Size.nav)
        .raised(.float, .pill)
        .frame(maxWidth: Size.navWidth)
        .padding(.horizontal, Space.s4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rest timer")
    }

    /// The ring running down beside the time left.
    private func ring(_ left: Double, _ total: Double) -> some View {
        HStack(spacing: Space.s2) {
            ZStack {
                Circle().stroke(Palette.input, lineWidth: Size.restStroke)
                Circle().trim(from: 0, to: min(1, left / total)).stroke(Palette.primary, style: StrokeStyle(lineWidth: Size.restStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90)).animation(.linear(duration: 0.5), value: left)
            }
            .frame(width: Size.restRing, height: Size.restRing)
            Text(clock(left)).type(.t20).monospacedDigit().foregroundStyle(Palette.text)
        }
        .accessibilityElement(children: .ignore)
    }

    private func clock(_ left: Double) -> String { restText(Int(left.rounded(.up))) }

    private func pill(_ title: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).type(.t12).fontWeight(.semibold).foregroundStyle(Palette.text)
                .frame(width: Size.control, height: Size.control).raised(.control, .circle)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}
