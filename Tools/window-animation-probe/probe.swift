// Throwaway probe: can a third-party macOS window manager animate other apps' windows, and how?
//
// Nothing here is shipped code, nothing is imported by any target, and it is not in Package.swift.
// Public API only — no @_silgen_name, no SkyLight — so `nm -u probe` is itself a result.
//
//     swiftc -O probe.swift -o probe
//     ./probe all <outdir> [reps] [targets...]   # full matrix; JSONL on stdout, notes on stderr
//     ./probe target                             # the child app the matrix animates (spawned by `all`)
//     ./probe sandboxcheck <bundle-id>           # AX + capture from inside App Sandbox (see RESULTS.md)
//
// Rules the probe keeps: it only animates windows it opened itself (a child process it spawns, or an
// app it launches with `open -F` and refuses to use if that app was already running), and it quits
// them afterwards. It never touches ~/.config/spacial-shell or Application Support.
//
// Instruments, all public:
//   - AX write latency: wall time around AXUIElementSetAttributeValue.
//   - Geometry: a thread polling CGWindowListCopyWindowInfo(.optionIncludingWindow) for the target's
//     bounds — what the window server says the frame is, independent of what we asked for.
//   - Content: an SCStream on the target window alone; a `.complete` frame means its pixels changed.
//   - Screen: an SCStream on the display region (sRGB, 1/4 scale), over a magenta backdrop window the
//     probe owns. Magenta inside a rect where a window (or the overlay) should be = a hole on screen.

import AppKit
import ApplicationServices
import CoreMedia
import QuartzCore
import ScreenCaptureKit

setvbuf(stdout, nil, _IOLBF, 0)

func now() -> Double { CACurrentMediaTime() }
func r1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
func msr(_ s: Double) -> Double { r1(s * 1000) }
func note(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

func pct(_ xs: [Double], _ p: Double) -> Double {
    guard !xs.isEmpty else { return .nan }
    let s = xs.sorted()
    return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
}

func latStats(_ prefix: String, _ xs: [Double], into d: inout [String: Any]) {
    guard !xs.isEmpty else { return }
    d[prefix + "N"] = xs.count
    d[prefix + "P50ms"] = msr(pct(xs, 0.5))
    d[prefix + "P95ms"] = msr(pct(xs, 0.95))
    d[prefix + "MaxMs"] = msr(xs.max()!)
}

let machScale: Double = {
    var tb = mach_timebase_info()
    mach_timebase_info(&tb)
    return Double(tb.numer) / Double(tb.denom) / 1e9
}()

// MARK: - Geometry

func lerp(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
    CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
           width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
}

func ease(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }

func close(_ a: CGRect, _ b: CGRect, _ tol: Double = 2) -> Bool {
    abs(a.minX - b.minX) <= tol && abs(a.minY - b.minY) <= tol
        && abs(a.width - b.width) <= tol && abs(a.height - b.height) <= tol
}

let primaryHeight = NSScreen.screens[0].frame.height
/// AX / CG use top-left global coordinates; AppKit windows use bottom-left.
func cocoa(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height) }

// MARK: - Accessibility

func axAttr<T>(_ e: AXUIElement, _ a: String) -> T? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success else { return nil }
    return v as? T
}

func axFrame(_ w: AXUIElement) -> CGRect? {
    guard let pv: AXValue = axAttr(w, kAXPositionAttribute), let sv: AXValue = axAttr(w, kAXSizeAttribute) else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pv, .cgPoint, &p)
    AXValueGetValue(sv, .cgSize, &s)
    return CGRect(origin: p, size: s)
}

@discardableResult func axSetPos(_ w: AXUIElement, _ p: CGPoint) -> AXError {
    var p = p
    return AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
}

@discardableResult func axSetSize(_ w: AXUIElement, _ s: CGSize) -> AXError {
    var s = s
    return AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
}

func axPlace(_ w: AXUIElement, _ r: CGRect) {
    axSetSize(w, r.size); axSetPos(w, r.origin); axSetSize(w, r.size)
}

func cgBounds(_ id: CGWindowID) -> CGRect? {
    guard let raw = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
          let b = raw.first?[kCGWindowBounds as String] as? [String: Any] else { return nil }
    return CGRect(dictionaryRepresentation: b as CFDictionary)
}

// MARK: - Instruments

/// Records every change of the target's window-server bounds, with the time it was observed.
final class GeoPoller {
    let id: CGWindowID
    private let lock = NSLock()
    private var running = true
    private(set) var changes: [(t: Double, r: CGRect)] = []
    private(set) var polls = 0

    init(_ id: CGWindowID) {
        self.id = id
        Thread { [self] in
            while lock.withLock({ running }) {
                let r = cgBounds(id)
                let t = now()
                lock.withLock {
                    polls += 1
                    if let r, changes.last.map({ $0.r != r }) ?? true { changes.append((t, r)) }
                }
                usleep(1000)
            }
        }.start()
    }

    func stop() -> [(t: Double, r: CGRect)] { lock.withLock { running = false; return changes } }
    func last() -> (t: Double, r: CGRect)? { lock.withLock { changes.last } }
    func at(_ t: Double, in cs: [(t: Double, r: CGRect)]) -> CGRect? { cs.last(where: { $0.t <= t })?.r ?? cs.first?.r }
}

