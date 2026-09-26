// Synthetic input for runner.py's pointer and key steps (#81), posted at the HID tap so the shell's
// own event tap, hover tracking and drag-and-drop see it exactly like a real mouse and keyboard.
//
//   input move X Y                  pointer to X,Y (global points, top-left origin)
//   input click X Y
//   input rightclick X Y            a secondary click (the rail's context menus)
//   input drag X1 Y1 X2 Y2 [SECS]   press at 1, glide to 2, release there — after holding SECS.
//                                   The button is only down while this process lives (its event
//                                   source goes with it), so a held drag is a long-lived process.
//   input scroll X Y DY [N]         N mouse-wheel notches of DY lines at X,Y (negative DY: down)
//   input key CHORD                 e.g. fn-comma, cmd-m (modifiers: fn ctrl alt shift cmd)
//   input type TEXT                 type TEXT into whatever has key focus (a search field)
//   input flags fn|none             press / release a bare modifier (the hold-Fn cheat sheet)
//   input axclick PID LABEL         click the centre of PID's first AX element titled LABEL
//
// The pointer moves like a hand, not a plotter (#149): every move follows a slightly curved path
// (a quadratic Bézier bowed a little to one side) at a minimum-jerk speed profile (accelerate,
// then decelerate), takes 250–600 ms depending on distance (Fitts-like), posts at about 100 Hz,
// and rests 80–150 ms before a click or a drop. A drag presses, nudges past AppKit's drag
// threshold, then glides.
//
// Needs only the Accessibility grant the runner already holds, like axfullscreen.swift.
import ApplicationServices
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
func die(_ msg: String, _ code: Int32 = 2) -> Never { fputs("input: \(msg)\n", stderr); exit(code) }
guard AXIsProcessTrusted() else { die("this process tree has no Accessibility grant", 3) }
let src = CGEventSource(stateID: .hidSystemState)
func num(_ i: Int) -> CGFloat { guard i < args.count, let v = Double(args[i]) else { die("bad number") }; return v }

func mouse(_ type: CGEventType, _ p: CGPoint, button: CGMouseButton = .left) {
    let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: button)!
    e.post(tap: .cghidEventTap)
}

// --- human pointer motion (#149) ---------------------------------------------------------------

func rnd(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b) }
func pause(_ secs: Double) { usleep(useconds_t(max(secs, 0) * 1_000_000)) }
func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

/// Fitts-like: time grows with the log of the distance (target width ~10 pt), ±8% from hand to
/// hand, clamped to 250–600 ms. 50 pt ≈ 0.33 s, 300 pt ≈ 0.50 s, 900 pt ≈ 0.6 s.
func moveDuration(_ d: CGFloat) -> Double {
    let t = (0.16 + 0.07 * log2(1 + Double(d) / 10)) * rnd(0.92, 1.08)
    return min(max(t, 0.25), 0.6)
}

/// Minimum-jerk position profile: 0 → 1 with zero speed and acceleration at both ends.
func minJerk(_ t: Double) -> Double { t * t * t * (10 - 15 * t + 6 * t * t) }

/// From a to b along a gently bowed path. A glide posts only moved/dragged events; the caller
/// decides what happens at the end.
func glide(from a: CGPoint, to b: CGPoint, dragging: Bool) {
    let type: CGEventType = dragging ? .leftMouseDragged : .mouseMoved
    let d = hypot(b.x - a.x, b.y - a.y)
    guard d >= 2 else { mouse(type, b); return }
    let dur = moveDuration(d)
    // The control point sits off the chord's midpoint, 4–10% of the distance (at most 40 pt) to
    // a random side: a wrist arcs, it does not rule lines.
    let side: CGFloat = Bool.random() ? 1 : -1
    let bow = min(d * CGFloat(rnd(0.04, 0.10)), 40) * side
    let nx = -(b.y - a.y) / d, ny = (b.x - a.x) / d
    let c = CGPoint(x: (a.x + b.x) / 2 + nx * bow, y: (a.y + b.y) / 2 + ny * bow)
    let hz = rnd(90, 110)
    let start = now()
    var tick = 1
    while true {
        let target = start + Double(tick) / hz
        let wait = target - now()
        if wait > 0 { pause(wait + rnd(-0.0015, 0.0015)) }   // a little jitter in the report rate
        let t = min((now() - start) / dur, 1)
        let s = CGFloat(minJerk(t)), u = 1 - s
        mouse(type, CGPoint(x: u * u * a.x + 2 * u * s * c.x + s * s * b.x,
                            y: u * u * a.y + 2 * u * s * c.y + s * s * b.y))
        if t >= 1 { break }
        tick += 1
    }
}

/// The short rest a hand makes on a target before it clicks or lets go. During a drag the pointer
/// is re-reported where it is, as a resting mouse still reports: drop targets update per event.
func settle(at p: CGPoint, dragging: Bool) {
    let secs = rnd(0.08, 0.15)
    if dragging {
        pause(secs / 2); mouse(.leftMouseDragged, p); pause(secs / 2)
    } else {
        pause(secs)
    }
}

func current() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

func click(_ p: CGPoint, button: CGMouseButton = .left) {
    glide(from: current(), to: p, dragging: false)
    settle(at: p, dragging: false)
    let (down, up): (CGEventType, CGEventType) = button == .left ? (.leftMouseDown, .leftMouseUp)
                                                                  : (.rightMouseDown, .rightMouseUp)
    mouse(down, p, button: button); pause(rnd(0.05, 0.09)); mouse(up, p, button: button)
}

