import Testing
import AppKit
import ApplicationServices
import Darwin
import Foundation
import SpacialShellKit
@testable import SpacialShellPlatform

/// #126: the Dock poll against the real Dock — what one read costs, which the issue asks to be
/// measured. Read-only. Without an Accessibility grant (or with no Dock) there is nothing to read,
/// and the test says so rather than failing.
///
/// Three numbers per poll: wall time (mostly waiting on the Dock over AX IPC), our thread's CPU,
/// and the Dock's CPU answering (its CPU over the burst, less its idle rate over as long).
@Suite(.serialized) struct DockReaderTests {
    @Test func readsTheDockAndReportsWhatAPollCosts() throws {
        guard AXIsProcessTrusted() else {
            print("DockReaderTests: no Accessibility grant — nothing measured")
            return
        }
        var reader = DockReader()
        guard let first = reader.read() else {
            print("DockReaderTests: no Dock to read — nothing measured")
            return
        }
        #expect(!first.items.isEmpty)
        // Some running app always has a Dock item (Finder, at the least), and matches by bundle URL.
        #expect(first.items.contains { !$0.pids.isEmpty })
        let dock = try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first).processIdentifier

        let n = 80
        var wall: [Double] = []
        let dockBefore = Self.cpu(of: dock), threadBefore = Self.threadCPU(), start = Self.now()
        for _ in 0..<n {
            let t = Self.now()
            _ = reader.read()
            wall.append(Self.now() - t)
        }
        let burst = Self.now() - start
        let dockBusy = Self.cpu(of: dock) - dockBefore, threadBusy = Self.threadCPU() - threadBefore
        // The Dock's own idle rate over as long, to take out of its share.
        let idleBefore = Self.cpu(of: dock)
        Thread.sleep(forTimeInterval: burst)
        let dockIdle = Self.cpu(of: dock) - idleBefore

        wall.sort()
        let us = 1e6, mean = wall.reduce(0, +) / Double(n)
        let ours = threadBusy / Double(n), theirs = max(0, dockBusy - dockIdle) / Double(n)
        let perSecond = 1 / DockWatcher.interval
        print(String(format: """
            DockReaderTests: %d Dock items, %d polls. Wall: mean %.0f µs, p50 %.0f, p95 %.0f, max %.0f. \
            CPU per poll: ours %.0f µs, the Dock's %.0f µs. At %.0f ms: %.2f%% of a core here, %.2f%% in the Dock.
            """,
            first.items.count, n, mean * us, wall[n / 2] * us, wall[n * 95 / 100] * us, wall[n - 1] * us,
            ours * us, theirs * us, DockWatcher.interval * 1000, ours * perSecond * 100, theirs * perSecond * 100))
    }

    private static func now() -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9 }
    private static func threadCPU() -> Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9 }

    /// Another process's user + system CPU, in seconds. `rusage_info` reports mach time units.
    private static func cpu(of pid: pid_t) -> Double {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        guard rc == 0 else { return 0 }
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(info.ri_user_time + info.ri_system_time) * Double(tb.numer) / Double(tb.denom) / 1e9
    }
}