final class Frame {
    let t: Double, w: Int, h: Int, px: [UInt8]
    init(t: Double, w: Int, h: Int, px: [UInt8]) { self.t = t; self.w = w; self.h = h; self.px = px }
}

final class Recorder: NSObject, SCStreamOutput {
    let keepPixels: Bool
    private let lock = NSLock()
    private var frames: [Frame] = []
    init(keepPixels: Bool) { self.keepPixels = keepPixels }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = arr.first, let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete
        else { return }
        let t = (info[.displayTime] as? UInt64).map { Double($0) * machScale } ?? now()
        var w = 0, h = 0, px: [UInt8] = []
        if keepPixels, let pb = CMSampleBufferGetImageBuffer(sb) {
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            w = CVPixelBufferGetWidth(pb); h = CVPixelBufferGetHeight(pb)
            let bpr = CVPixelBufferGetBytesPerRow(pb)
            let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
            px = [UInt8](repeating: 0, count: w * h * 4)
            px.withUnsafeMutableBytes { dst in
                for y in 0..<h { memcpy(dst.baseAddress! + y * w * 4, base + y * bpr, w * 4) }
            }
            CVPixelBufferUnlockBaseAddress(pb, .readOnly)
        }
        let f = Frame(t: t, w: w, h: h, px: px)
        lock.withLock { frames.append(f) }
    }

    func all() -> [Frame] { lock.withLock { frames } }
}

func startStream(_ filter: SCContentFilter, rect: CGRect?, w: Int, h: Int, pixels: Bool, hz: Int) async throws -> (SCStream, Recorder) {
    let cfg = SCStreamConfiguration()
    if let rect { cfg.sourceRect = rect }
    cfg.width = w; cfg.height = h
    cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(hz))
    cfg.queueDepth = 8
    cfg.pixelFormat = kCVPixelFormatType_32BGRA
    cfg.colorSpaceName = CGColorSpace.sRGB
    cfg.showsCursor = false
    let rec = Recorder(keepPixels: pixels)
    let s = SCStream(filter: filter, configuration: cfg, delegate: nil)
    try s.addStreamOutput(rec, type: .screen, sampleHandlerQueue: DispatchQueue(label: "rec"))
    try await s.startCapture()
    return (s, rec)
}

/// Pixel box of a global rect inside a region-scaled frame.
func box(_ r: CGRect, _ region: CGRect, _ f: Frame) -> (Int, Int, Int, Int)? {
    let rr = r.intersection(region)
    guard !rr.isNull, rr.width > 0, rr.height > 0 else { return nil }
    let sx = Double(f.w) / region.width, sy = Double(f.h) / region.height
    let x0 = max(0, Int((rr.minX - region.minX) * sx)), x1 = min(f.w, Int((rr.maxX - region.minX) * sx))
    let y0 = max(0, Int((rr.minY - region.minY) * sy)), y1 = min(f.h, Int((rr.maxY - region.minY) * sy))
    return x1 > x0 && y1 > y0 ? (x0, y0, x1, y1) : nil
}

func magenta(_ f: Frame, _ r: CGRect, _ region: CGRect) -> Double {
    guard let (x0, y0, x1, y1) = box(r, region, f) else { return 0 }
    var hit = 0, n = 0
    for y in stride(from: y0, to: y1, by: 1) {
        for x in stride(from: x0, to: x1, by: 1) {
            let i = (y * f.w + x) * 4
            n += 1
            if f.px[i + 2] > 200 && f.px[i + 1] < 70 && f.px[i] > 200 { hit += 1 }
        }
    }
    return n == 0 ? 0 : Double(hit) / Double(n)
}

func diff(_ a: Frame, _ b: Frame, _ r: CGRect, _ region: CGRect) -> Double {
    guard let (x0, y0, x1, y1) = box(r, region, a), a.w == b.w, a.h == b.h else { return .nan }
    var sum = 0, n = 0
    for y in y0..<y1 {
        for x in x0..<x1 {
            let i = (y * a.w + x) * 4
            sum += abs(Int(a.px[i]) - Int(b.px[i])) + abs(Int(a.px[i + 1]) - Int(b.px[i + 1])) + abs(Int(a.px[i + 2]) - Int(b.px[i + 2]))
            n += 3
        }
    }
    return n == 0 ? .nan : Double(sum) / Double(n)
}

