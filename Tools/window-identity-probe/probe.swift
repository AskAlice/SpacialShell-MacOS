// Throwaway probe for issue #17: can an AXUIElement be mapped to a CGWindowID with public API only?
//
// Ground truth is the private `_AXUIElementGetWindow`; the candidate is a match against
// CGWindowListCopyWindowInfo on pid + layer + frame + title. Nothing here is shipped code and
// nothing here is imported by the app: build it standalone with
//
//     swiftc -O probe.swift -o probe
//
// Subcommands:
//   baseline [rounds]      sweep every AX window of every running app, N times
//   identical <pid>        force two windows of one app to the same frame, measure, restore
//   move <pid>             start an AX move and sample the CG list while it is in flight
//   park <pid>             shove a window into a corner sliver, mostly off-screen
//
// Output is one JSON object per case on stdout; human-readable notes go to stderr.

import AppKit
import ApplicationServices
import Foundation

// The private call, declared here rather than via the repo's PrivateApi target so this file stays
// standalone. It is the ground truth the public answer is measured against.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: inout CGWindowID) -> AXError

// MARK: - CGWindowList side

struct CGEntry {
    let id: CGWindowID
    let pid: pid_t
    let bounds: CGRect
    let title: String?
    let layer: Int
    let onscreen: Bool
    let alpha: Double
    let owner: String
}

func cgSnapshot(onScreenOnly: Bool = false) -> [CGEntry] {
    let opts: CGWindowListOption = onScreenOnly
        ? [.optionOnScreenOnly, .excludeDesktopElements]
        : [.optionAll, .excludeDesktopElements]
    let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
    return raw.compactMap { d in
        guard let id = d[kCGWindowNumber as String] as? CGWindowID,
              let pid = d[kCGWindowOwnerPID as String] as? pid_t,
              let b = d[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: b as CFDictionary)
        else { return nil }
        return CGEntry(
            id: id,
            pid: pid,
            bounds: rect,
            title: d[kCGWindowName as String] as? String,
            layer: d[kCGWindowLayer as String] as? Int ?? 0,
            onscreen: (d[kCGWindowIsOnscreen as String] as? Bool) ?? false,
            alpha: d[kCGWindowAlpha as String] as? Double ?? 1,
            owner: d[kCGWindowOwnerName as String] as? String ?? "?"
        )
    }
}

// MARK: - AX side

func axWindows(_ pid: pid_t) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1.0)
    var count: CFIndex = 0
    guard AXUIElementGetAttributeValueCount(app, kAXWindowsAttribute as CFString, &count) == .success,
          count > 0
    else { return [] }
    var raw: CFArray?
    guard AXUIElementCopyAttributeValues(app, kAXWindowsAttribute as CFString, 0, count, &raw) == .success
    else { return [] }
    return (raw as? [AXUIElement]) ?? []
}

func axString(_ w: AXUIElement, _ attr: String) -> String? {
    var raw: AnyObject?
    guard AXUIElementCopyAttributeValue(w, attr as CFString, &raw) == .success else { return nil }
    return raw as? String
}

func axBool(_ w: AXUIElement, _ attr: String) -> Bool? {
    var raw: AnyObject?
    guard AXUIElementCopyAttributeValue(w, attr as CFString, &raw) == .success else { return nil }
    return raw as? Bool
}

func axFrame(_ w: AXUIElement) -> CGRect? {
    var pRaw: AnyObject?
    var sRaw: AnyObject?
    guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &pRaw) == .success,
          AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sRaw) == .success,
          let p0 = pRaw, let s0 = sRaw,
          CFGetTypeID(p0) == AXValueGetTypeID(), CFGetTypeID(s0) == AXValueGetTypeID()
    else { return nil }
    var p = CGPoint.zero
    var s = CGSize.zero
    AXValueGetValue(p0 as! AXValue, .cgPoint, &p)
    AXValueGetValue(s0 as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}

@discardableResult func axSetFrame(_ w: AXUIElement, _ f: CGRect) -> Bool {
    var p = f.origin
    var s = f.size
    guard let pv = AXValueCreate(.cgPoint, &p), let sv = AXValueCreate(.cgSize, &s) else { return false }
    let a = AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv)
    let b = AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv)
    return a == .success && b == .success
}

func truthID(_ w: AXUIElement) -> CGWindowID? {
    var id = CGWindowID()
    return _AXUIElementGetWindow(w, &id) == .success && id != kCGNullWindowID ? id : nil
}

// MARK: - The candidate public-API matcher

enum Verdict {
    case unique(CGWindowID, stage: String)
    case ambiguous([CGWindowID], stage: String)
    case empty(stage: String)
}

func approx(_ a: CGRect, _ b: CGRect, _ tol: CGFloat) -> Bool {
    abs(a.minX - b.minX) <= tol && abs(a.minY - b.minY) <= tol
        && abs(a.width - b.width) <= tol && abs(a.height - b.height) <= tol
}

