import Foundation
import QuartzCore
import SwiftUI
import os

/// shortcut: temporary, for the 60 Hz pass (remove once measured). -probe samples the main thread's stack every
/// millisecond for a second after each PerfDrive action and logs where its busy time went (device log "Track probe").
enum Probe {
    static let args = ProcessInfo.processInfo.arguments
    static func has(_ flag: String) -> Bool { args.contains(flag) }
}

final class Sampler: Thread, @unchecked Sendable {
    static var shared: Sampler?
    private let target: thread_act_t
    private let lock = NSLock()
    private var window: (name: String, until: CFTimeInterval)?
    private var stacks: [[UInt]] = []
    private let buffer = UnsafeMutablePointer<UInt>.allocate(capacity: 256)
    private let pair = UnsafeMutablePointer<UInt>.allocate(capacity: 2)
    private var names: [UInt: (image: String, symbol: String)] = [:]
    /// The main thread is waiting in its run loop (set by its own observers), so a sample there would only show idling.
    fileprivate var waiting = false
    private var idle = 0
    private let log = Logger(subsystem: "Track", category: "probe")

    /// From the main thread.
    static func install() {
        guard Probe.args.contains("-probe"), shared == nil else { return }
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

    static func begin(_ name: String) {
        guard let s = shared else { return }
        s.lock.lock(); s.window = (name, CACurrentMediaTime() + 1); s.lock.unlock()
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
            result = (image, info.dli_sname.map { demangle(String(cString: $0)) } ?? "?")
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

    /// Busy samples (the idle ones are only counted): self time by image, then the heaviest frames (inclusive).
    private func report(_ action: String, _ stacks: [[UInt]]) {
        let named = stacks.map { $0.map(name) }
        let busy = named
        var images: [String: Int] = [:], frames: [String: Int] = [:], ours: [String: Int] = [:]
        for stack in busy {
            images[stack[0].image, default: 0] += 1
            for frame in Set(stack.map { "\($0.image)`\($0.symbol)" }) { frames[frame, default: 0] += 1 }
            for frame in Set(stack.filter { $0.image == "Track" }.map(\.symbol)) { ours[frame, default: 0] += 1 }
        }
        let line = { (d: [String: Int], k: Int) in d.sorted { $0.value > $1.value }.prefix(k) }
        log.log("probe \(action, privacy: .public): \(busy.count) busy samples, \(self.idle) idle")
        for (k, v) in line(images, 12) { log.log("probe \(action, privacy: .public) self \(v) \(k, privacy: .public)") }
        for (k, v) in line(frames, 60) { log.log("probe \(action, privacy: .public) incl \(v) \(String(k.prefix(300)), privacy: .public)") }
        for (k, v) in line(ours, 40) { log.log("probe \(action, privacy: .public) ours \(v) \(String(k.prefix(300)), privacy: .public)") }
        // Whole paths, leaf first (Apple's own names are hidden on the phone, so their images stand in): who drew.
        var chains: [String: Int] = [:]
        for stack in busy {
            var parts: [String] = []
            for frame in stack {
                let part = frame.symbol == "<redacted>" || frame.symbol == "?" ? frame.image : "\(frame.image)`\(frame.symbol.prefix(60))"
                if parts.last != part { parts.append(part) }
                if parts.count == 14 { break }
            }
            chains[parts.joined(separator: " < "), default: 0] += 1
        }
        for (k, v) in line(chains, 12) { log.log("probe \(action, privacy: .public) chain \(v) \(String(k.prefix(900)), privacy: .public)") }
    }
}