func savePNG(_ f: Frame, _ path: String) {
    var px = f.px
    let ctx = px.withUnsafeMutableBytes { buf in
        CGContext(data: buf.baseAddress, width: f.w, height: f.h, bitsPerComponent: 8, bytesPerRow: f.w * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)?.makeImage()
    }
    guard let img = ctx, let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

/// Update rate and worst gap of a set of event times inside [t0, t1].
func cadence(_ ts: [Double], _ t0: Double, _ t1: Double, _ prefix: String, into d: inout [String: Any]) {
    let inside = ts.filter { $0 >= t0 && $0 <= t1 }
    d[prefix + "Updates"] = inside.count
    d[prefix + "Hz"] = r1(Double(inside.count) / max(1e-3, t1 - t0))
    var gaps: [Double] = []
    var prev = t0
    for t in inside { gaps.append(t - prev); prev = t }
    gaps.append(t1 - prev)
    d[prefix + "MaxGapMs"] = msr(gaps.max() ?? (t1 - t0))
}

func onThread<T>(_ body: @escaping () -> T) async -> T {
    await withCheckedContinuation { c in Thread { c.resume(returning: body()) }.start() }
}

func sleepMs(_ ms: Double) async { try? await Task.sleep(nanoseconds: UInt64(ms * 1e6)) }

/// How long the overlay is given to reach the screen before the real window is parked under it.
let showWaitMs = Double(ProcessInfo.processInfo.environment["SHOW_WAIT_MS"] ?? "") ?? 25

// MARK: - Targets

struct Target {
    let name: String
    let bundleID: String?
    let openArgs: [String]
    let title: String?
}

final class Launched {
    let target: Target
    let pid: pid_t
    let window: AXUIElement
    let cgID: CGWindowID
    let child: Process?
    init(target: Target, pid: pid_t, window: AXUIElement, cgID: CGWindowID, child: Process?) {
        self.target = target; self.pid = pid; self.window = window; self.cgID = cgID; self.child = child
    }
}

struct ProbeError: Error, CustomStringConvertible { let description: String }

func findAXWindow(_ pid: pid_t, title: String?) async -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1.0)
    for _ in 0..<150 {
        let ws: [AXUIElement] = axAttr(app, kAXWindowsAttribute) ?? []
        for w in ws {
            let sub: String? = axAttr(w, kAXSubroleAttribute)
            let t: String = axAttr(w, kAXTitleAttribute) ?? ""
            if sub == kAXStandardWindowSubrole, title.map({ t.contains($0) }) ?? true { return w }
        }
        await sleepMs(100)
    }
    return nil
}

func findCGID(_ pid: pid_t, near r: CGRect) async -> CGWindowID? {
    for _ in 0..<20 {
        if let c = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) {
            let cands = c.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 }
            func dist(_ w: SCWindow) -> Double {
                abs(w.frame.minX - r.minX) + abs(w.frame.minY - r.minY) + abs(w.frame.width - r.width) + abs(w.frame.height - r.height)
            }
            if let best = cands.min(by: { dist($0) < dist($1) }), dist(best) < 4 { return best.windowID }
        }
        await sleepMs(100)
    }
    return nil
}

func launch(_ t: Target, place r: CGRect) async throws -> Launched {
    var child: Process?
    let pid: pid_t
    if let bid = t.bundleID {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bid).isEmpty else {
            throw ProbeError(description: "\(bid) already running — refusing to touch the user's app")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = t.openArgs
        try p.run(); p.waitUntilExit()
        var found: pid_t?
        for _ in 0..<150 {
            if let a = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first { found = a.processIdentifier; break }
            await sleepMs(100)
        }
        guard let found else { throw ProbeError(description: "\(bid) did not launch") }
        pid = found
    } else {
        let p = Process()
        p.executableURL = Bundle.main.executableURL
        p.arguments = ["target"]
        try p.run()
        child = p
        pid = p.processIdentifier
    }
    guard let w = await findAXWindow(pid, title: t.title) else { throw ProbeError(description: "\(t.name): no AX window") }
    axPlace(w, r)
    await sleepMs(400)
    guard let f = axFrame(w), let id = await findCGID(pid, near: f) else { throw ProbeError(description: "\(t.name): no CG window") }
    return Launched(target: t, pid: pid, window: w, cgID: id, child: child)
}

func quit(_ l: Launched) {
    if let c = l.child { c.terminate(); c.waitUntilExit(); return }
    guard let a = NSRunningApplication(processIdentifier: l.pid) else { return }
    a.terminate()
    for _ in 0..<50 where !a.isTerminated { usleep(100_000) }
    if !a.isTerminated { a.forceTerminate() }
}

func raise(_ l: Launched) {
    NSRunningApplication(processIdentifier: l.pid)?.activate()
    AXUIElementPerformAction(l.window, kAXRaiseAction as CFString)
}

// MARK: - The child app

func runTarget() -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 700, height: 500),
                     styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    w.title = "probe-target"
    let scroll = NSTextView.scrollableTextView()
    (scroll.documentView as! NSTextView).string = String(repeating: lorem, count: 400)
    w.contentView = scroll
    w.makeKeyAndOrderFront(nil)
    app.activate()
    app.run()
    exit(0)
}

let lorem = """
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore \
magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo \
consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.

"""

// MARK: - Shared scene

@MainActor final class Scene {
    let region: CGRect
    let backdrop: NSWindow
    let display: SCDisplay
    let hz: Int

