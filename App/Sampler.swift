import Foundation
import QuartzCore
import SwiftUI
import os

/// Bench-only, for finding what makes a touch slow on the phone (~/.pmd3/bench/stress.py): -probe samples the main
/// thread's stack every millisecond while TouchLog watches a touch and logs where its busy time went. Without the
/// argument nothing here runs.
final class Sampler: Thread, @unchecked Sendable {
    static var shared: Sampler?
    private let target: thread_act_t
    private let lock = NSLock()
    private var window: (name: String, until: CFTimeInterval)?
    private var stacks: [[UInt]] = []
    private let buffer = UnsafeMutablePointer<UInt>.allocate(capacity: 256)
    private let pair = UnsafeMutablePointer<UInt>.allocate(capacity: 2)
    private var names: [UInt: (image: String, symbol: String)] = [:]
    /// The main thread is waiting in its run loop (set by its own observers): a sample there would only show idling.
    fileprivate var waiting = false
    private var idle = 0
    private let log = Logger(subsystem: "Track", category: "probe")

    /// From the main thread.
    static func install() {
        guard shared == nil, ProcessInfo.processInfo.arguments.contains("-probe") else { return }
        let sampler = Sampler(target: pthread_mach_thread_np(pthread_self()))
        sampler.qualityOfService = .userInteractive
        sampler.start()
        shared = sampler
        for (activity, order) in [(CFRunLoopActivity.beforeWaiting, CFIndex.max), (.afterWaiting, CFIndex.min)] {
            let observer = CFRunLoopObserverCreateWithHandler(nil, activity.rawValue, true, order) { _, _ in sampler.waiting = activity == .beforeWaiting }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }

    private init(target: thread_act_t) { self.target = target }

    /// A measured line in the probe log (nothing without -probe).
    static func note(_ text: @autoclosure () -> String) {
        guard let s = shared else { return }
        let line = text()
        s.log.log("probe note \(line, privacy: .public)")
    }

    static func begin(_ name: String, for seconds: CFTimeInterval) {
        guard let s = shared else { return }
        s.lock.lock(); s.window = (name, CACurrentMediaTime() + seconds); s.lock.unlock()
    }

    override func main() {
        while true {
            lock.lock(); let w = window; lock.unlock()
            guard let w else { usleep(5000); continue }
            if CACurrentMediaTime() > w.until {
                lock.lock(); window = nil; lock.unlock()
                report(w.name, stacks); stacks = []; idle = 0
                continue
            }
            if waiting { idle += 1; usleep(1000); continue }
            let n = sample()
            if n > 0 { stacks.append(Array(UnsafeBufferPointer(start: buffer, count: n))) }
            usleep(1000)
        }
    }

    /// The main thread's return addresses, leaf first, read while it's paused (nothing allocated meanwhile).
    private func sample() -> Int {
        guard thread_suspend(target) == KERN_SUCCESS else { return 0 }
        defer { thread_resume(target) }
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) { thread_get_state(target, ARM_THREAD_STATE64, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let strip = { (a: UInt64) in UInt(a & 0x0000_000F_FFFF_FFFF) }
        buffer[0] = strip(state.__pc); buffer[1] = strip(state.__lr)
        var n = 2, fp = UInt(state.__fp)
        while fp != 0, n < 256 {
            var size: vm_size_t = 0
            guard vm_read_overwrite(mach_task_self_, vm_address_t(fp), 16, vm_address_t(UInt(bitPattern: pair)), &size) == KERN_SUCCESS else { break }
            buffer[n] = strip(UInt64(pair[1])); n += 1
            guard pair[0] > fp else { break }
            fp = pair[0]
        }
        return n
    }

    private func name(_ address: UInt) -> (image: String, symbol: String) {
        if let known = names[address] { return known }
        guard address > 1 else { return ("?", "?") }
        var info = Dl_info()
        var result = ("?", "?")
        if dladdr(UnsafeRawPointer(bitPattern: address - 1), &info) != 0 {
            let image = info.dli_fname.map { String(cString: $0).split(separator: "/").last.map(String.init) ?? "?" } ?? "?"
            // System names are hidden on the phone: the function's place in its library instead, named later from the
            // phone's own symbols (pymobiledevice3 developer fetch-symbols).
            let symbol = info.dli_sname.map { String(cString: $0) }
            let start = UInt(bitPattern: info.dli_saddr ?? UnsafeMutableRawPointer(bitPattern: address - 1))
            let base = UInt(bitPattern: info.dli_fbase)
            result = (image, symbol == nil || symbol == "<redacted>" ? "+0x" + String(start &- base, radix: 16) : demangle(symbol!))
        }
        names[address] = result
        return result
    }

    private func demangle(_ symbol: String) -> String {
        typealias Fn = @convention(c) (UnsafePointer<CChar>?, Int, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?, UInt32) -> UnsafeMutablePointer<CChar>?
        guard symbol.hasPrefix("$s"), let f = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swift_demangle") else { return symbol }
        let fn = unsafeBitCast(f, to: Fn.self)
        guard let out = symbol.withCString({ fn($0, strlen($0), nil, nil, 0) }) else { return symbol }
        defer { free(out) }
        return String(cString: out)
    }

    /// Busy samples (1 ms each; idle ones only counted): self time by image, then the heaviest frames (inclusive).
    private func report(_ action: String, _ stacks: [[UInt]]) {
        let named = stacks.map { $0.map(name) }
        var images: [String: Int] = [:], frames: [String: Int] = [:], ours: [String: Int] = [:], leaves: [String: Int] = [:]
        for stack in named {
            images[stack[0].image, default: 0] += 1
            leaves["\(stack[0].image)`\(stack[0].symbol)", default: 0] += 1
            for frame in Set(stack.map { "\($0.image)`\($0.symbol)" }) { frames[frame, default: 0] += 1 }
            for frame in Set(stack.filter { $0.image == "Track" }.map(\.symbol)) { ours[frame, default: 0] += 1 }
        }
        let top = { (d: [String: Int], k: Int) in d.sorted { $0.value > $1.value }.prefix(k) }
        log.log("probe \(action, privacy: .public): \(named.count) busy samples, \(self.idle) idle")
        for (k, v) in top(images, 6) { log.log("probe \(action, privacy: .public) self \(v) \(k, privacy: .public)") }
        for (k, v) in top(leaves, 20) { log.log("probe \(action, privacy: .public) leaf \(v) \(String(k.prefix(200)), privacy: .public)") }
        for (k, v) in top(frames, 80) { log.log("probe \(action, privacy: .public) incl \(v) \(String(k.prefix(200)), privacy: .public)") }
        for (k, v) in top(ours, 15) { log.log("probe \(action, privacy: .public) ours \(v) \(String(k.prefix(200)), privacy: .public)") }
    }
}

/// Bench-only A/B switches: each turns one kind of motion off (as Reduce Motion does), or one speed-up on, so a part
/// that drops frames can be checked against the other way on one install.
enum AB {
    private static let args = ProcessInfo.processInfo.arguments
    /// The workout's cards built as they scroll into view (Start workout spent ~165 ms in SwiftUI on 22 cards).
    static let lazyCards = args.contains("-ab-lazy")
    /// iOS's keyboard loaded once, out of sight, after launch, so the first field tapped doesn't wait for it (Keyboard
    /// up 62 → 47 ms, down 37 → 18 ms on the iPhone 13); -ab-cold-keyboard measures without.
    static let warmKeyboard = !args.contains("-ab-cold-keyboard")
    /// Card open, measuring only: raised and sunk surfaces as plain fills (their cost in a card's first frame).
    static let flatSurfaces = args.contains("-ab-flat")
    /// Card open, measuring only: the workout's cards without their shared glide (matchedGeometryEffect).
    static let noGlide = args.contains("-ab-no-glide")
    /// Card open: every card's sets built once and kept, shut, so opening one only uncovers it (it took ~20 ms to build).
    static let builtSets = args.contains("-ab-built-sets")
    /// Card open, measuring only: a card's sets without their rows (what the rows cost against the rest).
    static let noRows = args.contains("-ab-no-rows")
    /// Card open, measuring only: rows without their swipe and hold (a UIKit recognizer each).
    static let noSwipe = args.contains("-ab-no-swipe")
    /// Card open, measuring only: a row's numbers without shrinking to fit (each measured at several sizes).
    static let plainText = args.contains("-ab-plain-text")
    /// The four tabs back in the app's own view tree (before build 83), to measure what keeping them there costs.
    static let sharedTabs = args.contains("-ab-shared-tabs")
    /// Cards without .geometryGroup() (before build 84), to measure what it saves.
    static let noGeometryGroup = args.contains("-ab-no-geometry-group")
    /// Drawing costs, measuring only: no drop shadow on raised surfaces, no inner shadow in sunk ones, each surface
    /// flattened into one layer (drawingGroup).
    static let noShadow = args.contains("-ab-no-shadow")
    static let noInner = args.contains("-ab-no-inner")
    static let surfaceGroup = args.contains("-ab-surface-group")
    static let stillSheets = args.contains("-still-sheets")   // sheets and the question
    static let stillToast = args.contains("-still-toast")
    static let stillPages = args.contains("-still-pages")     // a screen's content shifting in
    static let stillRest = args.contains("-still-rest")
    static let stillTap = args.contains("-still-tap")         // a tap's change (Motion.tap): cards, rows, arranging
    /// The workout's page as before build 97, one SwiftUI ScrollView, to measure against.
    static let swiftUIList = args.contains("-ab-swiftui-list")
    /// The workout's page as a UIKit list (CardList).
    static let uikitList = !swiftUIList
    /// That list's changes shown at once, without iOS animating the heights (what the animation costs there).
    static let stillList = args.contains("-ab-still-list")
    /// That list's cards drawn by UIKit (CardView), not SwiftUI.
    static let uikitCard = !swiftUIList
    /// Those cards changed in place (a card opened) update their own views and resize in the list's animation,
    /// without a snapshot (the list's own update took ~12 ms of a card open on the iPhone 13).
    static let directCards = args.contains("-ab-direct-cards")
    /// Cards in view build what they open in idle turns, so a tap only shows it (building took ~7 ms of a first open).
    static let prebuiltSets = !swiftUIList
    /// The page as one scroll view placing every row itself (CardList.Placed), no collection view.
    static let ownList = !swiftUIList
    /// Screens: their shift and fade start on the frame after the screen was built, not in the build's own update
    /// (the video showed a page's move begin with a jump and a stutter while its first frame took 30-70 ms).
    static let lateArrive = args.contains("-ab-late-arrive")
    /// Measuring only: an empty page in place of a split, lift, past workout or Settings, and an empty sheet (the
    /// screen's own content against what's around it).
    static let emptyPages = args.contains("-ab-empty-pages")
    static let emptySheets = args.contains("-ab-empty-sheets")
    /// Tabs: a hidden one stays in the window, hidden, not taken out (what coming back into the window costs).
    static let attachedTabs = args.contains("-ab-attached-tabs")
    /// Measuring only: a screen's arrival only shifts (no fade), or only fades (no shift): which one the screen
    /// recording's stutter comes from.
    static let shiftOnly = args.contains("-ab-shift-only")
    static let fadeOnly = args.contains("-ab-fade-only")
    /// Tabs: the one shown comes in by Core Animation, flattened to one layer as it moves, not by SwiftUI's Arrive.
    static let caTabs = args.contains("-ab-ca-tabs")
}

extension View {
    /// .geometryGroup(), unless an AB switch measures without it.
    @ViewBuilder func geometryGroup(when on: Bool) -> some View {
        if on { geometryGroup() } else { self }
    }

    /// .drawingGroup(), only while an AB switch measures it.
    @ViewBuilder func drawingGroup(when on: Bool) -> some View {
        if on { drawingGroup() } else { self }
    }
}
