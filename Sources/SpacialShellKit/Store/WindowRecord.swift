import Foundation

/// #174: everything the store knows about one window that the model does not carry, in one place.
///
/// A window that vanishes is forgotten whole (`WindowRecords.forget`), and one retired to
/// `ignored` keeps only what `retire` names, so a new fact about a window has one clean-up to
/// follow and cannot outlive its window by being missed at a second one. What was learned from
/// our writes' echoes lives in `WindowEchoes` and `FocusEchoes`; the store forgets it there too.
struct WindowRecord: Equatable, Sendable {
    /// The frame last observed or written: what the plan compares against. After a failed write it
    /// is the frame we asked for, which the window never took; `lastSeen` is reality.
    var observed: CGRect?
    /// Where the window was when the shell parked it: where it goes back to.
    var prePark: CGRect?
    /// In a parking corner, by the shell's hand.
    var parked = false
    /// Failed writes in a row (spec §11: the third retires it).
    var failures = 0
    /// #165: a dialog or popup due a placement on the next pass: at first appearance, and again
    /// when the displays change. Nothing else ever moves one, so one the user moved stays put.
    var pendingPopup: PopupRequest?
    /// #165: adopted as a dialog or popup, so a display change can clamp it.
    var isPopup = false
    var bundleID: String?
    /// #110: the snapshot's `title`, kept current by every refresh and by `kAXTitleChanged`. Never
    /// put on a span or a log line: titles are the user's content (#148).
    var title: String?
    /// The frame in the last *snapshot*: reality, unlike `observed`. "Changed" is judged against
    /// this, or a retired window would look changed on the very next snapshot and we would fight
    /// it forever.
    var lastSeen: CGRect?
    /// Spec §11 as amended 2026-09-15: retirement lasts only "until it changes", so a retired
    /// window's last known state is kept to recognise the change that brings it back (#36).
    var retired: Retired?
    /// Spec §7.4 + §11: retired *while parked*, a window is unreachable by the reconciler for good,
    /// so nothing would ever unpark it. Its last real frame is kept purely so the termination
    /// restore can put it back.
    var stranded: CGRect?

    /// `wentAway`: seen on another Space since retirement; coming back is a change too (#55).
    struct Retired: Equatable, Sendable { var frame: CGRect; var fullscreen: Bool; var wentAway = false }

    /// Spec §11: retired to `ignored`. The reconciler no longer places it, so everything learned
    /// from placing it goes; who it is stays (its app, title and last seen frame), with what brings
    /// it back and, retired while parked, where the termination restore puts it. Built from what is
    /// kept, so a new field is dropped here unless it is named.
    mutating func retire(fullscreen: Bool) {
        var kept = WindowRecord(bundleID: bundleID, title: title, lastSeen: lastSeen, stranded: stranded)
        if parked, let frame = prePark ?? observed { kept.stranded = frame }
        kept.retired = Retired(frame: lastSeen ?? observed ?? .zero, fullscreen: fullscreen)
        self = kept
    }
}

/// #174: the store's `WindowRecord`s. Reading a window with none gives an empty record, and a
/// record written back empty is dropped, so a window that is not known leaves no entry. The
/// whole-table views are what the reconciler, the snapshot and the termination restore read.
struct WindowRecords: Sendable {
    private var byRef: [WindowRef: WindowRecord] = [:]

    subscript(r: WindowRef) -> WindowRecord {
        get { byRef[r] ?? WindowRecord() }
        set { byRef[r] = newValue == WindowRecord() ? nil : newValue }
    }

    /// `r` vanished: nothing about it outlives it.
    mutating func forget(_ r: WindowRef) { byRef[r] = nil }

    var observed: [WindowRef: CGRect] { byRef.compactMapValues(\.observed) }
    var prePark: [WindowRef: CGRect] { byRef.compactMapValues(\.prePark) }
    var parked: Set<WindowRef> { Set(byRef.filter(\.value.parked).keys) }
    var pendingPopups: [WindowRef: PopupRequest] { byRef.compactMapValues(\.pendingPopup) }
    var popups: Set<WindowRef> { Set(byRef.filter(\.value.isPopup).keys) }
    var bundleIDs: [WindowRef: String] { byRef.compactMapValues(\.bundleID) }
    var titles: [WindowRef: String] { byRef.compactMapValues(\.title) }
    var retired: Set<WindowRef> { Set(byRef.filter { $0.value.retired != nil }.keys) }
    var stranded: [WindowRef: CGRect] { byRef.compactMapValues(\.stranded) }
}