    init(region: CGRect, display: SCDisplay, hz: Int) {
        self.region = region; self.display = display; self.hz = hz
        backdrop = NSWindow(contentRect: cocoa(region), styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        backdrop.isOpaque = true
        backdrop.hasShadow = false
        backdrop.ignoresMouseEvents = true
        backdrop.isReleasedWhenClosed = false
        backdrop.orderFrontRegardless()
    }

    func screenStream() async throws -> (SCStream, Recorder) {
        try await startStream(SCContentFilter(display: display, excludingWindows: []), rect: region,
                              w: Int(region.width / 4), h: Int(region.height / 4), pixels: true, hz: hz)
    }
}

func waitSettle(_ g: GeoPoller, target: CGRect, after t0: Double, timeout: Double = 1.5) async -> (t: Double, reached: Bool) {
    let start = now()
    while now() - start < timeout {
        if let l = g.last() {
            if close(l.r, target) { return (max(l.t, t0), true) }
            if now() - l.t > 0.3 && now() - start > 0.3 { return (max(l.t, t0), false) }
        }
        await sleepMs(2)
    }
    return (now(), false)
}

// MARK: - Mechanism 1 + 3a: stepped AX writes (and hybrid: one size write, stepped position)

struct StepResult { var pos: [Double] = [], size: [Double] = [], errors = 0, writes = 0, start = 0.0, end = 0.0 }

func steppedLoop(_ w: AXUIElement, mode: String, from: CGRect, to: CGRect, dur: Double, hz: Double) -> StepResult {
    var r = StepResult()
    if mode == "hybrid" {
        let a = now()
        if axSetSize(w, to.size) != .success { r.errors += 1 }
        r.size.append(now() - a)
    }
    r.start = now()
    while true {
        let p = min(1, (now() - r.start) / dur)
        let f = lerp(from, to, ease(p))
        if mode != "resize" {
            let a = now()
            if axSetPos(w, f.origin) != .success { r.errors += 1 }
            r.pos.append(now() - a)
        }
        if mode == "resize" || mode == "both" {
            let a = now()
            if axSetSize(w, f.size) != .success { r.errors += 1 }
            r.size.append(now() - a)
        }
        r.writes += 1
        if p >= 1 { break }
        let wait = r.start + Double(r.writes) / hz - now()
        if wait > 0 { usleep(UInt32(wait * 1e6)) }
    }
    r.end = now()
    return r
}

@MainActor func runStepped(_ l: Launched, _ scene: Scene, mode: String, from: CGRect, to: CGRect, dur: Double,
                           snap: String?) async throws -> [String: Any] {
    axPlace(l.window, from)
    raise(l)
    await sleepMs(400)
    let geo = GeoPoller(l.cgID)
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    guard let scw = content.windows.first(where: { $0.windowID == l.cgID }) else { throw ProbeError(description: "window gone") }
    let (ws, wrec) = try await startStream(SCContentFilter(desktopIndependentWindow: scw), rect: nil, w: 320, h: 240, pixels: false, hz: scene.hz)
    let (ds, drec) = try await scene.screenStream()
    await sleepMs(300)

    let hz = Double(scene.hz)
    let res = await onThread { steppedLoop(l.window, mode: mode, from: from, to: to, dur: dur, hz: hz) }
    let settle = await waitSettle(geo, target: to, after: res.end)
    await sleepMs(300)
    try? await ws.stopCapture(); try? await ds.stopCapture()
    let changes = geo.stop()
    let wframes = wrec.all(), dframes = drec.all()

    var d: [String: Any] = ["target": l.target.name, "mech": "stepped-\(mode)", "durMs": msr(dur)]
    d["writes"] = res.writes
    d["writeHz"] = r1(Double(res.writes) / (res.end - res.start))
    d["axErrors"] = res.errors
    d["loopMs"] = msr(res.end - res.start)
    latStats("pos", res.pos, into: &d)
    latStats("size", res.size, into: &d)
    let tEnd = settle.t
    d["reachedTarget"] = settle.reached
    d["tailMs"] = msr(max(0, tEnd - res.end))
    d["finalFrame"] = changes.last.map { "\($0.r)" } ?? "?"
    cadence(changes.map(\.t), res.start, tEnd, "geo", into: &d)
    cadence(wframes.map(\.t), res.start, tEnd, "content", into: &d)
    cadence(dframes.map(\.t), res.start, tEnd, "screen", into: &d)
    // Holes: magenta inside where the window must be. A screen frame can show the window at the geometry
    // sample before it or the one after it (poll time is not display time), so only pixels inside BOTH
    // rects, inset 24 pt, count — a moving window cannot fake a hole by being one poll ahead.
    let base = dframes.last(where: { $0.t < res.start }).map { magenta($0, from.insetBy(dx: 24, dy: 24), scene.region) } ?? 0
    var holes = 0, worst = 0.0, inWindow = 0
    var worstFrame: Frame?
    for f in dframes where f.t >= res.start && f.t <= tEnd + 0.2 {
        guard let g = geo.at(f.t, in: changes) else { continue }
        let next = changes.first(where: { $0.t > f.t })?.r ?? g
        let r = g.intersection(next).insetBy(dx: 24, dy: 24)
        guard !r.isNull, r.width > 40, r.height > 40 else { continue }
        inWindow += 1
        let m = magenta(f, r, scene.region) - base
        if m > worst { worst = m; worstFrame = f }
        if m > 0.03 { holes += 1 }
    }
    d["holeFrames"] = holes
    d["screenFramesChecked"] = inWindow
    d["worstHolePct"] = r1(worst * 100)
    if let snap, let worstFrame, worst > 0.03 { savePNG(worstFrame, "\(snap)-worsthole.png") }
    d["pollsPerSec"] = r1(Double(geo.polls) / max(1e-3, now() - res.start + 1))
    if let snap {
        let mid = dframes.filter { $0.t >= res.start && $0.t <= tEnd }
        for (i, f) in mid.enumerated() where i % max(1, mid.count / 6) == 0 { savePNG(f, "\(snap)-\(i).png") }
    }
    return d
}

// MARK: - Mechanism 2 + 3b: snapshot overlay (optionally resizing the real window while it is parked)

@MainActor func runOverlay(_ l: Launched, _ scene: Scene, variant: String, removal: String, from: CGRect, to: CGRect,
                           dur: Double, park: CGPoint, snap: String?) async throws -> [String: Any] {
    axPlace(l.window, from)
    raise(l)
    await sleepMs(400)
    let geo = GeoPoller(l.cgID)
    // The overlay window is persistent in a real WM, so it is created (empty, click-through) before the
    // timed path starts. It also gets its own window stream: the only instrument that sees the overlay's
    // real render cadence (the display-region stream is capped — see `calib`).
    let ow = NSWindow(contentRect: cocoa(scene.region), styleMask: .borderless, backing: .buffered, defer: false)
    ow.isOpaque = false; ow.backgroundColor = .clear; ow.hasShadow = false; ow.ignoresMouseEvents = true
    ow.level = .floating; ow.isReleasedWhenClosed = false
    let view = NSView(frame: NSRect(origin: .zero, size: scene.region.size))
    let root = CALayer()
    view.layer = root; view.wantsLayer = true
    ow.contentView = view
    // Layer rects in the view's own bottom-left space. (A first version set `isGeometryFlipped` on this
    // layer-hosting view's root; AppKit does not reliably honour it, and some frames drew the snapshot
    // vertically mirrored — measured, see RESULTS.md.)
    func layerRect(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX - scene.region.minX, y: scene.region.maxY - r.maxY, width: r.width, height: r.height)
    }
    ow.orderFrontRegardless()
    await sleepMs(150)
    let pre = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let ovw = pre.windows.first(where: { $0.windowID == CGWindowID(ow.windowNumber) }) else { throw ProbeError(description: "overlay not listed") }
    let (os, orec) = try await startStream(SCContentFilter(desktopIndependentWindow: ovw), rect: nil, w: 320, h: 160, pixels: false, hz: scene.hz)
    let (ds, drec) = try await scene.screenStream()
    await sleepMs(300)

