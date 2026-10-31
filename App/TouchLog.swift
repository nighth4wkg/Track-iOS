import UIKit
import UIKit.UIGestureRecognizerSubclass
import os

/// For measuring how fast a touch shows (-touchLog, driven by ~/.pmd3/bench/stress.py). Every finger down and up is
/// timed from the touch's own timestamp: "ready" when the main thread has handled it and handed its frame over (idle
/// after the system's commit), "frame" at the next screen refresh after that, when it shows. The layers are compared
/// at each idle, so a response that comes later (after an async step) is timed too, and a touch that changed no layer
/// says so (SwiftUI can redraw inside one layer, so "no layer change" is a hint to check, not proof of a dead tap).
/// Each goes to the device log ("Track touch"), numbered so a script can match it to its step:
/// "touch 12 up at 196,801: ready 3 ms, frame 8 ms, first change 3 ms, last change 3 ms, changed [CALayer x2], longest
/// gap 8 ms, check 0.4 ms". "changed" names the views whose own layer changed (what keeps redrawing).
/// Without the argument nothing here runs. (A copy of the screen per refresh cost 50–90 ms: it was the delay itself.)
@MainActor final class TouchLog: NSObject, UIGestureRecognizerDelegate {
    private static var shared: TouchLog?
    private let logger = Logger(subsystem: "Track", category: "touch")
    private weak var scene: UIWindowScene?
    private struct Watch {
        let name: String, at: CFTimeInterval, before: Int
        var ready: CFTimeInterval?, frame: CFTimeInterval?, first: CFTimeInterval?, change: CFTimeInterval?, lastTick: CFTimeInterval, gap: CFTimeInterval = 0
        /// The views whose own layer changed while it was watched, and how many times: what keeps redrawing.
        var changed: [String: Int] = [:]
    }
    private var watching: Watch?
    private var count = 0, checkTime: CFTimeInterval = 0, checks = 0
    /// Each layer's own look at the last check, to name the ones that changed.
    private var own: [ObjectIdentifier: Int] = [:], diff: [String: Int] = [:]
    /// How long a touch is watched for a later change.
    private static let window: CFTimeInterval = 0.6

    static func install() {
        guard shared == nil, ProcessInfo.processInfo.arguments.contains("-touchLog"),
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let log = TouchLog()
        log.scene = scene
        let link = CADisplayLink(target: log, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        // After everything else in a pass, the system's commit (2000000) included: the frame is handed over.
        let idle = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, Int(Int32.max)) { _, _ in
            MainActor.assumeIsolated { log.idle() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), idle, .commonModes)
        shared = log
    }

    @objc private func tick(_ link: CADisplayLink) {
        // Windows that came later (a dialog's own) get a watcher too.
        for window in scene?.windows ?? [] where !(window.gestureRecognizers ?? []).contains(where: { $0 is Watcher }) {
            let watcher = Watcher(target: nil, action: nil)
            watcher.delegate = self
            watcher.seen = { [weak self] name, at in self?.start(name, at) }
            window.addGestureRecognizer(watcher)
        }
        guard var watch = watching else { return }
        watch.gap = max(watch.gap, link.timestamp - watch.lastTick)
        watch.lastTick = link.timestamp
        // The first refresh after it was ready is when it shows.
        if watch.ready != nil, watch.frame == nil { watch.frame = link.timestamp }
        watching = watch
        if link.timestamp - watch.at > Self.window { finish() }
    }

    private func idle() {
        guard var watch = watching else { return }
        let now = CACurrentMediaTime()
        if watch.ready == nil { watch.ready = now }
        if layers() != watch.before { watch.change = now; if watch.first == nil { watch.first = now } }
        watch.changed.merge(diff, uniquingKeysWith: +)
        watching = watch
    }

    private func start(_ name: String, _ at: CFTimeInterval) {
        if watching != nil { finish() }
        count += 1
        watching = Watch(name: "touch \(count) \(name)", at: at, before: layers(), ready: nil, frame: nil, first: nil, change: nil, lastTick: CACurrentMediaTime())
        Sampler.begin(watching!.name, for: Self.window)
    }

    private func finish() {
        guard let watch = watching else { return }
        watching = nil
        let ms = { (time: CFTimeInterval?) in time.map { "\(Int((($0 - watch.at) * 1000).rounded())) ms" } ?? "none" }
        let check = String(format: "%.1f", checks > 0 ? checkTime / Double(checks) * 1000 : 0)
        let changes = watch.changed.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) x\($0.value)" }.joined(separator: " ")
        let result = "ready \(ms(watch.ready)), frame \(ms(watch.frame)), first change \(ms(watch.first)), last change \(watch.change == nil ? "no layer change" : ms(watch.change)), changed [\(changes)]"
        // Public: the device log hides text by default.
        logger.log("\(watch.name, privacy: .public): \(result, privacy: .public), longest gap \(Int(watch.gap * 1000)) ms, check \(check, privacy: .public) ms")
        checkTime = 0; checks = 0
    }

    /// A fingerprint of every window's layers: where they are, how they look, what they hold.
    private func layers() -> Int {
        let started = CACurrentMediaTime()
        defer { checkTime += CACurrentMediaTime() - started; checks += 1 }
        var hasher = Hasher(), now: [ObjectIdentifier: Int] = [:]
        diff = [:]
        func fold(_ layer: CALayer) {
            var mine = Hasher()
            mine.combine(layer.position.x); mine.combine(layer.position.y)
            mine.combine(layer.bounds.origin.y); mine.combine(layer.bounds.width); mine.combine(layer.bounds.height)
            mine.combine(layer.opacity); mine.combine(layer.isHidden)
            mine.combine(layer.backgroundColor.map { CFHash($0) } ?? 0)
            if let contents = layer.contents { mine.combine(ObjectIdentifier(contents as AnyObject)) }
            let id = ObjectIdentifier(layer), look = mine.finalize()
            now[id] = look
            if let was = own[id], was != look { diff[layer.delegate.map { String(describing: type(of: $0)) } ?? String(describing: type(of: layer)), default: 0] += 1 }
            hasher.combine(id); hasher.combine(look)
            for sublayer in layer.sublayers ?? [] { fold(sublayer) }
        }
        for window in scene?.windows ?? [] where !window.isHidden { fold(window.layer) }
        own = now
        return hasher.finalize()
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    /// Sees every touch and never takes one: it holds nothing back and fails when the finger lifts.
    private final class Watcher: UIGestureRecognizer {
        var seen: ((String, CFTimeInterval) -> Void)?

        override init(target: Any?, action: Selector?) {
            super.init(target: target, action: action)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { report("down", touches) }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            report("up", touches)
            state = .failed
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }

        private func report(_ name: String, _ touches: Set<UITouch>) {
            guard let touch = touches.first else { return }
            let point = touch.location(in: view)
            seen?("\(name) at \(Int(point.x)),\(Int(point.y))", touch.timestamp)
        }
    }
}
