import UIKit
import os

/// For measuring smoothness (UITests/PerfTour.swift, or on a phone): launched with -frameLog, every screen refresh is
/// timed, and a frame that came later than its slot by half a frame or more counts as a hitch: "jank" when it's
/// under a quarter second (a stutter you see), a stall when longer (the UI tests reading the screen cause those). The running tally is
/// read as the label of a hidden element ("frame-log"), worked out when it's read, so reading it costs no frames, and each
/// hitch goes to the device log ("Track frames"), readable over USB without touching the app.
/// Without the argument nothing here runs.
@MainActor final class FrameLog: NSObject {
    private static var shared: FrameLog?
    private var window: UIWindow?
    private let logger = Logger(subsystem: "Track", category: "frames")
    private var last: CFTimeInterval = 0
    private var frames = 0, hitches = 0, jank = 0
    private var late: Double = 0, jankLate: Double = 0, worst: Double = 0

    static func install() {
        guard shared == nil, ProcessInfo.processInfo.arguments.contains("-frameLog"),
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let log = FrameLog()
        let link = CADisplayLink(target: log, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120) // ProMotion stays at full rate
        link.add(to: .main, forMode: .common)
        // Its own window, above everything (a workout covers the app's), taking no touches.
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.isUserInteractionEnabled = false
        let root = UIViewController()
        let tally = Tally(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        tally.log = log
        root.view.addSubview(tally)
        window.rootViewController = root
        window.isHidden = false
        log.window = window
        shared = log
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard last > 0 else { return }
        let gap = link.timestamp - last, slot = link.targetTimestamp - link.timestamp
        frames += 1
        worst = max(worst, gap)
        guard gap > slot * 1.5 else { return }
        hitches += 1; late += gap - slot
        logger.log("hitch \(Int((gap - slot) * 1000)) ms late, total \(self.hitches)")
        if gap - slot < 0.25 { jank += 1; jankLate += gap - slot }
    }

    /// Running totals since launch; a test reads them before and after a step and takes the difference.
    fileprivate var summary: String {
        String(format: "frames=%d hitches=%d late=%.1f jank=%d jankms=%.1f worst=%.1f", frames, hitches, late * 1000, jank, jankLate * 1000, worst * 1000)
    }

    private final class Tally: UIView {
        weak var log: FrameLog?
        override var isAccessibilityElement: Bool { get { true } set {} }
        override var accessibilityIdentifier: String? { get { "frame-log" } set {} }
        override var accessibilityLabel: String? { get { log?.summary } set {} }
    }
}