    let tCmd = now()
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    let tContent = now()
    guard let scw = content.windows.first(where: { $0.windowID == l.cgID }) else { throw ProbeError(description: "window gone") }
    let scale = NSScreen.screens.first(where: { $0.frame.intersects(cocoa(from)) })?.backingScaleFactor ?? 1
    let cfg = SCStreamConfiguration()
    cfg.width = Int(scw.frame.width * scale); cfg.height = Int(scw.frame.height * scale)
    cfg.showsCursor = false
    cfg.ignoreShadowsSingleWindow = true
    let img = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: scw), configuration: cfg)
    let tCapture = now()

    let snapLayer = CALayer()
    snapLayer.contents = img
    snapLayer.contentsGravity = .resize
    snapLayer.contentsScale = scale
    CATransaction.begin(); CATransaction.setDisableActions(true)
    snapLayer.frame = layerRect(scw.frame)
    root.addSublayer(snapLayer)
    CATransaction.commit()
    CATransaction.flush()
    await sleepMs(showWaitMs)
    let tShown = now()

    let p0 = now()
    axSetPos(l.window, park)
    if variant == "parkresize" { axSetSize(l.window, to.size) }
    let tParked = now()

    let tA0 = now()
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        CATransaction.begin()
        CATransaction.setAnimationDuration(dur)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.setCompletionBlock { c.resume() }
        snapLayer.frame = layerRect(to)
        CATransaction.commit()
    }
    let tA1 = now()

    let w0 = now()
    if variant == "endwrite" { axSetSize(l.window, to.size); axSetPos(l.window, to.origin); axSetSize(l.window, to.size) }
    else { axSetPos(l.window, to.origin) }
    let w1 = now()
    var settle = (t: w1, reached: false)
    if removal != "immediate" { settle = await waitSettle(geo, target: to, after: w1) }
    if removal == "settled2f" { await sleepMs(1000.0 / Double(scene.hz) * 2) }
    let tRemove = now()
    ow.orderOut(nil)
    CATransaction.flush()
    await sleepMs(500)
    try? await ds.stopCapture(); try? await os.stopCapture()
    let changes = geo.stop()
    if removal == "immediate" { settle = (changes.first(where: { $0.t >= w0 && close($0.r, to) })?.t ?? tRemove, changes.last.map { close($0.r, to) } ?? false) }
    let frames = drec.all()

    var d: [String: Any] = ["target": l.target.name, "mech": "overlay-\(variant)-\(removal)", "durMs": msr(dur)]
    d["shareableContentMs"] = msr(tContent - tCmd)
    d["captureMs"] = msr(tCapture - tContent)
    d["overlayShowMs"] = msr(tShown - tCapture)
    d["commandToMotionMs"] = msr(tA0 - tCmd)
    d["parkWriteMs"] = msr(tParked - p0)
    d["animMs"] = msr(tA1 - tA0)
    d["finalWriteMs"] = msr(w1 - w0)
    d["settleAfterWriteMs"] = msr(max(0, settle.t - w0))
    d["reachedTarget"] = settle.reached
    d["removeAfterWriteMs"] = msr(tRemove - w0)
    d["imagePx"] = "\(img.width)x\(img.height)"
    cadence(frames.map(\.t), tA0, tA1, "screen", into: &d)
    cadence(orec.all().map(\.t), tA0, tA1, "overlayRender", into: &d)

    // Show: the overlay lands on top of the real window, then the window is parked. Holes at the origin?
    let inFrom = scw.frame.insetBy(dx: 40, dy: 40), inTo = to.insetBy(dx: 40, dy: 40)
    let before = frames.last(where: { $0.t < tCmd })
    let baseFrom = before.map { magenta($0, inFrom, scene.region) } ?? 0
    let showHoles = frames.filter { $0.t >= tShown - 0.05 && $0.t <= tA0 + 0.03 && magenta($0, inFrom, scene.region) - baseFrom > 0.03 }
    d["showHoleFrames"] = showHoles.count
    d["showHoleMsAfterPark"] = showHoles.map { msr($0.t - p0) }
    if let snap { for (i, f) in showHoles.prefix(4).enumerated() { savePNG(f, "\(snap)-showhole-\(i).png") } }
    if let before, let afterPark = frames.last(where: { $0.t <= tA0 + 0.005 }) {
        d["showPopDiff"] = r1(diff(before, afterPark, scw.frame.insetBy(dx: 8, dy: 8), scene.region))
    }
    // Hand-off: after the overlay is ordered out, is there a hole where the window should be?
    let post = frames.filter { $0.t >= tRemove && $0.t <= tRemove + 0.3 }
    d["handoffFramesChecked"] = post.count
    d["handoffHoleFrames"] = post.filter { magenta($0, inTo, scene.region) > 0.03 }.count
    d["handoffWorstHolePct"] = r1((post.map { magenta($0, inTo, scene.region) }.max() ?? 0) * 100)
    if let last = frames.last(where: { $0.t < tRemove }), let final = frames.last {
        let rect = to.insetBy(dx: 8, dy: 8)
        d["swapPopDiff"] = r1(diff(last, final, rect, scene.region))
        var prev = last, worst = 0.0
        for f in post { worst = max(worst, diff(prev, f, rect, scene.region)); prev = f }
        d["handoffWorstStepDiff"] = r1(worst)
    }
    if let snap {
        let pick = frames.filter { $0.t >= tRemove - 0.03 && $0.t <= tRemove + 0.1 }
        for (i, f) in pick.prefix(8).enumerated() { savePNG(f, "\(snap)-handoff-\(i).png") }
        if let mid = frames.first(where: { $0.t >= (tA0 + tA1) / 2 }) { savePNG(mid, "\(snap)-mid.png") }
        if let shown = frames.first(where: { $0.t >= tParked + 0.005 }) { savePNG(shown, "\(snap)-parked.png") }
    }
    ow.close()
    return d
}

