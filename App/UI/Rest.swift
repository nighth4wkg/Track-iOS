import SwiftUI
import TrackCore

/// Rest (the PWA's timer floating where the nav pill sits): a ring running down, the time left, −15s, +15s and Skip.
/// It shows only while the rest runs; running out buzzes. `compact` is just the ring and the time, for the keyboard's
/// bar while typing.
struct RestTimer: View {
    @Environment(AppModel.self) private var model
    var compact = false
    /// How often the time and ring redraw.
    private static let tick: TimeInterval = 0.5
    @State private var ended = 0
    /// The rest that ran out: its clock stops redrawing until the next one starts.
    @State private var over: Int?

    var body: some View {
        let until = model.training.restUntil
        Group {
            if let until, until != over {
                TimelineView(.periodic(from: .now, by: Self.tick)) { context in
                    let left = max(0, Double(until) / 1000 - context.date.timeIntervalSince1970)
                    let total = Double(max(1, model.training.settings.restSeconds))
                    if left > 0 {
                        if compact {
                            ring(left, total).accessibilityLabel("Rest, \(time(left)) left").frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            full(left, total)
                        }
                    }
                }
                // A new or shifted rest gets a fresh clock; the old one's last tick would show a second too many.
                .id(until)
                .task(id: until) {
                    let wait = Double(until) / 1000 - Date.now.timeIntervalSince1970
                    guard wait > 0 else { over = until; return }
                    try? await Task.sleep(for: .seconds(wait))
                    guard !Task.isCancelled, model.training.restUntil == until else { return }
                    ended += 1
                    over = until
                }
            }
        }
        .sensoryFeedback(.warning, trigger: ended)
    }

    private func full(_ left: Double, _ total: Double) -> some View {
        HStack(spacing: Space.s2) {
            ring(left, total).accessibilityLabel("\(time(left)) of rest left")
            Spacer(minLength: 0)
            shift("−15s", "15 seconds less") { model.shiftRest(by: -15) }
            shift("+15s", "15 seconds more") { model.shiftRest(by: 15) }
            Button("Skip") { model.skipRest() }.buttonStyle(PrimaryStyle(compact: true))
        }
        .padding(.horizontal, Space.s2)
        .frame(height: Size.nav)
        .raised(.float, .pill)
        .frame(maxWidth: Size.navWidth)
        .padding(.horizontal, Space.s4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rest timer")
        .floatingBar(Size.nav)
    }

    /// The ring running down beside the time left.
    private func ring(_ left: Double, _ total: Double) -> some View {
        HStack(spacing: Space.s2) {
            Ring(value: left / total, size: Rings.rest.size, stroke: Rings.rest.stroke, label: "") { EmptyView() }
            Text(time(left)).type(.t20).monospacedDigit().foregroundStyle(Palette.text)
        }
        .accessibilityElement(children: .ignore)
    }

    private func time(_ left: Double) -> String { clock(Int(left.rounded(.up))) }

    private func shift(_ title: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).type(.t12).foregroundStyle(Palette.text)
                .frame(width: Size.control, height: Size.control).raised(.control, .pill)
        }
        .buttonStyle(CardStyle())
        .accessibilityLabel(label)
    }
}
