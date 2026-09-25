import AppKit
import SwiftUI
import SpacialShellKit

/// A layout's glyph (#10, design §2 "Glyph"): its SF Symbol, or — for a drawn layout without one —
/// its zones outlined in a 16 × 12 pt box, so twenty custom layouts are twenty different pictures
/// rather than twenty identical `square.grid.3x2`s.
struct LayoutGlyph: View {
    let def: LayoutDef

    var body: some View {
        if let symbol = def.symbol {
            Image(systemName: symbol).font(.system(size: 12))
        } else {
            ZoneOutline(zones: Self.zones(def)).stroke(lineWidth: 1.1).frame(width: 16, height: 12)
        }
    }

    static func zones(_ def: LayoutDef) -> [LayoutZone] {
        if case .zones(let z) = def.body { z } else { [] }
    }

    /// The same picture for an `NSMenuItem`, which takes an image rather than a view. Template, so
    /// the menu tints it with the item's text.
    static func image(_ def: LayoutDef) -> NSImage? {
        if let symbol = def.symbol { return NSImage(systemSymbolName: symbol, accessibilityDescription: def.name) }
        let zones = zones(def)
        let image = NSImage(size: NSSize(width: 16, height: 12), flipped: true) { rect in
            NSColor.black.setStroke()
            let path = NSBezierPath(cgPath: ZoneOutline(zones: zones).path(in: rect).cgPath)
            path.lineWidth = 1.1
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Unit-rect zones as rounded outlines in whatever rect it is given — the glyph at 16 × 12, a
/// preset button at 44 × 28.
struct ZoneOutline: Shape {
    let zones: [LayoutZone]
    func path(in r: CGRect) -> Path {
        var p = Path()
        for z in zones {
            let cell = CGRect(x: r.minX + z.x * r.width, y: r.minY + z.y * r.height, width: z.w * r.width, height: z.h * r.height)
            p.addRoundedRect(in: cell.insetBy(dx: 0.6, dy: 0.6), cornerSize: CGSize(width: 1, height: 1))
        }
        return p
    }
}
