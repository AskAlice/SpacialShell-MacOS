import AppKit
import Darwin
import OSLog
import QuartzCore

/// #140 (G13): what a re-tile on the switch overlay costs, measured. A debug flag, and only
/// instruments: launch with `SPACIAL_LOG_RETILE=1` (e.g. `launchctl setenv SPACIAL_LOG_RETILE 1`,
/// then relaunch). It changes nothing about how a re-tile runs: that is `animate-retile` and
/// `MotionRules`. `Scripts/e2e/scenarios/perf/retile.scn` sets both.
///
/// Every re-tile the overlay animates logs one `retile N=…` line (category `motion`), and one
/// `retile N=… abandoned: <why>` when it is placed instantly after all (over the capture budget, a
/// capture failed, superseded). It emits signposts on `sh.emu.SpacialShell` / Points of Interest,
/// which Instruments' Time Profiler template records: intervals `retile` (command to landing),
/// `retile.capture`, `retile.shot` (one per picture), `retile.play`, and events `retile.shown` and
/// `retile.firstFrame`.
@MainActor
final class RetileProbe {
    nonisolated static let enabled = ProcessInfo.processInfo.environment["SPACIAL_LOG_RETILE"] == "1"
    nonisolated static let signposter = OSSignposter(subsystem: "sh.emu.SpacialShell", category: .pointsOfInterest)
    static let log = Logger(subsystem: "sh.emu.SpacialShell", category: "motion")

    let windows: Int
    /// The flight's length, for the frames it should have drawn.
    private let flight: CFTimeInterval
    private let since: ContinuousClock.Instant
    private let started = ContinuousClock.now
    private let cpu0 = RetileProbe.mainThreadCPU()
    private let whole: OSSignpostIntervalState
    private var captureState: OSSignpostIntervalState?
    private var playState: OSSignpostIntervalState?
    private var captureTotal: Duration = .zero
    private var windowShots: [Duration] = []
    private var backdropShots: [Duration] = []
    private var shownAt: ContinuousClock.Instant?
    private var firstFrame: Duration?
    private var ticks: [CFTimeInterval] = []
    private var period: CFTimeInterval = 1.0 / 60
    private var link: CADisplayLink?
    private var ticker: Ticker?
    private var done = false

    init(windows: Int, since: ContinuousClock.Instant, flight: CFTimeInterval) {
        self.windows = windows
        self.since = since
        self.flight = flight
        whole = Self.signposter.beginInterval("retile", id: Self.signposter.makeSignpostID(), "N=\(self.windows)")
    }

    func captureBegan() { captureState = Self.signposter.beginInterval("retile.capture", id: Self.signposter.makeSignpostID(), "N=\(self.windows)") }
    func captureEnded(_ total: Duration) {
        captureTotal = total
        if let s = captureState { Self.signposter.endInterval("retile.capture", s) }
    }
    func shot(window: Bool, _ d: Duration) { if window { windowShots.append(d) } else { backdropShots.append(d) } }

    func shown() {
        shownAt = .now
        Self.signposter.emitEvent("retile.shown", "N=\(self.windows)")
    }

    /// The motion starts: tick with the display from here to the landing.
    func playing(on view: NSView?) {
        playState = Self.signposter.beginInterval("retile.play", id: Self.signposter.makeSignpostID(), "N=\(self.windows)")
        guard let view else { return }
        let ticker = Ticker { [weak self] link in self?.tick(link) }
        let link = view.displayLink(target: ticker, selector: #selector(Ticker.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.ticker = ticker; self.link = link
    }

    private func tick(_ link: CADisplayLink) {
        if firstFrame == nil {
            firstFrame = .now - since
            Self.signposter.emitEvent("retile.firstFrame", "N=\(self.windows)")
        }
        if link.duration > 0 { period = link.duration }
        ticks.append(link.timestamp)
    }

    /// Landed: stop ticking, log the numbers.
    func landed() {
        guard !done else { return }
        done = true
        link?.invalidate(); link = nil; ticker = nil
        if let s = playState { Self.signposter.endInterval("retile.play", s) }
        Self.signposter.endInterval("retile", whole)
        let wall = ContinuousClock.now - started
        let cpu = Self.mainThreadCPU() - cpu0
        // A gap of k periods between ticks is k - 1 frames the display showed without us.
        var dropped = 0, maxGap = 0.0
        for (a, b) in zip(ticks, ticks.dropFirst()) {
            let gap = b - a
            maxGap = max(maxGap, gap)
            dropped += max(0, Int((gap / period).rounded()) - 1)
        }
        let perWindow = windowShots.isEmpty ? 0 : windowShots.map(Self.ms).reduce(0, +) / Double(windowShots.count)
        let worstWindow = windowShots.map(Self.ms).max() ?? 0
        let wallMs = Self.ms(wall)
        Self.log.notice("""
            retile N=\(self.windows) capture.total.ms=\(Self.ms(self.captureTotal), format: .fixed(precision: 1)) \
            capture.window.mean.ms=\(perWindow, format: .fixed(precision: 1)) capture.window.max.ms=\(worstWindow, format: .fixed(precision: 1)) \
            capture.backdrop.ms=\(self.backdropShots.map(Self.ms).max() ?? 0, format: .fixed(precision: 1)) \
            shown.ms=\(self.shownAt.map { Self.ms($0 - self.since) } ?? -1, format: .fixed(precision: 1)) \
            firstFrame.ms=\(self.firstFrame.map(Self.ms) ?? -1, format: .fixed(precision: 1)) \
            frames=\(self.ticks.count) expected=\(Int((self.flight / self.period).rounded())) dropped=\(dropped) \
            maxGap.ms=\(maxGap * 1000, format: .fixed(precision: 1)) hz=\(1 / self.period, format: .fixed(precision: 0)) \
            mainCPU.ms=\(cpu * 1000, format: .fixed(precision: 1)) wall.ms=\(wallMs, format: .fixed(precision: 1))
            """)
    }

    /// Dropped before landing (superseded, the watchdog, capture failed): no numbers.
    func abandoned(_ why: String) {
        guard !done else { return }
        done = true
        link?.invalidate(); link = nil; ticker = nil
        if let s = playState { Self.signposter.endInterval("retile.play", s) }
        Self.signposter.endInterval("retile", whole)
        Self.log.notice("retile N=\(self.windows) abandoned: \(why, privacy: .public)")
    }

    static func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    /// CPU time (user + system) of the calling thread, which is the main thread here.
    static func mainThreadCPU() -> Double {
        let port = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, port) }
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        func s(_ t: time_value_t) -> Double { Double(t.seconds) + Double(t.microseconds) / 1e6 }
        return s(info.user_time) + s(info.system_time)
    }
}

/// CADisplayLink wants an Objective-C target. It is added to the main run loop, so it ticks there.
@MainActor
private final class Ticker: NSObject {
    let body: @MainActor (CADisplayLink) -> Void
    init(_ body: @escaping @MainActor (CADisplayLink) -> Void) { self.body = body }
    @objc func tick(_ link: CADisplayLink) { body(link) }
}