/// pid (+ optionally layer-0) pool, then frame, then title. The approach named in the issue.
/// `anyLayer` drops the layer-0 restriction, which is needed for floating panels.
func predict(
    pid: pid_t, frame: CGRect?, title: String?, cg: [CGEntry], tol: CGFloat, anyLayer: Bool = false
) -> Verdict {
    let pool = cg.filter { $0.pid == pid && (anyLayer || $0.layer == 0) }
    if pool.isEmpty { return .empty(stage: "pool-empty") }
    if pool.count == 1 { return .unique(pool[0].id, stage: "solo") }

    let frameHits = frame.map { f in pool.filter { approx($0.bounds, f, tol) } } ?? []
    if frameHits.count == 1 { return .unique(frameHits[0].id, stage: "frame") }
    if frameHits.count > 1 {
        let t = frameHits.filter { $0.title != nil && $0.title == title }
        if t.count == 1 { return .unique(t[0].id, stage: "frame+title") }
        return .ambiguous(frameHits.map(\.id), stage: "frame-tie")
    }
    // No frame hit at all: fall back to title alone.
    let t = pool.filter { $0.title != nil && $0.title == title }
    if t.count == 1 { return .unique(t[0].id, stage: "title-only") }
    if t.count > 1 { return .ambiguous(t.map(\.id), stage: "title-tie") }
    return .empty(stage: "no-candidate")
}

/// Predictor C: per-app bipartite assignment. Each AX window gets a candidate set (frame match,
/// title match or blank CG title); AX windows sharing the same candidate set are assigned to it
/// pairwise in list order. CGWindowList and AXWindows are both nominally front-to-back, so this is
/// the last public signal available once frame and title have both tied.
func assign(
    pool: [CGEntry], axFrames: [CGRect?], axTitles: [String], tol: CGFloat, order: [CGWindowID]
) -> [CGWindowID?] {
    // Ties are broken in onscreen-list order: `.optionAll` order is not front-to-back, the
    // onscreen list is, so it is the only order worth trying.
    let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
    let cands: [[CGWindowID]] = zip(axFrames, axTitles).map { f, t in
        guard let f else { return [] }
        return pool.filter { e in
            approx(e.bounds, f, tol) && (e.title == nil || e.title!.isEmpty || e.title == t)
        }
        .map(\.id)
        .sorted { rank[$0] ?? Int.max < rank[$1] ?? Int.max }
    }
    var out = [CGWindowID?](repeating: nil, count: cands.count)
    var groups: [[CGWindowID]: [Int]] = [:]
    for (i, c) in cands.enumerated() where !c.isEmpty { groups[c, default: []].append(i) }
    for (cand, idxs) in groups where cand.count == idxs.count {
        for (k, i) in idxs.enumerated() { out[i] = cand[k] }
    }
    return out
}

// MARK: - Sweep

struct Row {
    var app: String
    var pid: pid_t
    var axTitle: String
    var axFrame: CGRect?
    var minimized: Bool
    var hidden: Bool
    var truth: CGWindowID?
    var predicted: CGWindowID?
    var stage: String
    var candidates: Int
    var ordinalPredicted: CGWindowID?
    var truthInPool: Bool
    var truthOnscreen: Bool?
    var cgTitle: String?
    var poolSize: Int
    var subrole: String
    var role: String
    var regularApp: Bool
    var anyLayerPredicted: CGWindowID?
    var anyLayerStage: String
    var poolOnscreen: Int
    var assignPredicted: CGWindowID?

    var correct: Bool { truth != nil && predicted == truth }
    /// What the reconciler would actually key on: standard windows of ordinary apps.
    var adoptable: Bool { regularApp && role == "AXWindow" && subrole == "AXStandardWindow" }
    var dict: [String: Any] {
        [
            "app": app, "pid": Int(pid), "axTitle": axTitle,
            "frame": axFrame.map { [$0.minX, $0.minY, $0.width, $0.height] } as Any,
            "minimized": minimized, "hidden": hidden,
            "truth": truth.map(Int.init) as Any, "predicted": predicted.map(Int.init) as Any,
            "stage": stage, "candidates": candidates,
            "ordinalOK": ordinalPredicted != nil && ordinalPredicted == truth,
            "truthInPool": truthInPool, "truthOnscreen": truthOnscreen as Any,
            "cgTitle": cgTitle as Any, "titleAgrees": cgTitle == axTitle,
            "poolSize": poolSize, "correct": correct,
            "subrole": subrole, "role": role, "regularApp": regularApp, "adoptable": adoptable,
            "anyLayerPredicted": anyLayerPredicted.map(Int.init) as Any,
            "anyLayerCorrect": truth != nil && anyLayerPredicted == truth,
            "anyLayerStage": anyLayerStage, "poolOnscreen": poolOnscreen,
            "assignPredicted": assignPredicted.map(Int.init) as Any,
            "assignCorrect": truth != nil && assignPredicted == truth,
            "assignAnswered": assignPredicted != nil,
        ]
    }
}