// MARK: - Capture cost on its own

func captureCost(_ l: Launched, reps: Int) async -> [String: Any] {
    var sc: [Double] = [], cap: [Double] = []
    var px = ""
    for _ in 0..<reps {
        let a = now()
        guard let c = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let w = c.windows.first(where: { $0.windowID == l.cgID }) else { continue }
        let b = now()
        let cfg = SCStreamConfiguration()
        let scale = NSScreen.screens.first(where: { $0.frame.intersects(cocoa(w.frame)) })?.backingScaleFactor ?? 1
        cfg.width = Int(w.frame.width * scale); cfg.height = Int(w.frame.height * scale)
        cfg.showsCursor = false
        guard let img = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg) else { continue }
        let e = now()
        sc.append(b - a); cap.append(e - b); px = "\(img.width)x\(img.height)"
    }
    var d: [String: Any] = ["target": l.target.name, "mech": "capture-cost", "imagePx": px]
    latStats("shareableContent", sc, into: &d)
    latStats("capture", cap, into: &d)
    return d
}

// MARK: - Driver

func emit(_ d: [String: Any], _ runs: inout [[String: Any]]) {
    runs.append(d)
    if let j = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]) { print(String(data: j, encoding: .utf8)!) }
}

@MainActor func driveAll(out: String, reps: Int, names: [String]) async {
    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    let doc = out + "/probe-doc.txt"
    try? String(repeating: lorem, count: 1500).write(toFile: doc, atomically: true, encoding: .utf8)
    let catalog = [
        Target(name: "child-appkit-textview", bundleID: nil, openArgs: [], title: "probe-target"),
        Target(name: "TextEdit", bundleID: "com.apple.TextEdit", openArgs: ["-F", "-a", "TextEdit", doc], title: "probe-doc"),
        Target(name: "Calculator", bundleID: "com.apple.calculator", openArgs: ["-F", "-a", "Calculator"], title: nil),
        Target(name: "Preview", bundleID: "com.apple.Preview", openArgs: ["-F", "-a", "Preview", "/System/Library/Desktop Pictures/Mac Yellow.heic"], title: "Mac Yellow"),
        Target(name: "ActivityMonitor", bundleID: "com.apple.ActivityMonitor", openArgs: ["-F", "-a", "Activity Monitor"], title: "Activity Monitor"),
    ]
    let targets = names.isEmpty ? catalog : catalog.filter { names.contains($0.name) }

    let screen = NSScreen.screens[0]
    let hz = screen.maximumFramesPerSecond
    let mainID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
    guard let sc = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
          let display = sc.displays.first(where: { $0.displayID == mainID }) else { note("no SCDisplay (Screen Recording?)"); return }
    note("AXIsProcessTrusted=\(AXIsProcessTrusted()) screenRecording=\(CGPreflightScreenCaptureAccess()) main=\(screen.frame) \(hz)Hz scale=\(screen.backingScaleFactor)")

    let vis = screen.visibleFrame
    let top = primaryHeight - vis.maxY
    let wantA = CGRect(x: vis.minX + 120, y: top + 100, width: 900, height: 620)
    let wantB = CGRect(x: vis.minX + 1100, y: top + 300, width: 1300, height: 900)
    let park = CGPoint(x: screen.frame.maxX - 1, y: primaryHeight - screen.frame.minY - 1)
    let dur = 0.3
    var runs: [[String: Any]] = []

    for t in targets {
        note("== \(t.name)")
        let l: Launched
        do { l = try await launch(t, place: wantA) } catch { note("skip: \(error)"); continue }
        // Feasible endpoints: what the app actually accepts for A and B.
        axPlace(l.window, wantA); await sleepMs(300)
        let a = axFrame(l.window) ?? wantA
        axPlace(l.window, wantB); await sleepMs(300)
        let b = axFrame(l.window) ?? wantB
        emit(["target": t.name, "mech": "endpoints", "A": "\(a)", "B": "\(b)", "resizable": a.size != b.size], &runs)
        let region = a.union(b).insetBy(dx: -60, dy: -60).intersection(CGRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height))
        let scene = Scene(region: region, display: display, hz: hz)
        raise(l)
        await sleepMs(500)

        // ONLY=stepped / ONLY=overlay reruns one half of the matrix.
        let only = ProcessInfo.processInfo.environment["ONLY"]
        if only == nil { emit(await captureCost(l, reps: 10), &runs) }

        let modes: [(String, CGRect, CGRect)] = [
            ("move", a, CGRect(origin: b.origin, size: a.size)),
            ("resize", a, CGRect(origin: a.origin, size: b.size)),
            ("both", a, b),
            ("hybrid", a, b),
        ]
        for (mode, f, to) in modes where only != "overlay" {
            for rep in 0..<reps {
                let (x, y) = rep % 2 == 0 ? (f, to) : (to, f)
                do {
                    emit(try await runStepped(l, scene, mode: mode, from: x, to: y, dur: dur,
                                              snap: rep == 0 ? "\(out)/\(t.name)-stepped-\(mode)" : nil), &runs)
                } catch { note("stepped \(mode): \(error)") }
            }
        }
        for variant in ["endwrite", "parkresize"] where only != "stepped" {
            for removal in ["immediate", "settled", "settled2f"] {
                for rep in 0..<reps {
                    let (x, y) = rep % 2 == 0 ? (a, b) : (b, a)
                    do {
                        emit(try await runOverlay(l, scene, variant: variant, removal: removal, from: x, to: y, dur: dur, park: park,
                                                  snap: rep == 0 ? "\(out)/\(t.name)-overlay-\(variant)-\(removal)" : nil), &runs)
                    } catch { note("overlay \(variant) \(removal): \(error)") }
                }
            }
        }
        scene.backdrop.close()
        quit(l)
        await sleepMs(800)
    }
    summarize(runs, to: out + "/summary.txt")
}

