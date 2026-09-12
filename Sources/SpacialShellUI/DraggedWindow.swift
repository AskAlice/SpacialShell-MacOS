import CoreTransferable
import UniformTypeIdentifiers
import SpacialShellProtocol

/// What a dragged tab carries: the window it stands for, and nothing else.
///
/// A private content type, not `public.text` or a file URL, so the drag is meaningful only inside
/// SpacialShell — dropping a tab on another app does nothing rather than pasting something odd
/// into it, and nothing another app offers can be dropped on the rail.
extension UTType {
    static let spacialWindow = UTType(exportedAs: "me.askalice.SpacialShell.window")
}

struct DraggedWindow: Codable, Transferable {
    let ref: WindowRef

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .spacialWindow)
    }
}
