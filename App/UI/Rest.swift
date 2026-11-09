import SwiftUI
import TrackCore
import UIKit

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
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let until = model.training.restUntil
        let resting = until != nil && until != over
        // Up from below the screen's edge as a rest starts, back down as it ends or is skipped (the PWA's .rest); the
        // one in the keyboard's bar just shows.
        let moving = !compact && !still && !AB.stillRest
        ZStack {
            if let until, resting {
                // The rise is on this holder, which stays through a ±: on the clock it went with each new clock (its
                // .id), so a ± slid the timer out and up again (build 103).
                ZStack {
                    Ticking(every: Self.tick) { now in
                        let left = max(0, Double(until) / 1000 - now.timeIntervalSince1970)
                        let total = Double(max(1, model.training.settings.restSeconds))
                        if left > 0 {
                            if compact {
                                ring(left, total, until).accessibilityLabel("Rest, \(time(left)) left").padding(.horizontal, Space.s2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                full(left, total, until)
                            }
                        }
                    }
                    // A new or shifted rest gets a fresh clock, swapped in place; the old one's last tick would show a
                    // second too many.
                    .id(until)
                    .transition(.identity)
                }
                .task(id: until) {
                    let wait = Double(until) / 1000 - Date.now.timeIntervalSince1970
                    guard wait > 0 else { over = until; return }
                    try? await Task.sleep(for: .seconds(wait))
                    guard !Task.isCancelled, model.training.restUntil == until else { return }
                    ended += 1
                    over = until
                }
                .transition(.rise(Size.nav + floatingGap, moving))
            }
        }
        .motion(on: resting, moving)
        .sensoryFeedback(.warning, trigger: ended)
    }

    private func full(_ left: Double, _ total: Double, _ until: Int) -> some View {
        HStack(spacing: Space.s2) {
            ring(left, total, until).accessibilityLabel("\(time(left)) of rest left")
            Spacer(minLength: 0)
            shift("−\(RestIntent.step)s", "\(RestIntent.step) seconds less") { shiftRest(by: -RestIntent.step) }
            shift("+\(RestIntent.step)s", "\(RestIntent.step) seconds more") { shiftRest(by: RestIntent.step) }
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
    private func ring(_ left: Double, _ total: Double, _ until: Int) -> some View {
        HStack(spacing: Space.s2) {
            if AB.oldWay {
                Ring(value: left / total, size: Rings.rest.size, stroke: Rings.rest.stroke, label: "") { EmptyView() }
            } else {
                ZStack {
                    Circle().inset(by: Rings.rest.stroke / 2).stroke(Palette.well, lineWidth: Rings.rest.stroke)
                    RestArc(until: until, total: total, left: left)
                }
                .frame(width: Rings.rest.size, height: Rings.rest.size)
            }
            Text(time(left)).type(.t20).monospacedDigit().foregroundStyle(Palette.text)
        }
        .accessibilityElement(children: .ignore)
    }

    private func time(_ left: Double) -> String { clock(Int(left.rounded(.up))) }

    /// Only while a rest runs: the timer on its way out still takes taps, and +15s there would start a new rest.
    private func shiftRest(by seconds: Int) {
        guard (model.training.restUntil ?? 0) > nowMillis() else { return }
        model.shiftRest(by: seconds)
    }

    private func shift(_ title: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).type(.t12).foregroundStyle(Palette.text)
                .frame(width: Size.control, height: Size.control).raised(.control, .pill)
        }
        .buttonStyle(CardStyle())
        .accessibilityLabel(label)
    }
}

/// The rest ring's green arc, run down by Core Animation from the time left to none in one smooth move. Redrawn at
/// each tick with animations off, it moved in half-second steps (owner, build 130). Given each tick (`left`), it
/// starts again only for a new or shifted rest, or if its move was ever taken away; each tick also sets where it
/// stands, so without its move it would still step as before rather than show nothing.
private struct RestArc: UIViewRepresentable {
    let until: Int
    let total: Double
    let left: Double

    func makeUIView(context: Context) -> Arc { Arc() }
    func updateUIView(_ arc: Arc, context: Context) { arc.run(until: until, total: total, left: left) }

    final class Arc: UIView {
        private let shape = CAShapeLayer()
        private var running: (until: Int, total: Double)?
        private static let key = "left"

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            shape.fillColor = nil
            shape.lineCap = .round
            shape.lineWidth = Rings.rest.stroke
            shape.strokeColor = UIColor(Palette.accent).cgColor
            shape.strokeEnd = 0
            layer.addSublayer(shape)
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            shape.frame = bounds
            // As Ring's: from the top, clockwise, its stroke inside the box.
            let radius = (min(bounds.width, bounds.height) - Rings.rest.stroke) / 2
            shape.path = UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius,
                                      startAngle: -.pi / 2, endAngle: .pi * 3 / 2, clockwise: true).cgPath
        }

        func run(until: Int, total: Double, left: Double) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            shape.strokeEnd = CGFloat(min(1, max(0, left / total)))
            guard running?.until != until || running?.total != total || shape.animation(forKey: Self.key) == nil else { return }
            running = (until, total)
            shape.removeAnimation(forKey: Self.key)
            guard left > 0 else { return }
            // A rest made longer than the setting (+15s) stays full until it's back to the setting's length, as Ring did.
            let move = CABasicAnimation(keyPath: "strokeEnd")
            move.fromValue = min(1, left / total)
            move.toValue = 0
            move.duration = min(left, total)
            move.beginTime = shape.convertTime(CACurrentMediaTime(), from: nil) + max(0, left - total)
            move.fillMode = .both
            // Kept when it's done or the app goes to the background, so it isn't started again (or lost) on the way back.
            move.isRemovedOnCompletion = false
            shape.add(move, forKey: Self.key)
        }
    }
}