func unpack(_ v: Verdict) -> (CGWindowID?, Int, String) {
    switch v {
    case let .unique(id, s): (id, 1, s)
    case let .ambiguous(ids, s): (nil, ids.count, s)
    case let .empty(s): (nil, 0, s)
    }
}

func sweep(tol: CGFloat) -> [Row] {
    let cg = cgSnapshot()
    // The onscreen list is ordered front-to-back like AXWindows; optionAll is not. The tiebreak
    // uses onscreen order, which is the strongest public signal found.
    let onscreenOrder = cgSnapshot(onScreenOnly: true).map(\.id)
    var rows: [Row] = []
    for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy != .prohibited && app.processIdentifier != getpid()
    {
        let pid = app.processIdentifier
        let wins = axWindows(pid)
        if wins.isEmpty { continue }
        let pool = cg.filter { $0.pid == pid && $0.layer == 0 }
        let frames = wins.map { axFrame($0) }
        let titles = wins.map { axString($0, kAXTitleAttribute as String) ?? "" }
        let assigned = assign(
            pool: pool, axFrames: frames, axTitles: titles, tol: tol, order: onscreenOrder)
        for (i, w) in wins.enumerated() {
            let f = frames[i]
            let t = titles[i]
            let truth = truthID(w)
            let (predicted, cands, stage) = unpack(predict(pid: pid, frame: f, title: t, cg: cg, tol: tol))
            let (anyPred, _, anyStage) = unpack(
                predict(pid: pid, frame: f, title: t, cg: cg, tol: tol, anyLayer: true))
            let entry = truth.flatMap { id in cg.first { $0.id == id } }
            rows.append(Row(
                app: app.localizedName ?? "?", pid: pid, axTitle: t, axFrame: f,
                minimized: axBool(w, kAXMinimizedAttribute as String) ?? false,
                hidden: app.isHidden,
                truth: truth, predicted: predicted, stage: stage, candidates: cands,
                ordinalPredicted: i < pool.count ? pool[i].id : nil,
                truthInPool: truth.map { id in pool.contains { $0.id == id } } ?? false,
                truthOnscreen: entry?.onscreen, cgTitle: entry?.title, poolSize: pool.count,
                subrole: axString(w, kAXSubroleAttribute as String) ?? "",
                role: axString(w, kAXRoleAttribute as String) ?? "",
                regularApp: app.activationPolicy == .regular,
                anyLayerPredicted: anyPred, anyLayerStage: anyStage,
                poolOnscreen: pool.filter(\.onscreen).count,
                assignPredicted: assigned[i]
            ))
        }
    }
    return rows
}

