import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TrackWidgets: WidgetBundle {
    var body: some Widget { RestLiveActivity() }
}

/// The rest timer in the Dynamic Island and on the Lock Screen: a ring emptying in Track's mint and the countdown,
/// both driven by the system from the end time, so they stay smooth with Track closed.
struct RestLiveActivity: Widget {
    private static let mint = Color(red: 0x48 / 255, green: 0xE5 / 255, blue: 0x8D / 255)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestAttributes.self) { context in
            HStack(spacing: 14) {
                ring(context.state, size: 44, line: 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest").font(.subheadline).foregroundStyle(.secondary)
                    Text(timerInterval: Self.left(context.state), countsDown: true)
                        .font(.title.weight(.bold)).monospacedDigit()
                }
                Spacer()
                Text(context.attributes.workout).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0x12 / 255, green: 0x14 / 255, blue: 0x18 / 255).opacity(0.85))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { ring(context.state, size: 40, line: 5).padding(.leading, 4) }
                DynamicIslandExpandedRegion(.center) {
                    Text(timerInterval: Self.left(context.state), countsDown: true)
                        .font(.title.weight(.bold)).monospacedDigit().multilineTextAlignment(.center)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Rest").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Next set in \(context.attributes.workout)").font(.footnote).foregroundStyle(.secondary)
                }
            } compactLeading: {
                ring(context.state, size: 20, line: 3)
            } compactTrailing: {
                Text(timerInterval: Self.left(context.state), countsDown: true)
                    .monospacedDigit().font(.subheadline.weight(.semibold)).foregroundStyle(Self.mint)
                    .frame(maxWidth: 44)
            } minimal: {
                ring(context.state, size: 20, line: 3)
            }
            .keylineTint(Self.mint)
        }
    }

    /// From now to the rest's end; empty once it has passed (a range can't run backwards).
    private static func left(_ state: RestAttributes.ContentState) -> ClosedRange<Date> {
        let now = Date.now
        return now...max(now, state.until)
    }

    /// A ring that empties as the rest runs out.
    private func ring(_ state: RestAttributes.ContentState, size: CGFloat, line: CGFloat) -> some View {
        let start = min(state.until.addingTimeInterval(-Double(state.seconds)), state.until)
        return ProgressView(timerInterval: start...state.until, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
            .progressViewStyle(.circular)
            .tint(Self.mint)
            .frame(width: size, height: size)
    }
}
