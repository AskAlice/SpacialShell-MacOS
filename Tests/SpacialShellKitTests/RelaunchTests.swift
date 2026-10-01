import Testing
import Foundation
@testable import SpacialShellKit

/// #194: the helper `reload` leaves behind. The pid and the bundle path reach it as positional
/// parameters, so no path can change what the script does, and the script itself parses.
@Suite struct RelaunchTests {
    @Test func pidAndBundleArePositionalParameters() {
        let path = "/Users/a b/Apps/Spacial \"Shell\" $(rm -rf ~).app"
        let args = Relaunch.arguments(pid: 4242, bundlePath: path)
        #expect(args == ["-c", Relaunch.script, "spacial-relaunch", "4242", path])
        #expect(!Relaunch.script.contains("4242") && !Relaunch.script.contains(path))
        // Waits on $1, opens $2 and only $2, with install.sh's -600 retry.
        #expect(Relaunch.script.contains(#"kill -0 "$1""#))
        #expect(Relaunch.script.contains(#"until /usr/bin/open "$2""#))
    }

    @Test func scriptParses() throws {
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-n", "-c", Relaunch.script]
        try sh.run()
        sh.waitUntilExit()
        #expect(sh.terminationStatus == 0)
    }

    /// `Scripts/dev.sh`'s bare binary: nothing to reopen, so nothing is started.
    @Test func onlyAnAppBundleIsReopened() throws {
        #expect(try !Relaunch.start(bundle: URL(fileURLWithPath: "/tmp/build/debug"), pid: 1))
    }
}
