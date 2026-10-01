import Testing
import Foundation
import SpacialShellProtocol
@testable import SpacialShellKit

@Suite struct WireStateTests {
    @Test func reflectsWorld() throws {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .column)
        w.adopt(WindowRef(id: 1, pid: 1), kind: .tile, on: "D1")
        w.adopt(WindowRef(id: 2, pid: 1), kind: .tile, on: "D1")
        let s = WireState.test(world: w)
        #expect(s.screens.map(\.display) == ["D1", "D2"])
        #expect(s.screens[0].isFocused && !s.screens[1].isFocused)
        #expect(s.screens[0].workspaces[0].windowCount == 2)
        #expect(s.screens[0].workspaces[0].isActive)
        #expect(s.screens[0].workspaces[0].layout == "column")
        let json = try JSONValue(encoding: s)          // wire round-trip
        #expect(try json.decode(WireState.self) == s)
    }

    /// #198/#199: a workspace carries the title it goes by everywhere (#183: its category,
    /// capitalised, else its name) and each window its title and app name, so a client can name
    /// rows and find a window by app and title.
    @Test func carriesTitlesAndAppNames() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let tab = WindowRef(id: 1, pid: 7)
        w.adopt(tab, kind: .tile, on: "D1")
        let s = WireState.test(world: w, bundleIDs: [tab: "com.x.browser"], titles: [tab: "Pull requests"],
                               appNames: [7: "Brave Origin"], categoryOverrides: ["com.x.browser": .web])
        let ws = s.screens[0].workspaces[0]
        #expect(ws.title == "Web browsing")
        #expect(ws.windows[0].title == "Pull requests" && ws.windows[0].appName == "Brave Origin")
        #expect(s.screens[0].workspaces.last?.title == "New workspace", "the trailing empty row")
    }
}


/// #199: finding a window by app and title — what `spacialctl focus-window --app … --title …` asks.
@Suite struct FindWindowTests {
    let pr = WindowRef(id: 1, pid: 7), docs = WindowRef(id: 2, pid: 7), zsh = WindowRef(id: 3, pid: 9)
    let notes = WindowRef(id: 4, pid: 11)

    /// Row 1: the two Brave tabs; row 2: the terminal and a note. Focus on the terminal.
    func state() -> WireState {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(pr, kind: .tile, on: "D1"); w.adopt(docs, kind: .tile, on: "D1")
        let second = w.screens["D1"]!.workspaces[1].id
        w.adopt(zsh, kind: .tile, on: "D1", workspace: second); w.adopt(notes, kind: .tile, on: "D1", workspace: second)
        w.focus = Focus(screen: "D1", window: zsh)
        return WireState.test(world: w,
                              bundleIDs: [pr: "com.brave.Browser.origin", docs: "com.brave.Browser.origin",
                                          zsh: "co.zeit.hyper", notes: "com.apple.Notes"],
                              titles: [pr: "Pull requests · AskAlice/SpacialShell", docs: "AXUIElement docs",
                                       zsh: "~/code — zsh", notes: "Shopping list"],
                              appNames: [7: "Brave Origin", 9: "Hyper", 11: "Notes"])
    }

    @Test func appAndTitleTogether() {
        #expect(state().findWindow(app: "brave", title: "PULL REQ", index: nil, first: false) == .success(pr))
    }

    @Test func appByNameBundleIDOrPid() {
        let s = state()
        #expect(s.findWindow(app: "hyper", title: nil, index: nil, first: false) == .success(zsh))
        #expect(s.findWindow(app: "com.apple.Notes", title: nil, index: nil, first: false) == .success(notes))
        #expect(s.findWindow(app: "Notes", title: nil, index: nil, first: false) == .success(notes))   // bundle-id suffix or name
        #expect(s.findWindow(app: "9", title: nil, index: nil, first: false) == .success(zsh))
    }

    @Test func titleAlone() {
        #expect(state().findWindow(app: nil, title: "shopping", index: nil, first: false) == .success(notes))
    }

    /// Several matches: an error that lists them, numbered in display, row, tab order — the order
    /// `--index` counts in, from 1.
    @Test func ambiguityListsThemAndIndexPicks() {
        let s = state()
        guard case .failure(let e) = s.findWindow(app: "brave", title: nil, index: nil, first: false) else {
            Issue.record("ambiguous"); return
        }
        #expect(e.message.contains("[1] Brave Origin · Pull requests"))
        #expect(e.message.contains("[2] Brave Origin · AXUIElement docs"))
        #expect(s.findWindow(app: "brave", title: nil, index: 2, first: false) == .success(docs))
        guard case .failure(let out) = s.findWindow(app: "brave", title: nil, index: 3, first: false) else {
            Issue.record("out of range"); return
        }
        #expect(out.message.contains("[2]"))
    }

    /// `--first`: the focused window if it matches, else one in the focused display's shown row,
    /// else the first listed.
    @Test func firstPrefersTheFocusedThenTheShownRow() {
        let s = state()
        #expect(s.findWindow(app: nil, title: "o", index: nil, first: true) == .success(zsh))
        #expect(s.findWindow(app: "brave", title: nil, index: nil, first: true) == .success(pr))
    }

    @Test func noneMatchesOrNothingAsked() {
        let s = state()
        #expect(s.findWindow(app: "safari", title: nil, index: nil, first: false) == .failure(FindWindowRefusal("no window matches app \"safari\"")))
        guard case .failure = s.findWindow(app: nil, title: nil, index: nil, first: false) else { Issue.record("needs one"); return }
        guard case .failure = s.findWindow(app: "brave", title: nil, index: 1, first: true) else { Issue.record("exclusive"); return }
    }
}
