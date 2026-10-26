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
    /// The Lock Screen's see-through night behind it.
    private static let backdrop = 0.85
    /// Rings (size, line): on the Lock Screen a tap target's size, in the open island smaller, in its pill smallest.
    private static let rings = (lock: (size: 44.0, line: 5.0), island: (size: 36.0, line: 4.0), compact: (size: 20.0, line: 3.0))
    /// The open island's time, its inset from the island's curve, and the pill's room for the time.
    private static let island = (time: 34.0, inset: 6.0, compactTime: 44.0)
    /// A button's least height: the system's small capsule.
    private static let button = 28.0
    /// A tap opens the workout itself, not Home (TrackApp's onOpenURL).
    private static let workout = URL(string: "track://workout")

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestAttributes.self) { context in
            // Laid out as the open island: what it is on the left, the time on the right, the buttons on their own row.
            VStack(spacing: Space.s3) {
                HStack(spacing: Space.s3) {
                    title(context, ring: Self.rings.lock)
                    countdown(context).font(.title.weight(.bold)).multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if context.state.resting { controls(stale: context.isStale) }
            }
            .padding(Space.s4)
            .activityBackgroundTint(Color(hex: Hex.night, opacity: Self.backdrop))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(Self.workout)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    title(context, ring: Self.rings.island)
                        .padding(.leading, Self.island.inset)
                    .frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context).font(.system(size: Self.island.time, weight: .bold)).multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing).padding(.trailing, Self.island.inset)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.resting { controls(stale: context.isStale).padding(.horizontal, Self.island.inset).padding(.top, Self.island.inset) }
                }
            } compactLeading: {
                ring(context, size: Self.rings.compact.size, line: Self.rings.compact.line)
            } compactTrailing: {
                countdown(context).font(.subheadline.weight(.semibold)).foregroundStyle(Self.mint)
                    .multilineTextAlignment(.trailing).frame(maxWidth: Self.island.compactTime)
            } minimal: {
                ring(context, size: Self.rings.compact.size, line: Self.rings.compact.line)
            }
            .keylineTint(Self.mint)
            .widgetURL(Self.workout)
        }
    }

    /// Resting until the end time: iOS marks the activity stale then (RestLive's staleDate) and redraws it, so a rest
    /// that runs out on its own shows "Go" without Track having to wake up.
    private static func resting(_ context: ActivityViewContext<RestAttributes>) -> Bool { context.state.resting && !context.isStale }

    /// From now to the rest's end; empty once it has passed (a range can't run backwards).
    private static func left(_ state: RestAttributes.ContentState) -> ClosedRange<Date> {
        let now = Date.now
        return now...max(now, state.until)
    }

    /// The time left, counting down on its own; between rests, "Go".
    @ViewBuilder private func countdown(_ context: ActivityViewContext<RestAttributes>) -> some View {
        if Self.resting(context) {
            Text(timerInterval: Self.left(context.state), countsDown: true).monospacedDigit().lineLimit(1)
        } else {
            Text("Go").lineLimit(1)
        }
    }

    /// −15s and +15s while it runs (the app's rest buttons), then Skip (Done once it's over): they change the rest in
    /// Track. They share the row's width.
    private func controls(stale: Bool) -> some View {
        HStack(spacing: Space.s2) {
            if !stale {
                Button(intent: RestIntent(seconds: -RestIntent.step)) { label("−\(RestIntent.step)s") }
                Button(intent: RestIntent(seconds: RestIntent.step)) { label("+\(RestIntent.step)s") }
            }
            Button(intent: RestIntent(seconds: 0)) { label(stale ? "Done" : "Skip") }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(Self.mint)
    }

    private func label(_ text: String) -> some View {
        Text(text).lineLimit(1).fixedSize().frame(maxWidth: .infinity, minHeight: Self.button)
    }

    /// The ring beside "Rest" (or "Ready") over the workout's name: the Lock Screen's and the open island's left side.
    private func title(_ context: ActivityViewContext<RestAttributes>, ring size: (size: Double, line: Double)) -> some View {
        HStack(spacing: Space.s3) {
            ring(context, size: size.size, line: size.line)
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.resting(context) ? "Rest" : "Ready").font(.headline)
                Text(context.attributes.workout).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .layoutPriority(1)
    }

    /// A ring that empties as the rest runs out.
    /// Between rests, a mint tick instead.
    @ViewBuilder private func ring(_ context: ActivityViewContext<RestAttributes>, size: CGFloat, line: CGFloat) -> some View {
        if Self.resting(context) {
            let state = context.state
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