func emit(_ label: String, _ rows: [Row], extra: [String: Any] = [:]) {
    var out: [String: Any] = ["case": label, "rows": rows.map(\.dict)]
    let withTruth = rows.filter { $0.truth != nil }
    out["n"] = withTruth.count
    out["correct"] = withTruth.filter(\.correct).count
    out["wrongAnswer"] = withTruth.filter { $0.predicted != nil && $0.predicted != $0.truth }.count
    out["noAnswer"] = withTruth.filter { $0.predicted == nil }.count
    out["cgTitleAvailable"] = rows.filter { $0.cgTitle != nil }.count
    out["truthMissingFromCGList"] = withTruth.filter { !$0.truthInPool }.count
    out["ordinalCorrect"] = withTruth.filter { $0.ordinalPredicted == $0.truth }.count
    let adopt = withTruth.filter(\.adoptable)
    out["adoptableN"] = adopt.count
    out["adoptableCorrect"] = adopt.filter(\.correct).count
    out["adoptableWrong"] = adopt.filter { $0.predicted != nil && $0.predicted != $0.truth }.count
    out["adoptableNoAnswer"] = adopt.filter { $0.predicted == nil }.count
    out["anyLayerCorrect"] = withTruth.filter { $0.anyLayerPredicted == $0.truth }.count
    out["adoptableAnyLayerCorrect"] = adopt.filter { $0.anyLayerPredicted == $0.truth }.count
    out["assignCorrect"] = withTruth.filter { $0.assignPredicted == $0.truth }.count
    out["assignAnswered"] = withTruth.filter { $0.assignPredicted != nil }.count
    out["assignWrong"] = withTruth.filter { $0.assignPredicted != nil && $0.assignPredicted != $0.truth }.count
    out["adoptableAssignCorrect"] = adopt.filter { $0.assignPredicted == $0.truth }.count
    out["adoptableAssignWrong"] = adopt
        .filter { $0.assignPredicted != nil && $0.assignPredicted != $0.truth }.count
    out.merge(extra) { a, _ in a }
    let data = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

func note(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

// MARK: - main

let args = CommandLine.arguments
let cmd = args.count > 1 ? args[1] : "baseline"
note("AXIsProcessTrusted: \(AXIsProcessTrusted())")
guard AXIsProcessTrusted() else {
    note("no accessibility grant; aborting")
    exit(2)
}

switch cmd {
case "baseline":
    let rounds = args.count > 2 ? Int(args[2]) ?? 1 : 1
    for r in 0 ..< rounds {
        emit("baseline-r\(r)", sweep(tol: 1.0))
        if r + 1 < rounds { Thread.sleep(forTimeInterval: 1.0) }
    }

case "identical":
    // Force several windows of one app onto the exact same frame: the worst case for frames.
    let pid = pid_t(args[2])!
    let wins = axWindows(pid).filter { axBool($0, kAXMinimizedAttribute as String) != true }
    guard wins.count >= 2 else { note("need 2+ windows"); exit(3) }
    let saved = wins.map { axFrame($0) }
    let target = CGRect(x: 200, y: 200, width: 700, height: 500)
    for w in wins.prefix(4) { axSetFrame(w, target) }
    Thread.sleep(forTimeInterval: 1.5)
    emit("identical-frames", sweep(tol: 1.0).filter { $0.pid == pid })
    for (w, f) in zip(wins, saved) { if let f { axSetFrame(w, f) } }

case "move":
    // Sample while an AX move is in flight, so AX frame and CG bounds can disagree.
    let pid = pid_t(args[2])!
    guard let w = axWindows(pid).first(where: { axBool($0, kAXMinimizedAttribute as String) != true }),
          let orig = axFrame(w)
    else { note("no movable window"); exit(3) }
    for step in 0 ..< 12 {
        axSetFrame(w, orig.offsetBy(dx: CGFloat(step) * 37, dy: CGFloat(step) * 11))
        // No settle wait: that is the point of this case.
        emit("mid-move-s\(step)", sweep(tol: 1.0).filter { $0.pid == pid })
    }
    axSetFrame(w, orig)

case "park":
    // SpacialShell parks off-workspace windows in a corner sliver.
    let pid = pid_t(args[2])!
    guard let w = axWindows(pid).first(where: { axBool($0, kAXMinimizedAttribute as String) != true }),
          let orig = axFrame(w), let screen = NSScreen.screens.first
    else { note("no movable window"); exit(3) }
    let f = CGRect(x: screen.frame.width - 12, y: screen.frame.height - 12, width: 900, height: 600)
    axSetFrame(w, f)
    Thread.sleep(forTimeInterval: 1.5)
    emit("corner-parked", sweep(tol: 1.0).filter { $0.pid == pid })
    axSetFrame(w, orig)

case "order":
    // Does the relative order of AXWindows match the relative order of the same windows in the
    // CG list? Measured per app, per option set, over N samples.
    let rounds = args.count > 2 ? Int(args[2]) ?? 1 : 1
    var results: [[String: Any]] = []
    for _ in 0 ..< rounds {
        let all = cgSnapshot()
        let screen = cgSnapshot(onScreenOnly: true)
        for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular && app.processIdentifier != getpid()
        {
            let pid = app.processIdentifier
            let axIDs = axWindows(pid).compactMap { truthID($0) }
            guard axIDs.count >= 2 else { continue }
            var row: [String: Any] = [
                "app": app.localizedName ?? "?", "axCount": axIDs.count, "axIDs": axIDs.map(Int.init),
            ]
            for (label, snap) in [("all", all), ("onscreen", screen)] {
                let listed = snap.filter { $0.pid == pid }.map(\.id).filter { axIDs.contains($0) }
                let axRestricted = axIDs.filter { listed.contains($0) }
                row["\(label)Covered"] = listed.count
                row["\(label)OrderMatches"] = listed == axRestricted
                row["\(label)Reversed"] = listed == axRestricted.reversed()
                row["\(label)IDs"] = listed.map(Int.init)
            }
            results.append(row)
        }
        Thread.sleep(forTimeInterval: 0.4)
    }
    let data = try! JSONSerialization.data(
        withJSONObject: ["case": "order", "rows": results], options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)

case "hide":
    // Cmd-H equivalent: does a hidden app's windows still map?
    let pid = pid_t(args[2])!
    guard let app = NSRunningApplication(processIdentifier: pid) else { note("no app"); exit(3) }
    app.hide()
    Thread.sleep(forTimeInterval: 1.5)
    emit("app-hidden", sweep(tol: 1.0).filter { $0.pid == pid })
    app.unhide()

default:
    note("unknown command: \(cmd)")
    exit(64)
}
