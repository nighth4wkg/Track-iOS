import UIKit
import os

/// shortcut: a temporary probe for the nav pill that ignores taps at launch; delete it once that's fixed.
/// Launched with -hitProbe, each touch logs ("Track hits", device log) the view it lands on, up to the window, and
/// every gesture recognizer on that path with its state as the finger lifts. -hideTabBar hides iOS's own tab bar
/// (behind the pill) in UIKit as well. Without the arguments nothing here runs.
@MainActor enum HitProbe {
    private static let logger = Logger(subsystem: "Track", category: "hits")

    static func install() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-hitProbe") || arguments.contains("-hideTabBar"),
              let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.windows.first }).first else { return }
        if arguments.contains("-hitProbe") { window.addGestureRecognizer(Watcher()) }
        if arguments.contains("-hideTabBar") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { hideBars(window.rootViewController) }
        }
    }

    private static func hideBars(_ controller: UIViewController?) {
        guard let controller else { return }
        if let tabs = controller as? UITabBarController {
            tabs.tabBar.isHidden = true
            logger.log("hid tab bar \(String(describing: type(of: tabs)), privacy: .public)")
        }
        controller.children.forEach(hideBars)
        hideBars(controller.presentedViewController)
    }

    static func path(_ view: UIView?) -> [UIView] { sequence(first: view, next: { $0?.superview }).compactMap { $0 } }

    static func log(_ phase: String, _ touch: UITouch) {
        let views = path(touch.view)
        let names = views.map { String(describing: type(of: $0)) }.joined(separator: " < ")
        let recognizers = views.flatMap { $0.gestureRecognizers ?? [] }.filter { !($0 is Watcher) }
            .map { "\(type(of: $0))#\($0.state.rawValue)\($0.isEnabled ? "" : "off")" }.joined(separator: " ")
        logger.log("\(phase, privacy: .public) at \(Int(touch.location(in: nil).x)),\(Int(touch.location(in: nil).y)) view: \(names, privacy: .public)")
        logger.log("\(phase, privacy: .public) recognizers: \(recognizers, privacy: .public)")
    }

    /// Never recognizes and never holds a touch back: it only watches.
    private final class Watcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
        init() {
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesEnded = false
            delegate = self
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            if let touch = touches.first { HitProbe.log("down", touch) }
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let touch = touches.first else { return }
            HitProbe.log("up", touch)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { HitProbe.log("after", touch) }
            state = .failed
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            if let touch = touches.first { HitProbe.log("cancel", touch) }
            state = .failed
        }
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
