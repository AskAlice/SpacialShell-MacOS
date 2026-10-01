import Foundation

/// #194: `reload`'s second half. Started just before the shell exits, a detached `/bin/sh` waits for
/// this process to be gone, then opens the same bundle again: the poll and LaunchServices' -600
/// retry of `Scripts/install.sh --relaunch-only`. It is launchd's child once we exit, so it outlives us.
public enum Relaunch {
    /// Waits for `$1` to exit (at most 12 s, the quit budget install.sh allows; the new shell refuses
    /// to start beside a live one anyway), then `open`s `$2`, asking again for 5 s while it is refused.
    static let script = """
        i=0; while kill -0 "$1" 2>/dev/null && [ "$i" -lt 240 ]; do i=$((i + 1)); sleep 0.05; done
        i=0; until /usr/bin/open "$2" 2>/dev/null; do i=$((i + 1)); [ "$i" -ge 50 ] && exec /usr/bin/open "$2"; sleep 0.1; done
        """

    /// `/bin/sh`'s arguments. The pid and path are positional parameters, never spliced into the script.
    public static func arguments(pid: Int32, bundlePath: String) -> [String] {
        ["-c", script, "spacial-relaunch", String(pid), bundlePath]
    }

    /// Starts the helper for this process; false when there is nothing to reopen. Only an `.app` is:
    /// `Scripts/dev.sh`'s bare binary has no bundle (its `bundleURL` is the build directory, which
    /// `open` would show in Finder), so there a reload is a plain quit.
    public static func start(bundle: URL, pid: Int32 = getpid()) throws -> Bool {
        guard bundle.pathExtension == "app" else { return false }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = arguments(pid: pid, bundlePath: bundle.path)
        try helper.run()
        return true
    }
}
