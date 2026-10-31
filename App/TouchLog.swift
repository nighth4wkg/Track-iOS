import UIKit
import UIKit.UIGestureRecognizerSubclass
import os

/// For measuring how fast a touch shows (-touchLog, driven by ~/.pmd3/bench/stress.py): every finger down and up is
/// timed from the touch's own timestamp to the first screen refresh whose pixels differ, found by comparing a small
/// copy of what's on screen (SwiftUI draws many views into one layer, so comparing layers would miss changes). Each goes
/// to the device log ("Track touch"), numbered so a script can match it to its step:
/// "touch 12 up at 196,801: shown 9 ms, 1 frames, longest gap 8 ms, copy 2.1 ms" or "… no change in 600 ms".
/// The longest gap between refreshes says whether a slow one was the app busy; the copy's own cost is logged too.
/// Without the argument nothing here runs.
@MainActor final class TouchLog: NSObject, UIGestureRecognizerDelegate {
    private static var shared: TouchLog?
    private let logger = Logger(subsystem: "Track", category: "touch")
    private weak var scene: UIWindowScene?
    /// A touch being watched: what it was, when, the screen before it, and the refreshes since.
    private var watching: (name: String, at: CFTimeInterval, before: [UInt8], frames: Int, gap: CFTimeInterval, last: CFTimeInterval)?
    private var count = 0, copyTime: CFTimeInterval = 0, copies = 0
    /// How long a touch is watched for a change, and the copy's scale (a quarter of a point per pixel).
    private static let window: CFTimeInterval = 0.6, scale: CGFloat = 0.25

    static func install() {
        guard shared == nil, ProcessInfo.processInfo.arguments.contains("-touchLog"),
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let log = TouchLog()
        log.scene = scene
        let link = CADisplayLink(target: log, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
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
        watch.frames += 1
        watch.gap = max(watch.gap, link.timestamp - watch.last)
        watch.last = link.timestamp
        watching = watch
        if copy() != watch.before { finish("shown \(ms(link.timestamp - watch.at)) ms, \(watch.frames) frames") }
        else if link.timestamp - watch.at > Self.window { finish("no change in \(ms(Self.window)) ms") }
    }

    private func start(_ name: String, _ at: CFTimeInterval) {
        if watching != nil { finish("cut short by the next touch") }
        count += 1
        watching = ("touch \(count) \(name)", at, copy(), 0, 0, CACurrentMediaTime())
    }

    private func finish(_ result: String) {
        guard let watch = watching else { return }
        watching = nil
        let copyAverage = copies > 0 ? copyTime / Double(copies) * 1000 : 0
        // Public: the device log hides text by default.
        logger.log("\(watch.name, privacy: .public): \(result, privacy: .public), longest gap \(self.ms(watch.gap)) ms, copy \(String(format: "%.1f", copyAverage), privacy: .public) ms")
        copyTime = 0; copies = 0
    }

    /// What's on screen now, every window in order, as a small bitmap.
    private func copy() -> [UInt8] {
        let started = CACurrentMediaTime()
        defer { copyTime += CACurrentMediaTime() - started; copies += 1 }
        let windows = (scene?.windows ?? []).filter { !$0.isHidden }.sorted { $0.windowLevel < $1.windowLevel }
        guard let size = windows.first?.bounds.size else { return [] }
        let width = Int(size.width * Self.scale), height = Int(size.height * Self.scale)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: Self.scale, y: -Self.scale)
            UIGraphicsPushContext(context)
            for window in windows { window.drawHierarchy(in: window.frame, afterScreenUpdates: false) }
            UIGraphicsPopContext()
        }
        return pixels
    }

    private func ms(_ seconds: CFTimeInterval) -> Int { Int((seconds * 1000).rounded()) }

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
