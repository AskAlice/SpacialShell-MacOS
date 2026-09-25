// Synthetic input for runner.py's pointer and key steps (#81), posted at the HID tap so the shell's
// own event tap, hover tracking and drag-and-drop see it exactly like a real mouse and keyboard.
//
//   input move X Y                  pointer to X,Y (global points, top-left origin)
//   input click X Y
//   input drag X1 Y1 X2 Y2 [SECS]   press at 1, glide to 2, release there — after holding SECS.
//                                   The button is only down while this process lives (its event
//                                   source goes with it), so a held drag is a long-lived process.
//   input key CHORD                 e.g. fn-comma, cmd-m (modifiers: fn ctrl alt shift cmd)
//   input flags fn|none             press / release a bare modifier (the hold-Fn cheat sheet)
//   input axclick PID LABEL         click the centre of PID's first AX element titled LABEL
//
// Needs only the Accessibility grant the runner already holds, like axfullscreen.swift.
import ApplicationServices
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
func die(_ msg: String, _ code: Int32 = 2) -> Never { fputs("input: \(msg)\n", stderr); exit(code) }
guard AXIsProcessTrusted() else { die("this process tree has no Accessibility grant", 3) }
let src = CGEventSource(stateID: .hidSystemState)
func num(_ i: Int) -> CGFloat { guard i < args.count, let v = Double(args[i]) else { die("bad number") }; return v }

func mouse(_ type: CGEventType, _ p: CGPoint) {
    let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!
    e.post(tap: .cghidEventTap)
}

func glide(from a: CGPoint, to b: CGPoint, dragging: Bool) {
    // Small steps with real time between them: AppKit starts a drag only after the pointer has
    // moved a few points *while* held, and SwiftUI's drop targets update per event.
    let steps = max(8, Int(hypot(b.x - a.x, b.y - a.y) / 6))
    for i in 1...steps {
        let t = CGFloat(i) / CGFloat(steps)
        mouse(dragging ? .leftMouseDragged : .mouseMoved, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        usleep(12_000)
    }
}

func current() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

func key(_ chord: String) {
    let parts = chord.lowercased().split(separator: "-").map(String.init)
    let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "w": 13, "m": 46, "h": 4, "q": 12, "g": 5, "comma": 43, "space": 49, "tab": 48,
        "esc": 53, "return": 36, "1": 18, "2": 19, "3": 20, "left": 123, "right": 124, "down": 125, "up": 126,
    ]
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
case "click":
    let p = CGPoint(x: num(1), y: num(2))
    glide(from: current(), to: p, dragging: false)
    mouse(.leftMouseDown, p); usleep(60_000); mouse(.leftMouseUp, p)
case "drag":
    let a = CGPoint(x: num(1), y: num(2)), b = CGPoint(x: num(3), y: num(4))
    glide(from: current(), to: a, dragging: false)
    mouse(.leftMouseDown, a); usleep(250_000)
    glide(from: a, to: b, dragging: true)
    usleep(400_000)   // let the drop target settle under the pointer
    if args.count > 5, let hold = Double(args[5]) {
        print("holding"); fflush(stdout)   // runner.py shoots the drop indicator now
        usleep(useconds_t(hold * 1_000_000))
        // After a still hold, AppKit wants to see the pointer at the target again before a drop.
        glide(from: CGPoint(x: b.x + 2, y: b.y + 2), to: b, dragging: true)
        usleep(200_000)
    }
    mouse(.leftMouseUp, b)
case "key" where args.count == 2: key(args[1])
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
    glide(from: current(), to: p, dragging: false)
    mouse(.leftMouseDown, p); usleep(60_000); mouse(.leftMouseUp, p)
default:
    die("usage: input move|click|drag|key|flags|axclick …")
}
usleep(50_000)
