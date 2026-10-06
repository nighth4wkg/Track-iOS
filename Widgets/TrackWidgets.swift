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
    private static let mint = Color(hex: Hex.mint)
    /// A tap opens the workout itself, not Home (TrackApp's onOpenURL).
    private static let workout = URL(string: "track://workout")

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestAttributes.self) { context in
            HStack(spacing: 14) {
                ring(context.state, size: 44, line: 5)
                VStack(alignment: .leading, spacing: 0) {
                    Text(context.state.resting ? "Rest · \(context.attributes.workout)" : context.attributes.workout)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    countdown(context.state).font(.title.weight(.bold))
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                if context.state.resting { controls(stale: context.isStale) }
            }
            .padding(16)
            .activityBackgroundTint(Color(hex: Hex.night, opacity: 0.85))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(Self.workout)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 10) {
                        ring(context.state, size: 36, line: 4)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(context.state.resting ? "Rest" : "Ready").font(.headline)
                            Text(context.attributes.workout).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.leading, 6)
                    .frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state).font(.system(size: 34, weight: .bold)).multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing).padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.resting { controls(stale: context.isStale, wide: true).padding(.horizontal, 6).padding(.top, 6) }
                }
            } compactLeading: {
                ring(context.state, size: 20, line: 3)
            } compactTrailing: {
                countdown(context.state).font(.subheadline.weight(.semibold)).foregroundStyle(Self.mint)
                    .multilineTextAlignment(.trailing).frame(maxWidth: 44)
            } minimal: {
                ring(context.state, size: 20, line: 3)
            }
            .keylineTint(Self.mint)
            .widgetURL(Self.workout)
        }
    }

    /// From now to the rest's end; empty once it has passed (a range can't run backwards).
    private static func left(_ state: RestAttributes.ContentState) -> ClosedRange<Date> {
        let now = Date.now
        return now...max(now, state.until)
    }

    /// The time left, counting down on its own; between rests, "Go".
    @ViewBuilder private func countdown(_ state: RestAttributes.ContentState) -> some View {
        if state.resting {
            Text(timerInterval: Self.left(state), countsDown: true).monospacedDigit().lineLimit(1)
        } else {
            Text("Go").lineLimit(1)
        }
    }

    /// +30s while it runs, then Skip (Done once it's over): they change the rest in Track. In the Dynamic Island they
    /// share its width.
    private func controls(stale: Bool, wide: Bool = false) -> some View {
        HStack(spacing: 8) {
            if !stale { Button(intent: RestIntent(seconds: 30)) { label("+30s", wide) } }
            Button(intent: RestIntent(seconds: 0)) { label(stale ? "Done" : "Skip", wide) }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(Self.mint)
    }

    private func label(_ text: String, _ wide: Bool) -> some View {
        Text(text).lineLimit(1).fixedSize().frame(maxWidth: wide ? .infinity : nil, minHeight: 28)
    }

    /// A ring that empties as the rest runs out.
    /// Between rests, a mint tick instead.
    @ViewBuilder private func ring(_ state: RestAttributes.ContentState, size: CGFloat, line: CGFloat) -> some View {
        if state.resting {
            let start = min(state.until.addingTimeInterval(-Double(state.seconds)), state.until)
            ProgressView(timerInterval: start...state.until, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.circular)
                .tint(Self.mint)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "checkmark.circle.fill").resizable().foregroundStyle(Self.mint).frame(width: size, height: size)
        }
    }
}