func drag(_ a: CGPoint, _ b: CGPoint, hold: Double?) {
    glide(from: current(), to: a, dragging: false)
    settle(at: a, dragging: false)
    mouse(.leftMouseDown, a)
    pause(rnd(0.09, 0.14))   // a press, not a tap: AppKit and SwiftUI see a held button first
    // Past the drag threshold (a few points) in three quick reports toward the target, so the
    // drag session exists before the real motion starts.
    let d = max(hypot(b.x - a.x, b.y - a.y), 1)
    let ux = (b.x - a.x) / d, uy = (b.y - a.y) / d
    var p = a
    for step in 1...3 {
        p = CGPoint(x: a.x + ux * CGFloat(step) * 3, y: a.y + uy * CGFloat(step) * 3)
        mouse(.leftMouseDragged, p); pause(0.016)
    }
    glide(from: p, to: b, dragging: true)
    settle(at: b, dragging: true)
    if let hold {
        print("holding"); fflush(stdout)   // runner.py shoots the drop indicator now
        pause(hold)
        // After a still hold, AppKit wants to see the pointer at the target again before a drop.
        glide(from: CGPoint(x: b.x + 2, y: b.y + 2), to: b, dragging: true)
        settle(at: b, dragging: true)
    }
    mouse(.leftMouseUp, b)
}

// --- keys ---------------------------------------------------------------------------------------

// kVK_ANSI_* positions, as SpacialShellKit's KeyCodes.byName.
let codes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
    "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45,
    "m": 46, "comma": 43, "space": 49, "tab": 48,
    "esc": 53, "return": 36, "equal": 24, "minus": 27, "left": 123, "right": 124, "down": 125, "up": 126,
    "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
]

func key(_ chord: String) {
    let parts = chord.lowercased().split(separator: "-").map(String.init)
    guard let name = parts.last, let code = codes[name] else { die("unknown key in \(chord)") }
    var flags: CGEventFlags = []
    for m in parts.dropLast() {
        switch m {
        case "fn": flags.insert(.maskSecondaryFn)
        case "ctrl": flags.insert(.maskControl)
        case "alt": flags.insert(.maskAlternate)
        case "shift": flags.insert(.maskShift)
        case "cmd": flags.insert(.maskCommand)
        default: die("unknown modifier \(m)")
        }
    }
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!
        e.flags = flags
        e.post(tap: .cghidEventTap)
        usleep(30_000)
    }
}

func flagsEvent(_ on: Bool) {
    let e = CGEvent(keyboardEventSource: src, virtualKey: 63, keyDown: on)!   // kVK_Function
    e.type = .flagsChanged
    e.flags = on ? .maskSecondaryFn : []
    e.post(tap: .cghidEventTap)
}

// --- accessibility ------------------------------------------------------------------------------

func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v as? T : nil
}

/// Depth-first, windows first: the first element whose title, description or string value is LABEL.
func find(_ el: AXUIElement, _ label: String, depth: Int = 0) -> AXUIElement? {
    if depth > 40 { return nil }
    for a in ["AXTitle", "AXDescription", "AXValue"] where (attr(el, a) as String?) == label { return el }
    for child in (attr(el, "AXChildren") as [AXUIElement]?) ?? [] {
        if let hit = find(child, label, depth: depth + 1) { return hit }
    }
    return nil
}

func centre(_ el: AXUIElement) -> CGPoint? {
    guard let p: AXValue = attr(el, "AXPosition"), let s: AXValue = attr(el, "AXSize") else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p, .cgPoint, &pt); AXValueGetValue(s, .cgSize, &sz)
    return CGPoint(x: pt.x + sz.width / 2, y: pt.y + sz.height / 2)
}

switch args.first {
case "move": glide(from: current(), to: CGPoint(x: num(1), y: num(2)), dragging: false)
case "click": click(CGPoint(x: num(1), y: num(2)))
case "rightclick": click(CGPoint(x: num(1), y: num(2)), button: .right)
case "drag":
    drag(CGPoint(x: num(1), y: num(2)), CGPoint(x: num(3), y: num(4)),
         hold: args.count > 5 ? Double(args[5]) : nil)
case "scroll":
    let p = CGPoint(x: num(1), y: num(2))
    glide(from: current(), to: p, dragging: false)
    settle(at: p, dragging: false)
    let n = args.count > 4 ? Int(num(4)) : 1
    for _ in 0..<max(n, 1) {
        let e = CGEvent(scrollWheelEvent2Source: src, units: .line, wheelCount: 1, wheel1: Int32(num(3)), wheel2: 0, wheel3: 0)!
        e.location = p
        e.post(tap: .cghidEventTap)
        usleep(150_000)
    }
case "key" where args.count == 2: key(args[1])
case "type" where args.count == 2:
    // Each letter's own key and no modifiers: the shell's tap reads key codes and flags, and a
    // borrowed code (or a source still remembering Fn from the last chord) would be a hotkey.
    for ch in args[1].utf16 {
        let code = codes[String(utf16CodeUnits: [ch], count: 1).lowercased()] ?? 49
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!
            e.flags = []
            var c = ch
            e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            e.post(tap: .cghidEventTap)
            usleep(40_000)
        }
        usleep(90_000)   // a person's pace, so the filtering shows letter by letter
    }
case "flags" where args.count == 2: flagsEvent(args[1] == "fn")
case "axclick" where args.count == 3:
    guard let pid = pid_t(args[1]) else { die("bad pid") }
    var hit: AXUIElement?
    for _ in 0..<20 {   // a window still building its view answers nothing for a moment
        hit = find(AXUIElementCreateApplication(pid), args[2])
        if hit != nil { break }
        usleep(250_000)
    }
    guard let el = hit, let p = centre(el) else { die("no AX element labelled \(args[2]) in pid \(pid)", 4) }
    click(p)
default:
    die("usage: input move|click|rightclick|drag|scroll|key|type|flags|axclick …")
}
usleep(50_000)
