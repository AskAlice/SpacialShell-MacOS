import AppKit
import Foundation

/// Structural checks a pixel snapshot can miss until a human squints at it: text drawn over
/// text (a borked line-height), and content escaping its container instead of wrapping or
/// truncating. Works off the rendered view's accessibility tree — SwiftUI publishes one element
/// per text/control with a real on-screen frame, which is exactly the geometry we want to judge.
@MainActor
enum LayoutLint {
    struct Element {
        let role: NSAccessibility.Role
        let label: String
        let frame: CGRect   // screen coordinates
    }

    /// SwiftUI's `ScrollView` is an `NSScrollView` in the hosted hierarchy.
    static func containsScrollView(_ v: NSView) -> Bool {
        v is NSScrollView || v.subviews.contains(where: containsScrollView)
    }

    /// All the issues found in `root` (hosted in a window); empty means clean.
    static func issues(in root: NSView, story: String, truncates: Bool = false) -> [String] {
        var out: [String] = []

        // 1. The view must not want more space than the story gave it — a container that can only
        //    show its content by clipping it is a wrap/truncation bug at the layout level.
        //
        //    Unless it scrolls. A `ScrollView`'s ideal height *is* its content's height, so a
        //    scrollable view legitimately "wants" more than it was given and answers the shortfall
        //    by scrolling rather than by clipping. The width check still applies: content spilling
        //    sideways out of a vertical scroller is a wrap bug like any other.
        let fitting = root.fittingSize
        let scrolls = containsScrollView(root)
        if !truncates, fitting.width > root.bounds.width + 0.5 {
            out.append("\(story): content wants \(Int(fitting.width))pt of width in a \(Int(root.bounds.width))pt container")
        }
        if !scrolls, fitting.height > root.bounds.height + 0.5 {
            out.append("\(story): content wants \(Int(fitting.height))pt of height in a \(Int(root.bounds.height))pt container")
        }

        // 2. Text-on-text overlap and escape checks over the accessibility tree.
        let elements = gather(root)
        let texts = elements.filter { $0.role == .staticText }
        let rootFrame = screenFrame(of: root)
        // A frame poking out of the root is content escaping the panel (padding is inside root).
        for t in texts where !rootFrame.insetBy(dx: -1, dy: -1).contains(t.frame) {
            out.append("\(story): text “\(t.label)” escapes the container (\(t.frame) vs \(rootFrame))")
        }
        for i in texts.indices {
            for j in texts.indices where j > i {
                let a = texts[i].frame, b = texts[j].frame
                let overlap = a.intersection(b)
                // Partial overlap between two distinct texts is the bug; containment is a
                // label-inside-control arrangement and legitimate.
                guard !overlap.isNull, overlap.width > 1, overlap.height > 1,
                      !a.contains(b), !b.contains(a) else { continue }
                out.append("\(story): text “\(texts[i].label)” overlaps “\(texts[j].label)” by \(Int(overlap.width))×\(Int(overlap.height))pt")
            }
        }
        return out
    }

    private static func screenFrame(of view: NSView) -> CGRect {
        guard let window = view.window else { return view.frame }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }

    private static func gather(_ any: Any) -> [Element] {
        var out: [Element] = []
        var queue: [Any] = [any]
        var budget = 4096   // SwiftUI trees are finite but let's not trust that with a hard loop
        while let next = queue.popLast(), budget > 0 {
            budget -= 1
            guard let el = next as? any NSAccessibilityProtocol else { continue }
            let role = el.accessibilityRole()
            if let role {
                let label = (el.accessibilityValue() as? String)
                    ?? el.accessibilityLabel()
                    ?? el.accessibilityTitle()
                    ?? "?"
                out.append(Element(role: role, label: label, frame: el.accessibilityFrame()))
            }
            for child in el.accessibilityChildren() ?? [] { queue.append(child) }
        }
        return out
    }
}