func summarize(_ runs: [[String: Any]], to path: String) {
    var groups: [String: [[String: Any]]] = [:]
    var order: [String] = []
    for r in runs {
        let k = "\(r["target"] ?? "?") | \(r["mech"] ?? "?")"
        if groups[k] == nil { order.append(k) }
        groups[k, default: []].append(r)
    }
    var s = "median across runs (n = runs); booleans as count true/n\n"
    for k in order {
        let g = groups[k]!
        var parts: [String] = []
        for key in Set(g.flatMap(\.keys)).sorted() where !["target", "mech"].contains(key) {
            let vals = g.compactMap { $0[key] }
            if let nums = vals as? [Double] ?? (vals as? [Int])?.map(Double.init) {
                if vals.first is Bool { continue }
                parts.append("\(key)=\(r1(pct(nums, 0.5)))")
            } else if let bs = vals as? [Bool] {
                parts.append("\(key)=\(bs.filter { $0 }.count)/\(bs.count)")
            } else if g.count == 1 {
                parts.append("\(key)=\(vals.first!)")
            }
        }
        s += "\(k) n=\(g.count): " + parts.joined(separator: " ") + "\n"
    }
    note(s)
    try? s.write(toFile: path, atomically: true, encoding: .utf8)
}

// MARK: - Sandbox check: AX writes and window capture from inside App Sandbox

