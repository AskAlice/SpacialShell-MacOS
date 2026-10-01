import Testing
@testable import SpacialShellKit

/// #193: another app's Secure Event Input stops every key-down reaching the hotkey tap, so the
/// shell watches for it and names the window asking for a password.
@Suite struct SecureInputTests {
    let prompt = WindowRef(id: 7, pid: 632), safari = WindowRef(id: 8, pid: 700), stray = WindowRef(id: 9, pid: 800)

    /// The Exodus prompt alone in the row above the active one (so parked), on a row called Finance.
    func world() -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(safari, kind: .tile, on: "D1")   // focused: it moves down, leaving the prompt above
        w.adopt(prompt, kind: .tile, on: "D1")
        w = CommandRunner.apply(.moveWindowToWorkspace(.down), to: w, in: .test()).0
        w.screens["D1"]!.workspaces[0].name = "Finance"
        return w
    }
    var exodus: SecureInputCandidate { SecureInputCandidate(ref: prompt, app: "Exodus", title: "Enter Password", secureField: true) }

    @Test func aPasswordWindowIsNamedWithItsWorkspaceAndCanBeShown() throws {
        var watch = SecureInputWatch()
        let listed = watch.observe(on: true, candidates: [exodus], world: world())
        let p = try #require(listed?.first)
        #expect(p.severity == .error)
        #expect(p.message == "Exodus is waiting for a password ('Enter Password', on workspace 1 'Finance'). SpacialShell's hotkeys are blocked until it's answered or closed.")
        #expect(p.key.hasPrefix(Problem.Key.secureInput))
        #expect(p.action?.title == "Show window")
        #expect(p.action?.command == .focusWindowRef(prompt))
    }

    @Test func noCandidateIsAGenericProblemWithNothingToShow() throws {
        var watch = SecureInputWatch()
        let listed = watch.observe(on: true, candidates: [], world: world())
        let p = try #require(listed?.first)
        #expect(p == .secureInputUnknown)
        #expect(p.message.hasPrefix("An app has secure keyboard entry on"))
        #expect(p.action == nil)
    }

    @Test func aWindowTheShellDoesNotHoldIsNamedButNotOffered() throws {
        var watch = SecureInputWatch()
        let c = SecureInputCandidate(ref: stray, app: nil, title: "", secureField: false)
        let listed = watch.observe(on: true, candidates: [c], world: world())
        let p = try #require(listed?.first)
        #expect(p.message == "An app is waiting for a password. SpacialShell's hotkeys are blocked until it's answered or closed.")
        #expect(p.action == nil)
    }

    @Test func aRepeatObservationIsNotReportedAgain() {
        var watch = SecureInputWatch()
        _ = watch.observe(on: true, candidates: [exodus], world: world())
        let again = watch.observe(on: true, candidates: [exodus], world: world())
        #expect(again == nil)
        var fresh = SecureInputWatch()
        let off = fresh.observe(on: false, candidates: [], world: world())
        #expect(off == nil, "off, and it was off")
    }

    @Test func aNewCandidateReplacesTheOldEntry() throws {
        var watch = SecureInputWatch()
        var problems = Problems()
        let first = watch.observe(on: true, candidates: [exodus], world: world())
        problems.replace(prefix: Problem.Key.secureInput, with: try #require(first))
        let s = SecureInputCandidate(ref: safari, app: "Safari", title: "Log in", secureField: true)
        let second = watch.observe(on: true, candidates: [s], world: world())
        problems.replace(prefix: Problem.Key.secureInput, with: try #require(second))
        #expect(problems.all.count == 1)
        #expect(problems.all.first?.message.hasPrefix("Safari is waiting") == true)
        #expect(problems.all.first?.action?.command == .focusWindowRef(safari))
    }

    @Test func secureInputTurningOffClearsIt() throws {
        var watch = SecureInputWatch()
        var problems = Problems()
        let on = watch.observe(on: true, candidates: [exodus], world: world())
        problems.replace(prefix: Problem.Key.secureInput, with: try #require(on))
        let off = watch.observe(on: false, candidates: [], world: world())
        let cleared = try #require(off)
        #expect(cleared.isEmpty)
        problems.replace(prefix: Problem.Key.secureInput, with: cleared)
        #expect(problems.isEmpty)
    }

    @Test func titlesMatchTheWordNotASubstring() {
        #expect(SecureInputCandidate.looksLikePasswordPrompt("Enter Password"))
        #expect(SecureInputCandidate.looksLikePasswordPrompt("Passphrase required"))
        #expect(!SecureInputCandidate.looksLikePasswordPrompt("1Password"))
        #expect(!SecureInputCandidate.looksLikePasswordPrompt("Passwords"))
    }
}
