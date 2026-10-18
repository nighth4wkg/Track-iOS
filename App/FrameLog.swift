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
    /// Each hitch while -perfNext drives ("ms since it began:ms late"), to see which steps they fall on.
    private var driveStart: CFTimeInterval?, trace: [String] = []
    /// The everyday action PerfDrive just did: how long until the screen could draw again, and its hitches after.
    private var action: (name: String, start: CFTimeInterval, respond: Double?, hitches: Int, late: Double, worst: Double)?

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
        guard last > 0 else { logger.log("launch: first frame \(Self.sinceLaunch()) ms after the process started"); return }
        let gap = link.timestamp - last, slot = link.targetTimestamp - link.timestamp
        frames += 1
        worst = max(worst, gap)
        if action?.respond == nil, let start = action?.start { action?.respond = CACurrentMediaTime() - start }
        if gap > slot * 1.5, let worst = action?.worst { action?.hitches += 1; action?.late += gap - slot; action?.worst = max(worst, gap - slot) }
        guard gap > slot * 1.5 else { return }
        hitches += 1; late += gap - slot
        logger.log("hitch \(Int((gap - slot) * 1000)) ms late, total \(self.hitches)")
        if gap - slot < 0.25 { jank += 1; jankLate += gap - slot }
        if let driveStart { trace.append("\(Int((last - driveStart) * 1000)):\(Int((gap - slot) * 1000))") }
    }

    /// With -perfNext too: once a workout opens, the keyboard moves on through its fields every 150 ms, as when Next
    /// is pressed over and over, with no test tool touching the app meanwhile (PerfTour reads the tally around it).
    static func driveNext(_ fields: [String], focus: (String) -> Void) async {
        guard ProcessInfo.processInfo.arguments.contains("-perfNext") else { return }
        try? await Task.sleep(for: .seconds(6))
        shared?.driveStart = CACurrentMediaTime()
        for field in fields.prefix(40) { focus(field); try? await Task.sleep(for: .milliseconds(150)) }
    }

    /// PerfDrive's next action begins (nil: the last has ended): the one before goes to the device log ("Track
    /// actions"): how long the screen waited for it, and how many frames came late after it and by how much.
    static func mark(_ name: String?) {
        if let name { Sampler.begin(name) }
        guard let log = shared else { return }
        if let a = log.action {
            let late = "\(a.hitches) late frames, \(Int(a.late * 1000)) ms late in all, worst \(Int(a.worst * 1000)) ms"
            Logger(subsystem: "Track", category: "actions").log("action \(a.name, privacy: .public): waited \(Int((a.respond ?? 0) * 1000)) ms, \(late, privacy: .public)")
        }
        log.action = name.map { ($0, CACurrentMediaTime(), nil, 0, 0, 0) }
    }

    /// Milliseconds since the kernel started this process (the launch, including what runs before main).
    private static func sinceLaunch() -> Int {
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride, mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return -1 }
        let start = info.kp_proc.p_starttime
        return Int((Date().timeIntervalSince1970 - (Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)) * 1000)
    }

    /// Running totals since launch; a test reads them before and after a step and takes the difference.
    fileprivate var summary: String {
        String(format: "frames=%d hitches=%d late=%.1f jank=%d jankms=%.1f worst=%.1f trace=%@", frames, hitches, late * 1000, jank, jankLate * 1000,
               worst * 1000, trace.joined(separator: ","))
    }

    private final class Tally: UIView {
        weak var log: FrameLog?
        override var isAccessibilityElement: Bool { get { true } set {} }
        override var accessibilityIdentifier: String? { get { "frame-log" } set {} }
        override var accessibilityLabel: String? { get { log?.summary } set {} }
    }
}
