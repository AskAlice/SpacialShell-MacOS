import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import SpacialShellProtocol

/// What a dragged tab carries: the window it stands for, and nothing else.
///
/// The content type is the standard `public.data` rather than a private
/// `sh.emu.SpacialShell.window`, and that is not laziness — a private one does not work.
/// A UTI invented at runtime has conformance only if the bundle *declares* it in
/// `UTExportedTypeDeclarations`; `UTType(exportedAs:conformingTo:)` does not register one on its
/// own, and neither does `importedAs` (both yield `supertypes == []`, verified on macOS 26).
/// A type conforming to nothing is offered to no destination — SwiftUI's `.dropDestination`
/// registers `public.item` / `public.data` — so the drag started, followed the cursor, and
/// silently did nothing.
///
/// Declaring it in `Resources/Info.plist` would fix only the installed `.app`: `Scripts/dev.sh`
/// runs a loose binary with no Info.plist, so drags would work when installed and fail while
/// developing. A standard type works in both.
///
/// The looser type does not let another app's drag into the rail do anything:
/// `dropDestination(for: DraggedWindow.self)` delivers only items that actually decode, so a
/// foreign `public.data` payload is rejected on decode. `DragTests` pins all of this down.
struct DraggedWindow: Codable, Transferable {
    let ref: WindowRef

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

/// What a dragged rail tile carries (#75): the workspace, and nothing else. `public.data` for the
/// same reasons as `DraggedWindow`; the two are told apart by decoding instead — their keys
/// differ (`workspace` vs `ref`), so neither payload ever decodes as the other. `DragTests` pins it.
struct DraggedWorkspace: Codable, Transferable {
    let workspace: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

/// Everything a rail tile accepts: a tab (move that window here) or another tile (reorder). One
/// destination deciding by payload, rather than two `.dropDestination`s stacked on one view,
/// whose interplay SwiftUI does not document.
enum RailDrop: Codable, Transferable {
    case window(DraggedWindow)
    case workspace(DraggedWorkspace)

    init(from decoder: Decoder) throws {
        if let w = try? DraggedWindow(from: decoder) { self = .window(w); return }
        self = .workspace(try DraggedWorkspace(from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .window(let w): try w.encode(to: encoder)
        case .workspace(let ws): try ws.encode(to: encoder)
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}
