// Adapted from AeroSpace (MIT) — Sources/AppBundle/util/appBundleUtil.swift @ c548c7f
// Trimmed to the signposter and the run-loop cancellation model; the rest of the
// original file depends on AeroSpace's window/monitor tree.
import AppKit
import Foundation
import os

let signposter = OSSignposter(subsystem: "me.askalice.SpacialShell", category: .pointsOfInterest)

#if DEBUG
    let isDebug = true
#else
    let isDebug = false
#endif

@inlinable
func checkCancellation(_ cm: CancellationMode = .cancellable) throws(CancellationError) {
    if cm == .cancellable && Task.isCancelled {
        throw CancellationError()
    }
}

public enum CancellationMode: Equatable, Sendable {
    case cancellable
    case nonCancellable
}