func sandboxCheck(bundleID: String) async {
    let env = ProcessInfo.processInfo.environment
    note("sandboxed=\(env["APP_SANDBOX_CONTAINER_ID"] != nil) home=\(NSHomeDirectory())")
    note("AXIsProcessTrusted=\(AXIsProcessTrusted()) CGPreflightScreenCaptureAccess=\(CGPreflightScreenCaptureAccess())")
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { note("\(bundleID) not running"); return }
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    var v: CFTypeRef?
    let roleErr = AXUIElementCopyAttributeValue(appEl, kAXRoleAttribute as CFString, &v)
    let winErr = AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &v)
    var d: [String: Any] = ["mech": "sandboxcheck", "target": bundleID, "sandboxed": env["APP_SANDBOX_CONTAINER_ID"] != nil,
                            "pid": Int(app.processIdentifier), "axReadRoleError": Int(roleErr.rawValue), "axReadWindowsError": Int(winErr.rawValue)]
    // Capture does not depend on AX: find the app's window through ScreenCaptureKit alone.
    if let c = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
       let sw = c.windows.first(where: { $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0 }) {
        let l = Launched(target: Target(name: bundleID, bundleID: bundleID, openArgs: [], title: nil),
                         pid: app.processIdentifier, window: appEl, cgID: sw.windowID, child: nil)
        for (k, v) in await captureCost(l, reps: 5) where k != "mech" && k != "target" { d[k] = v }
    } else {
        d["capture"] = "no SCWindow for pid"
    }
    func emitD() { if let j = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]) { print(String(data: j, encoding: .utf8)!) } }
    guard let w = await findAXWindow(app.processIdentifier, title: nil), let f0 = axFrame(w) else {
        d["axWindow"] = "none"
        emitD()
        return
    }
    var lat: [Double] = [], errs: [AXError] = []
    let steps = 60
    for i in 0...steps {
        let x = f0.minX + 200 * sin(Double(i) / Double(steps) * .pi)
        let a = now()
        let e = axSetPos(w, CGPoint(x: x, y: f0.minY))
        lat.append(now() - a)
        if e != .success { errs.append(e) }
        usleep(6000)
    }
    axSetPos(w, f0.origin)
    d["axWindow"] = "found"
    d["axWriteErrors"] = errs.count
    d["firstWriteError"] = errs.first.map { Int($0.rawValue) } ?? 0
    latStats("pos", lat, into: &d)
    emitD()
}

// MARK: - Instrument calibration: what cadence can each capture configuration actually see?

/// A layer animating continuously in a probe-owned overlay; each stream config watches it for 1.5 s.
@MainActor func calib() async {
    let screen = NSScreen.screens[0]
    let hz = screen.maximumFramesPerSecond
    let mainID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
    let region = CGRect(x: 60, y: 71, width: 2400, height: 1220)
    let ow = NSWindow(contentRect: cocoa(region), styleMask: .borderless, backing: .buffered, defer: false)
    ow.isOpaque = false; ow.backgroundColor = .clear; ow.hasShadow = false; ow.ignoresMouseEvents = true; ow.level = .floating
    let view = NSView(frame: NSRect(origin: .zero, size: region.size))
    let root = CALayer(); root.isGeometryFlipped = true
    view.layer = root; view.wantsLayer = true
    ow.contentView = view
    let box = CALayer()
    box.backgroundColor = NSColor.systemBlue.cgColor
    box.frame = CGRect(x: 100, y: 100, width: 600, height: 400)
    root.addSublayer(box)
    ow.orderFrontRegardless()
    let anim = CABasicAnimation(keyPath: "position.x")
    anim.fromValue = 400; anim.toValue = 1900; anim.duration = 0.5; anim.autoreverses = true; anim.repeatCount = .infinity
    box.add(anim, forKey: "x")
    await sleepMs(300)
    guard let c = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
          let display = c.displays.first(where: { $0.displayID == mainID }),
          let win = c.windows.first(where: { $0.windowID == CGWindowID(ow.windowNumber) }) else { note("calib: no SC content"); return }
    let configs: [(String, SCContentFilter, CGRect?, Int, Int, Bool)] = [
        ("display-region-quarter-pixels", SCContentFilter(display: display, excludingWindows: []), region, 600, 305, true),
        ("display-region-quarter-nocopy", SCContentFilter(display: display, excludingWindows: []), region, 600, 305, false),
        ("display-region-full", SCContentFilter(display: display, excludingWindows: []), region, 2400, 1220, false),
        ("display-whole-quarter", SCContentFilter(display: display, excludingWindows: []), nil, 640, 360, false),
        ("overlay-window", SCContentFilter(desktopIndependentWindow: win), nil, 320, 160, false),
    ]
    for (name, filter, rect, w, h, px) in configs {
        guard let (s, rec) = try? await startStream(filter, rect: rect, w: w, h: h, pixels: px, hz: hz) else { note("\(name): start failed"); continue }
        await sleepMs(1500)
        try? await s.stopCapture()
        let ts = rec.all().map(\.t)
        guard let last = ts.last else { note("\(name): no frames"); continue }
        var d: [String: Any] = ["mech": "calib", "config": name, "displayHz": hz]
        cadence(ts, last - 1.0, last, "stream", into: &d)
        if let j = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]) { print(String(data: j, encoding: .utf8)!) }
    }
    ow.close()
}

// MARK: - main

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "target":
    runTarget()
case "all":
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let out = args.count > 2 ? args[2] : NSTemporaryDirectory() + "window-animation-probe"
    let reps = args.count > 3 ? Int(args[3]) ?? 4 : 4
    let names = Array(args.dropFirst(4))
    Task { @MainActor in await driveAll(out: out, reps: reps, names: names); exit(0) }
    app.run()
case "calib":
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    Task { @MainActor in await calib(); exit(0) }
    app.run()
case "sandboxcheck":
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    Task { await sandboxCheck(bundleID: args.count > 2 ? args[2] : "com.apple.calculator"); exit(0) }
    app.run()
default:
    note("usage: probe all <outdir> [reps] [targets...] | probe target | probe sandboxcheck <bundle-id>")
    exit(2)
}
