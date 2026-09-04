# M2 research notes — overlay panels, IPC/CLI patterns (verified 2026-08-18/19)

: "Verify platform facts for the M2 shell UI (AppKit overlay panels) and a Raycast extension talking to SpacialShell over IPC",
  "agentCount": 6,
  "logs": [
    "[research:raycast-ext] failed: API Error: Server error mid-response. The response above may be incomplete."
  ],
  "result": {
    "synthesis": "# SpacialShell M2 — spec-ready facts (research merged with verification)

Legend: [H]=high, [M]=medium, [L]=low confidence. "Verified" = independently re-checked in the verdict pass (SDK headers on this Mac, raw upstream sources at pinned commits, or live probe on macOS 26.5).

---

## TOPIC 1: OVERLAY PANELS (workspace rail + window-tab bar)

### 1a. Settled facts

**Window class / style mask**
- [H] Use `NSPanel`; `.nonactivatingPanel` (1<<7) is NSPanel-only and is what stops clicks from activating the app. `.hudWindow` (1<<13), `.utilityWindow` (1<<4) also NSPanel-only. — NSPanel.h L13-19; NSWindow.h L49-52, L64-67; https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel
- [H] Accessory activation policy (`AppRuntime.swift:39`) does NOT prevent activation on window click ("may be activated programmatically or by clicking on one of its windows"); `.nonactivatingPanel` is required. Accessory apps are absent from Cmd+Tab. — https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory
- [H] `NSPanel([.borderless,.nonactivatingPanel])` on 26.5: canBecomeKey=false, canBecomeMain=false (borderless mask is the cause; a titled nonactivating panel reports canBecomeKey=true). Override both to `false` as guard. — canbecomekey.json ("title bar or a resize bar"), canbecomemain.json; NSWindow.h L438-439; live probe.
- [H] Defaults measured on 26.5 for `NSPanel([.borderless,.nonactivatingPanel])`: hidesOnDeactivate=FALSE (AppKit sets false when nonactivating; TRUE for plain NSPanel), isReleasedWhenClosed=false, isOpaque=TRUE, hasShadow=TRUE, isMovable=TRUE, isMovableByWindowBackground=false, ignoresMouseEvents=false, acceptsMouseMovedEvents=false, animationBehavior=.default, sharingType=.readOnly, level=0, collectionBehavior rawValue 0. With `[.nonactivatingPanel,.borderless,.hudWindow,.utilityWindow]` isMovableByWindowBackground defaults TRUE. — live probe; hidesondeactivate.json; isreleasedwhenclosed.json. Consequence: must set isOpaque=false, backgroundColor=.clear, hasShadow=false, isMovable=false explicitly; hidesOnDeactivate=false / isReleasedWhenClosed=false are belt-and-braces.

**Window levels (measured 26.5, CGWindowLevelForKey)**
- [H] desktop -2147483623, backstopMenu -20, normal 0, floating 3 (=tornOffMenu), modalPanel 8, utility 19, dock 20, mainMenu 24, status 25, popUpMenu 101, overlay 102, help 200, dragging 500, screenSaver 1000, assistiveTechHigh 1500. NSWindow.Level: .floating 3, .dock 20 (deprecated 10.13), .mainMenu 24, .statusBar 25, .popUpMenu 101, .screenSaver 1000. `NSWindow.Level(rawValue: kCGDockWindowLevel-1) == 19 == utility`. — CGWindowLevel.h L22-45, L64-81; NSWindow.h L192-201, L1066; AppKit.apinotes L9117-9118; scratchpad/lv probe.
- [H] "The stacking of levels takes precedence over the stacking of windows within each level." — https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct
- [H] Level 19 is above every window at standard app levels (0/3/8) and below Dock/menu bar/status items/menus. It does NOT beat third-party overlays that choose higher levels (AltTab .popUpMenu 101; OmniWM offers .statusBar/.popUpMenu/.screenSaver). Keep < 500 so drag images render above the panel (AltTab: .screenSaver "makes drag and drop on top the main window impossible"). — AltTab ThumbnailsPanel.swift@33c6615 L19-21; CGWindowLevel.h L78.
- [H] Peers: AeroSpace HUD `.floating` (NSPanelHud.swift L11); SketchyBar default kCGBackstopMenuLevel(-20), topmost=window→3, topmost=on→25 (bar_manager.c L37, L291-303); AltTab .popUpMenu.

**collectionBehavior**
- [H] `.canJoinAllSpaces` (1<<0) "The menu bar behaves this way"; `.transient` (1<<3) "hidden by exposé. Default if windowLevel != NSNormalWindowLevel"; `.stationary` (1<<4) "Unaffected by exposé... like desktop window" / "Mission Control doesn't affect the window"; `.ignoresCycle` (1<<6) default for non-normal levels (Cmd+` only); `.fullScreenAuxiliary` (1<<8) "can be shown with the fullscreen window"; `.canJoinAllApplications` (1<<18, macOS 13) "join other apps' sets and full screen spaces when eligible... floating windows and system overlays" (exclusive with .primary/.auxiliary). Level-derived defaults are implicit — rawValue stays 0 after setting level 19. — NSWindow.h L92-149; Apple docs {stationary,transient,canjoinallspaces,fullscreenauxiliary,ignorescycle,canjoinallapplications}.json; live probe.
- [H] Peer configs: AeroSpace NSPanelHud = `[.nonactivatingPanel,.borderless,.hudWindow,.utilityWindow]`, .floating, `[.canJoinAllSpaces,.fullScreenAuxiliary]`, hidesOnDeactivate false, isMovableByWindowBackground false, backgroundColor .clear, alphaValue 1, hasShadow true, orderFrontRegardless(), NSHostingView subview of contentView (NSPanelHud.swift L3-19; VolumeView.swift L16-23). OmniWM WorkspaceBarPanel = `[.borderless,.nonactivatingPanel]`, `[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]`, isOpaque false, .clear, hasShadow false, ignoresMouseEvents false, isFloatingPanel true, hidesOnDeactivate false, becomesKeyOnlyIfNeeded true, isMovable false, isMovableByWindowBackground false, level user-selectable, NSHostingView.sizingOptions=[], appearance mirrored from NSApp, constrainFrameRect(_:to:) clamps to screen.frame (WorkspaceBarManager.swift L7-36, L280-297, L607-636; WorkspaceBarPanel.swift L7-22). OmniWM is macOS 26-only (Package.swift .macOS(.v26)). AltTab ThumbnailsPanel = `.nonactivatingPanel`, canBecomeKey true, animationBehavior .none, hidesOnDeactivate false, .clear, .canJoinAllSpaces, .popUpMenu, setAccessibilitySubrole(.unknown) (L3-26).

**Native fullscreen of other apps**
- [M] Nonactivating panel of an accessory app + `[.canJoinAllSpaces,.fullScreenAuxiliary]` DOES appear over other apps' fullscreen spaces (FunWithPanels README L75-81 + AppDelegate.swift L13-30, L127-141; forum 783576). Failures: regular-app NSWindow via makeKeyAndOrderFront (forum 26677); screenSaver+canJoinAllSpaces+canJoinAllApplications WITHOUT fullScreenAuxiliary disappears (forum 759780). Peers mostly hide there: SketchyBar `SLSSpaceGetType(...) != 4 || show_in_fullscreen` (bar_manager.c L956), yabai #71 (CHANGELOG L796), Rift stack_line.rs L222-227; OmniWM shows (+placeholder panels, ARCHITECTURE.md L777). Our backend already has AXFullScreen (AXApp.swift:405, accessibility.swift:217-218) and activeSpaceDidChangeNotification (AXWindowBackend.swift:118) — hiding per display needs no private API. Not first-hand tested.

**Drawing / material**
- [H] NSVisualEffectView `.behindWindow` (default; "blends and blurs... with the contents behind the window") requires non-opaque clear panel. Materials: .sidebar (10.11), .headerView (10.14), .hudWindow (10.14), .popover, .menu; .titlebar historically withinWindow-only. Set `state = .active` ("Use the active look always") because panel is never key. `maskImage` on contentView effect view "will correctly influence the window's shadow". Defaults on 26.5: blendingMode 0, state 0 (.followsWindowActiveState), material 0 (deprecated appearanceBased). — NSVisualEffectView.h L18-107; behindwindow.json; AltTab patch 33c6615 L321-360; probe.
- [H] Performance: behind-window blur computed by window server, "isn't exactly free", recomputed when content updates; non-opaque windows lose occlusion culling; withinWindow requires layer backing. Mitigations: hasShadow=false, sizingOptions=[] ("fewer options can improve performance"), diff-and-apply surfaces. — https://asciiwwdc.com/2014/sessions/220; swiftui/nshostingview/sizingoptions.json; OmniWM L291, L618. (2014 talk predates Liquid Glass; no 26 numbers.)
- [H] macOS 26: `NSGlassEffectView` (contentView, cornerRadius, tintColor, style .regular/.clear) + `NSGlassEffectContainerView(spacing)` API_AVAILABLE(macos(26.0)); NSVisualEffectView not deprecated (only legacy materials). Bugs: forum 810314 (26.2, borderless transparent Dock-level window: glass backdrop cached, doesn't update; 0 replies); macOS 26.4 release notes "Fixed: ... non-opaque window that hosts glass content will correctly update the backdrop ... even if the window is inactive (166828089)"; forum 818901 (Mar 2026: non-key panel always foggy/inactive glass even with nonactivating + canBecomeKeyWindow=false; one DTS reply requesting sample, no fix). AltTab: NSGlassEffectView(.clear) + private `set_variant:` (present on 26.5 per probe) only when appIcons style AND selector exists, else NSVisualEffectView fallback (patch L286-372). Apple: "If you apply Liquid Glass effects to a custom control, do so sparingly." — NSGlassEffectView.h L14-57; https://developer.apple.com/documentation/macos-release-notes/macos-26_4-release-notes.
- [H] Private-API alternative (not recommended for us): JankyBorders/SketchyBar/Rift/yabai-5.x draw with SkyLight windows — JankyBorders `SLSNewWindow` (managed) or `SLSNewWindowWithOpaqueShapeAndContext` (unmanaged) with tags (1<<1)|(1<<9), SLSSetWindowResolution/Tags/Opacity(0), shadow density 0, level copied from target via SLSWindowQueryWindows/SLSWindowIteratorGetLevel, ordered via SLSTransactionOrderWindow (window.h L198-289; border.c L164-254). SketchyBar tags (1<<1)|(1<<16), SLSTransactionSetWindowLevel on 14+, sticky via SLSSpaceCreate+SLSSpaceSetAbsoluteLevel+SLSShowSpaces+SLSSpaceAddWindowsAndRemoveFromSpaces (window.c L53-116, L289-300). Rift cgs_window.rs L90-301, stack_line.rs L137-227 (NSNormalWindowLevel, tags 1<<3), mission_control.rs L1269-1274 (popUpMenu + blur 30). yabai removed borders in 6.0.0 (CHANGELOG L315, L330); `external_bar <main|all|off>:<top>:<bottom>` = manual layout reservation (yabai.asciidoc L140-148). OmniWM: NSPanels for bars, SkyLight only for focus border (+ private `IgnoreForScreencaptureWindowSelection`), all surfaces registered by CGS window number in SurfaceCoordinator (ARCHITECTURE.md L409-417, L787-789).
- [H] AeroSpace draws no bar/borders (delegates to JankyBorders/SketchyBar; goodies.adoc L36-48, L92-108); UI = NSStatusItem menu + NSPanelHud (volume, secure-input) + a SwiftUI `Window` scene for messages (MessageView.swift L5-23; sets `$0.level = .floating`; notes SwiftUI `.windowLevel` is macOS 15+, L22).
- [M] SwiftUI `Scene.windowLevel(_:)` exists in 26 SDK but `@available(macOS 15.0,*)` (SwiftUI.swiftinterface L573-579) — NSPanel+NSHostingView is the macOS 14 route.

**SwiftUI-in-panel pitfalls**
- [H] NSHostingView as contentView updates window contentMin/MaxSize from SwiftUI; default sizingOptions rawValue 7 (.standardBounds); set `[]` for fixed frames (macOS 13+). — sizingoptions.json; probe.
- [H] TextField in a never-key panel never becomes first responder — rename UI cannot live in these panels. — https://fazm.ai/blog/swiftui-floating-panel
- [H] Click-through: `NSView.acceptsFirstMouse(for:)` default false ("the event simply activates the window"); NSHostingView returns false on 26.5 (probe). Pre-macOS 15 only `.bordered` SwiftUI buttons accepted first-mouse; "macOS 15 beta 2 fixed these problems" — with macOS 14 minimum, subclass NSHostingView overriding acceptsFirstMouse → true (OmniWM's AppKit TabRail.swift L553 does; its SwiftUI bar relies on 26 behaviour). — https://christiantietze.de/posts/2024/04/enable-swiftui-button-click-through-inactive-windows/; acceptsfirstmouse(for:) doc.
- [H] Hover: FB11990170 (feedback-assistant/reports#384) concerns `onContinuousHover` not firing when app inactive (13.2, marked Fixed, no version). AppKit-reliable path: NSTrackingArea `.activeAlways` (0x80; "Not supported for NSTrackingCursorUpdate" → cursor manually). Do NOT set `acceptsMouseMovedEvents=true` (DTS: "strongly discouraged... triggers a flood of events"). — NSTrackingArea.h L19-36; https://developer.apple.com/forums/thread/736594.
- [H] NSHostingView isOpaque=false → mouseDownCanMoveWindow=true (probe); keep isMovable=false + isMovableByWindowBackground=false or empty-area clicks drag the panel. — mouseDownCanMoveWindow doc.
- [H] Never call NSApp.activate when showing; show via `orderFrontRegardless()` ("even if its application isn't active, without changing either the key window or the main window"), hide via `orderOut(nil)`; `animationBehavior = .none` suppresses inferred fade (NSWindow.h L538-540; AltTab L11). `isFloatingPanel=true` sets level 3; a later explicit `level=` wins (probe: 0→3→19).
- [H] Drag: `beginDraggingSession(with:event:source:)` (10.7, NSView.h L488) from any view given mouseDown NSEvent; drag images at level 500. Fn: `NSEvent.ModifierFlags.function` (1<<23, "Set if any function key is pressed" — also arrows/F-keys; NSEvent.h L175) or existing tap `.maskSecondaryFn` (HotkeyTap.swift:140).

**Exclusion from our own AX backend**
- [H] Already excluded twice: RefreshSession.swift:20-24 filters `.activationPolicy == .regular && pid != mine && != loginwindow` (our app is .accessory → fails filter anyway); AXApp.swift:102-104 returns nil for own pid ("AX requests to our own pid deadlock"). windowLevelCache.swift:9-41 (CGWindowList, layer 0→.normalWindow, 3→.alwaysOnTopWindow) is only consulted for AX-discovered windows (WindowClassifier.swift:18-30). Any future CGWindowList classifier must drop `kCGWindowOwnerPID == getpid()` or windowNumbers of owned NSWindows. Third-party AX tools: `setAccessibilitySubrole(.unknown)` (AltTab L22-23).
- [H] `sharingType = .none` excludes from capture but "will also not be able to participate in a number of system services... use with caution"; NSWindowSharingReadWrite deprecated 10.5-15.0. Default .readOnly (probe). — NSWindow.h L520-522, L1068.

**Geometry / displays**
- [H] `NSScreen.frame` includes menu bar+dock; `visibleFrame` excludes dock/menu bar and, on notch Macs, the bezel band ("Don't cache the rectangle... Even when dock hiding is enabled, the rectangle... may be smaller than the full screen"); `auxiliaryTopLeftArea/auxiliaryTopRightArea` + `safeAreaInsets` macOS 12 (NSScreen.h L56-65). Live probe (built-in 1512x982): frame (0,0,1512,982), visibleFrame (0,0,1512,949), safeAreaInsets.top 32, auxiliaryTopLeftArea (0,950,663,32), frame.maxY-visibleFrame.maxY = 33, NSStatusBar.system.thickness 22 (unusable), NSMenu.menuBarHeight 0 for non-main menus (NSMenu.h L158-160). Earlier external 1920x1080 measurement: band 30. Treat frame.maxY-visibleFrame.maxY as "reserved top band" (may be 1pt larger than the menu bar); prefer safeAreaInsets.top on notch displays. OmniWM: menuBarHeight fallback 28 (WorkspaceBarGeometry.swift L131-134); bar origin.y = visibleFrame.maxY - barHeight (L114-116).
- [H] visibleFrame knows nothing about our panels → Kit layout rect = visibleFrame minus (top: barHeight, left: railWidth) (yabai external_bar analogue). `NSMenu.menuBarVisible()` reflects only this app (NSMenu.h L80-82); public proxy for system auto-hide = frame.maxY == visibleFrame.maxY. DisplayTopology.swift:15-16 already flips to top-left, :20-31 UUID via CGDisplayCreateUUIDFromDisplayID, :35-51 main = screen at (0,0).
- [H] Reconfiguration: `NSApplication.didChangeScreenParametersNotification` (posted on main actor); NSScreen.screens must not be cached; `isMovable=false` ⇒ "will not be moved (or resized) by the system in response to a display reconfiguration" (NSWindow.h L411) → we reposition via setFrame(_:display:) ourselves; NSWindow.screen nil when offscreen; window server limits ±16,000 pos / 10,000 size; OmniWM constrainFrameRect(_:to:) clamps to screen.frame so AppKit never pushes the panel into visibleFrame (WorkspaceBarPanel.swift L10-22, WorkspaceBarManager.swift L137).

### 1b. Verify empirically (spike on 26.5 + a 14.x VM)
1. `.stationary` at level 19: visible under Mission Control overlay or covered? (Apple only says "like the desktop window".) Default `.transient` = hidden during Mission Control.
2. NSVisualEffectView `state=.active` in a never-key panel on 26.x: active vs foggy look (forum 818901 doesn't state whether state was set). If NSGlassEffectView tried: check stale-backdrop (fixed 26.4) and non-key foggy variant; `set_variant:` private selector exists on 26.5.
3. SwiftUI `.onHover` in never-key nonactivating panel on 14.x (OmniWM proves it on 26 only). Fallback: NSViewRepresentable with NSTrackingArea(.activeAlways,.mouseEnteredAndExited,.inVisibleRect).
4. `.plain`/custom SwiftUI Button click-through on 14.x without acceptsFirstMouse override (expected to fail pre-15).
5. Panels over another app's fullscreen space with `[.canJoinAllSpaces,.fullScreenAuxiliary]` (+ `.canJoinAllApplications` on 13+) from our accessory process — forum-grade evidence only.
6. Menu-bar band on external displays (30 vs 33 vs safeAreaInsets) — re-measure with the 1920x1080 display attached; confirm bar y = visibleFrame.maxY - barHeight leaves no gap.
7. Drag session from a level-19 panel: drag image (500) renders above panel; Fn detection via tap `.maskSecondaryFn` vs NSEvent `.function` during drag.
8. Blur cost with 2 panels/display × N displays under continuous tab updates (Activity Monitor WindowServer CPU) — decide `.sidebar` vs `.hudWindow` vs flat color.

### 1c. Design recommendation (concrete)
```swift
final class OverlayPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
  override func constrainFrameRect(_ r: NSRect, to s: NSScreen?) -> NSRect { r } // or clamp to targetScreen.frame
}
// init(contentRect:, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen)
level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)   // 19; use .floating(3) if coexisting w/ palettes is acceptable
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle] // + .canJoinAllApplications if #available(macOS 13,*) and we want over-fullscreen; add .stationary only after spike 1
hidesOnDeactivate = false; isReleasedWhenClosed = false
isOpaque = false; backgroundColor = .clear; hasShadow = false
isMovable = false; isMovableByWindowBackground = false
animationBehavior = .none; ignoresMouseEvents = false
setAccessibilitySubrole(.unknown)                    // hide from 3rd-party AX tools
contentView = NSVisualEffectView(material: .sidebar /*rail*/ or .headerView/.hudWindow /*bar*/, blendingMode: .behindWindow, state: .active)
  ↳ subview ClickThroughHostingView<Root>: NSHostingView { override func acceptsFirstMouse(for:) -> Bool { true } }, sizingOptions = [] (13+)
show: orderFrontRegardless(); hide/Zen: orderOut(nil)
```
- Hover: use NSTrackingArea `.activeAlways` wrapper (NSViewRepresentable) rather than trusting `.onHover` on 14.x; never `acceptsMouseMovedEvents=true`.
- Rename UI: not in panels (never key). Do rename via IPC/Raycast, hotkey-driven modal in a separate key-capable window, or inline in an NSPanel that *can* become key only when explicitly summoned.
- Materials: NSVisualEffectView on all OS versions; optional `#available(macOS 26.4,*)` NSGlassEffectView(.clear) path behind a flag after spike 2.
- Geometry: one PanelSet per NSScreen keyed by display UUID; on `didChangeScreenParametersNotification` re-enumerate NSScreen.screens, orderOut panels for vanished displays, setFrame for the rest. Bar frame = (visibleFrame.minX, visibleFrame.maxY - barH, visibleFrame.width, barH); rail = (visibleFrame.minX, visibleFrame.minY, railW, visibleFrame.height - barH). Kit layout rect = visibleFrame inset (top: barH, left: railW). Do not use NSStatusBar.thickness.
- Fullscreen: on activeSpaceDidChange / AXFullScreen change, orderOut both panels of a display whose focused window isFullscreen (peer default), unless config `show_in_fullscreen`.
- Own-window exclusion: existing pid/.accessory filters suffice; add `kCGWindowOwnerPID == getpid()` guard to any new CGWindowList consumer; optionally register owned windowNumbers in a SurfaceRegistry (OmniWM pattern) for hit-testing/capture exclusion.
- Fn+Drag: mouseDown in tab/rail item → beginDraggingSession from the hosting NSView; require Fn via HotkeyTap's `.maskSecondaryFn` state (or NSEvent.modifierFlags.contains(.function)); drop targets = other tabs / rail items / other display's panels; drag image at 500 stays above level 19.

---

## TOPIC 2: IPC (unix socket + CLI + Raycast)

### 2a. Settled facts

**Peer implementations**
- [H] AeroSpace (main@c548c7f8): NWListener + `NWParameters.tcp` + `requiredLocalEndpoint = .unix(path:)`, unconditional `removeItem` of old socket (no liveness probe), no chmod/getpeereid anywhere (server.swift L5-18). Path `/tmp/bobko.aerospace-\(NSUserName()).sock` (debug: bobko.aerospace.debug) (commonUtil.swift L5-6; appMetadata.swift L1-8) — NSUserName() works without $USER. Framing: 4-byte native-endian UInt32 length + JSON (NWConnectionEx.swift L5-15, L94-115); handshake: client writes UInt32 SOCKET_PROTOCOL_VERSION=1, server answers its version, cancels on mismatch, CLI prints "restart AeroSpace" (clientServer.swift L3; server.swift L46-49; NWConnectionEx L41-52). Request `{args,stdin,windowId:UInt32??,workspace:String??}` (env AEROSPACE_WINDOW_ID/WORKSPACE), answer `{exitCode,stdout,stderr,serverVersionAndHash}` (clientServer.swift L5-56; server.swift L88-113). Loops multiple requests per connection; parse error → exitCode 2 + "Can't parse request"; disabled server → 2 unless `enable`; `subscribe` dispatched before enabled check (server.swift L51-79). Exit codes 0/2, and 1 for conditional commands `true`,`false`,`test`,`test-not` (ExitCode.swift L10-11, L43-47; TrueCmdArgs/FalseCmdArgs/TestCmdArgs/TestNotCmdArgs). Subscribe: `subscribe [--all] [--no-send-initial] <event>...`, @MainActor subscriber map, initial state, `readTillError` until disconnect, frames encoded `[.withoutEscapingSlashes,.sortedKeys]` with `_event` discriminator; events focus-changed, focused-monitor-changed, focused-workspace-changed, mode-changed, window-detected, binding-triggered (subscriptions.swift L10-59; SubscribeCmdArgs.swift L9-12, L56-63; docs/aerospace-subscribe.adoc). `list-* --json` = array keyed by --format var names, `[.prettyPrinted,.withoutEscapingSlashes,.sortedKeys]` (formatToJson.swift L7-25; JsonEncoderEx.swift L6). Packaging: executableTarget `Cli` deps [Common] only, product `aerospace`; `swift build -c release --arch arm64 --arch x86_64 --product aerospace`; signed separately; shipped OUTSIDE .app at `<zip>/bin/aerospace`; cask `app` + `binary` + postflight xattr (Package.swift L18, L65-71; build-release.sh L26, L58, L64-77, L118; script/build-brew-cask.sh L62-68).
- [H] yabai (master@dd84572): `/tmp/yabai_%s.socket` from `getenv("USER")` (aborts if unset); 4-byte int length + NUL-separated argv + trailing NUL; shutdown(SHUT_WR); response chunk starting `\x07` → stderr + EXIT_FAILURE (yabai.c L2, L60-119; macros.h L18). Server: unlink/bind/`chmod 0600`/listen(SOMAXCONN)/FD_CLOEXEC; accepted fd posted to event loop; `handle_message(FILE*, char*)` via fdopen; `daemon_fail` prefixes `\x07` (message.c L3003-3044, L418-426; event_loop.c L1614-1646). No event stream: `signal --add event= action=` forks `/usr/bin/env sh -c` with YABAI_* env (event_signal.c L64-268; yabai.asciidoc L461-500, L726-756). Hand-emitted JSON queries.
- [H] Rift (main@be8afef): JSON-over-Mach, bootstrap "git.acsandmann.rift" (env RIFT_BS_NAME), MAX_MESSAGE_SIZE 262144; externally-tagged `RiftRequest`, untagged `RiftResponse {data}|{error}`, exit 0/1, RIFT_CLI_PRETTY, `rift-protocol` + `rift-client` crates, events `{"type":...}`, `subscribe cli --event --command` (mach.rs L18-27; transport.rs L6-89; events.rs L41-43; rift-cli.rs L460-560). No unix socket. Ruled out for us (bootstrap + Mach code in Node).
- [H] OmniWM (main@a97d9e0, tools 6.4, macOS 26): targets `OmniWMIPC` (no deps), `OmniWMCtl` executable → product `omniwmctl` deps [OmniWMIPC], IPC server in `OmniWM` library target wrapped by `OmniWMApp` executable (Package.swift L10-89; Sources/OmniWM/IPC/{IPCServer,IPCConnection,IPC*Router}.swift). Wire: NDJSON, 0x0A, UTF-8, `[.sortedKeys]` compact, max line 64 KiB, `OmniWMIPCProtocol.version = 11`; request `{version,id,kind,authorizationToken,payload}`; response `{version,id,kind,ok,status(success|executed|ignored|error|subscribed),code,result}`; malformed → kind "error"/code "invalid_request"; event `{version,id,kind:"event",channel,ok,status,code,result}` (IPCWire.swift L7-37; IPCConnection.swift L12; IPCModels.swift L6-8, L65-86, L1853-1867, L2779-2834; docs/IPC-CLI.md L179-187, L792-937). Socket `~/Library/Caches/com.barut.OmniWM/ipc.sock`, env `OMNIWM_SOCKET`, docs recommend `$TMPDIR/omniwm/ipc.sock` w/ 0700 parent, avoid /tmp; dir 0o700, secret 0o600, `chmod(path,0o600)` before listen(SOMAXCONN), FD_CLOEXEC + SO_NOSIGPIPE, `getpeereid == geteuid()`, stale probe: connect ok→EADDRINUSE, ECONNREFUSED/ENOENT→unlink+rebind, other errno rethrown; non-socket file at path → EEXIST; IPC disabled by default; "trust boundary is the local macOS user account" (IPCSocketPath.swift L7-26; IPCServer.swift L187-355; IPC-CLI.md L156-203). CLI: `omniwmctl <cmd> [--format json|table|tsv|text] [--json]`; exit 0 ok / 1 server rejected / 2 transport / 3 args / 4 internal; queries+subscribe default json, commands text; CLI-local `{ok:false,source:"cli",status,code,message,exitCode}`; `subscribe <channels|--all> [--no-send-initial]` (handshake response pretty-printed, then NDJSON events); `watch --exec` one child per event, line on stdin, OMNIWM_EVENT_CHANNEL/KIND/ID env; channels are coalesced state streams ("Slow consumers may only observe the newest buffered update") (IPC-CLI.md L207-249, L666-763, L940-993). Ships CLI at `OmniWM.app/Contents/MacOS/omniwmctl`; sign helper → main (entitlements) → bundle → notarize; "Install CLI" symlinks into first $HOME-prefixed PATH dir, else ~/.local/bin, ~/bin; detects Homebrew links (package-app.sh L25-86; AppCLIManager.swift L50-149).
- [H] Paneru (main@d667379): hard-coded `/tmp/paneru.socket`, no chmod, u32 LE length + NUL argv, `query state|virtual-workspaces|active --json` (state has "version":1,"timestamp"), `subscribe --json` NDJSON coalesced per tick, consumers re-`query state` for full refresh (reader.rs L23-141; QUERY_AND_SUBSCRIBE_FORMAT.md L3-185).

**Raycast runtime facts**
- [H] Raycast AeroSpace extension probes `/opt/homebrew/bin`, `/usr/local/bin`, `/run/current-system/sw/bin`, `~/.nix-profile/bin` + pref `aerospaceBin`, `execFile` 15 s timeout, maps ECONNREFUSED/"can't connect" → "Is AeroSpace.app running?" (aerospace.ts L10-97; package.json L92-100). Raycast yabai extension prepends `env USER=${userInfo().username}` (scripts.ts L7, L23).
- [H] Live probe: 'Raycast Helper (Extensions)' env (RAYCAST_VERSION=1.104.24) = FAVICON_PROVIDER, HOME, LC_ALL, NODE_ENV, NODE_PATH, RAYCAST_BUNDLE_ID, RAYCAST_VERSION, TMPDIR — NO USER, PATH, LOGNAME, SHELL. ⇒ CLI must be found by absolute path; socket path must not depend on $USER; $TMPDIR is present.
- [H] Node `net.connect({path})` supports unix sockets; path limit `sizeof(sun_path)` = 104 on macOS (103 usable) (nodejs.org/api/net.html; sys/un.h L79).

**Kernel / platform**
- [H] XNU `unp_connect` does `vnode_authorize(vp, NULL, KAUTH_VNODE_WRITE_DATA, ctx)` → connect() requires write permission on the socket file; bind creates it 0755 under umask 022 (uipc_usrreq.c L1216, L1345). `getpeereid(3)` "reliable"; LOCAL_PEERCRED 0x001, LOCAL_PEERPID 0x002, LOCAL_PEEREPID, LOCAL_PEERUUID, LOCAL_PEEREUUID, LOCAL_PEERTOKEN 0x006 (sys/un.h L88-93).
- [H] `confstr(_CS_DARWIN_USER_TEMP_DIR)` (65537; shell `getconf DARWIN_USER_TEMP_DIR`) → `/var/folders/9c/…/T/`, drwx------, independent of TMPDIR/USER env (probe with `env -u TMPDIR -u USER`). Documented contract: 0700 + purge of regular files not accessed in 3 days (man confstr); reboot cleaning is dirhelper behaviour (`-machineBoot`, LaunchDaemon com.apple.bsd.dirhelper.plist; 0/2314 entries predate last boot) — "not considered API"; periodic pass only unlinks S_ISREG (dirhelper.c L211) so a live socket survives. Path lengths: `<T>/me.askalice.SpacialShell/ipc.sock` = 82 B; `~/Library/Application Support/SpacialShell/ipc.sock` = 62 B.
- [H] sysexits.h: EX_USAGE 64, EX_UNAVAILABLE 69, EX_SOFTWARE 70, EX_PROTOCOL 76, EX_NOPERM 77 (L100-113).
- [M] Network.framework NWConnection/NWListener/NetworkListener (26 SDK) expose no fd or peer-credential API (grep of headers + swiftinterface); `NWEndpoint.unix(path:)` exists (L392). ⇒ per-connection getpeereid and chmod-before-listen require BSD sockets; a 0700 parent dir + chmod-after-`.ready` (small race) is possible with NWListener.

**SpacialShell today (cf94bc1)**
- [H] Package.swift tools 6.0, .macOS(.v14), targets PrivateApi/SpacialShellKit/SpacialShellPlatform/executable SpacialShell + 3 test targets; no IPC. Paths.swift L7-11: `~/.config/spacial-shell/config.toml`, `~/Library/Application Support/SpacialShell/state.json`, bundleID `me.askalice.SpacialShell`. bundle.sh L9-11 copies only SpacialShell binary; ad-hoc `codesign --force --sign - --identifier me.askalice.SpacialShell`. WorldStore.swift L3 `public actor WorldStore`, L8 `private let onChange: @Sendable (World) -> Void` injected at init (L32), L60 `public func run(_ command: Command) async`. Command.swift L7-19: focusWorkspace, focusWorkspaceIndex, focusWindow, moveWindow, moveWindowToWorkspace, cycleLayout, focusScreen, moveWindowToScreen, toggleFloat, closeFocusedWindow, toggleShellUI. Model.swift: WindowRef{id:UInt32,pid:Int32}, Workspace{id:UUID,name,symbol,layout,windows,anchor}, World{screens,screenOrder,focus}. ⇒ IPC event fan-out must be wired at WorldStore construction (or via the app's existing onChange closure); no rename command exists yet.

### 2b. Verify empirically
1. connect() to a 0600 socket in a 0700 dir from another uid fails (EACCES) on 26.5; same-uid succeeds; `getpeereid` returns expected euid for a Node client.
2. Node `net.connect({path})` from Raycast Helper (Extensions) reaches `<DARWIN_USER_TEMP_DIR>/me.askalice.SpacialShell/ipc.sock` — confirm sandbox/TCC doesn't block /var/folders access from the helper; fallback path under ~/Library/Application Support if it does.
3. Stale-socket recovery after SIGKILL of the daemon (ECONNREFUSED → unlink+rebind) and duplicate-instance detection (connect succeeds → refuse to start).
4. Bundle signing: nested `Contents/MacOS/spacialctl` with ad-hoc sign order helper→app passes `codesign -v --deep --strict`; Gatekeeper/AX trust unaffected by adding the helper (AX permission is per bundle id / code signature — re-grant may be needed once).
5. Event fan-out under load: coalescing keeps WorldStore.run latency flat with a stalled subscriber (write returns EAGAIN/EPIPE → drop oldest, keep newest); SO_NOSIGPIPE prevents SIGPIPE.
6. Path length of `confstr` dir on other machines stays < 104 with our suffix (82 here; /var/folders/xx/<30-char>/T/ is fixed-form, so safe, but assert at startup).
7. `swift build --arch arm64 --arch x86_64 --product spacialctl` universal binary size/time; whether SpacialShellIPC stays Foundation-only (no AppKit import) so spacialctl links in ms.

### 2c. Design recommendation (concrete)

**Package layout**
- `SpacialShellIPC` (library, Foundation only): protocol version const, `IPCRequest/IPCResponse/IPCEvent` Codable, NDJSON codec, socket-path resolver, error-code enum.
- `SpacialCtl` executableTarget → product `.executable(name:"spacialctl", targets:["SpacialCtl"])`, deps [SpacialShellIPC] only (no Kit/Platform/AX/TCC). Optionally swift-argument-parser.
- App target: `IPCServer` (BSD socket + DispatchSource accept; one actor per connection) → `WorldStore.run(_:)`; event fan-out from the onChange closure passed at WorldStore init.
- Tests: codec round-trip; integration boots IPCServer with `SPACIALSHELL_SOCKET=<tmp>` + FakeBackend, drives with spacialctl and raw NDJSON client; asserts 0700/0600 perms, stale recovery, protocol_mismatch, coalescing.

**Socket**
- Path: `confstr(_CS_DARWIN_USER_TEMP_DIR)/me.askalice.SpacialShell/ipc.sock` (per-user 0700, env-independent, 82 B). Fallback/alt: `~/Library/Application Support/SpacialShell/ipc.sock` (dir already exists). Env override `SPACIALSHELL_SOCKET`. Never `/tmp/<name>-$USER` or `/tmp/<name>`.
- Server: mkdir 0700 → probe existing (connect ok → another instance, abort; ECONNREFUSED/ENOENT → unlink) → socket(AF_UNIX,SOCK_STREAM) → bind → `chmod 0600` → listen(SOMAXCONN) → FD_CLOEXEC; per accept: FD_CLOEXEC, SO_NOSIGPIPE, `getpeereid(fd).euid == geteuid()` else close. No secret token (adds nothing over same-uid; complicates Raycast direct-connect). Not NWListener.

**Framing / protocol**
- NDJSON: one compact JSON object per line (0x0A), UTF-8, sortedKeys, ≤64 KiB/line; malformed line → error response, keep connection; multiple requests per connection; responses carry request id (pipelining OK).
- Request `{"v":1,"id":"…","method":"workspace.list","params":{…}}`
- Response `{"v":1,"id":"…","ok":true,"result":{…}}` | `{"v":1,"id":"…","ok":false,"error":{"code":"not_found","message":"…","details":{…}}}`
- Error codes (stable snake_case): invalid_request, protocol_mismatch, unknown_method, invalid_arguments, not_found, stale_window_id, disabled, internal_error. protocol_mismatch error carries serverProtocolVersion + appVersion.
- Events (after `subscribe`): `{"v":1,"kind":"event","channel":"world|focus|workspace","seq":N,"payload":{…}}` — coalesced snapshot streams (newest-only for slow consumers), initial snapshot unless `sendInitial:false`. IDs: workspace UUID, WindowRef{id,pid}, display UUID.
- Methods (M2): `ping`, `version` (app+protocol+pid), `world.get`, `screen.list`, `workspace.list`, `window.list`, `workspace.focus {screen?, index|id|name}`, `workspace.rename {id,name}` (new Command needed), `window.focus {window}`, `window.move_to_workspace {window, workspace}`, `layout.cycle {workspace?}` / `layout.set {workspace?, layout}`, `ui.zen {on|off|toggle}` (maps to toggleShellUI), `subscribe {channels:[…], sendInitial}`.

**CLI (`spacialctl`)**
- `spacialctl <noun> <verb> [args] [--json] [--socket PATH]`; list/query → aligned table, `--json` compact array; mutations print nothing on success; `subscribe [channels|--all] [--no-send-initial]` streams NDJSON with fflush per line; later `watch --exec`. stderr: one human line; `--json` CLI-local envelope `{ok:false,source:"cli",code,message,exitCode}`. Exit: 0 ok, 1 server rejected, 2 cannot connect ("Is SpacialShell running?"), 3 usage, 4 internal (OmniWM scheme; sysexits 64/69/70/76 acceptable). `--help`/completions never touch socket. Warn (AeroSpace-style) when app version ≠ CLI version.

**Shipping**
- `swift build -c release --product spacialctl` (add `--arch arm64 --arch x86_64` for distribution); bundle.sh copies to `SpacialShell.app/Contents/MacOS/spacialctl`; sign helper first, then main binary, then bundle (`codesign --force --sign - Contents/MacOS/spacialctl` then app). PATH exposure: `spacialctl install` / menu item symlinking into `~/.local/bin` (or first $HOME-prefixed PATH dir); Homebrew cask `binary` stanza later.

**Raycast extension**
- Structure: `extensions/spacialshell/` with commands: `list-workspaces` (List, per-screen sections, actions Focus/Rename/Cycle Layout), `list-windows` (List, actions Focus/Move to workspace…), `switch-workspace` (no-view, arg index|name), `cycle-layout` (no-view), `toggle-zen` (no-view), optional `menubar` (MenuBarExtra fed by `subscribe world`).
- Transport: primary = direct `net.connect({path: socketPath})` + `readline` NDJSON (no process spawn, ms latency, live subscribe); socketPath resolved as `process.env.TMPDIR ? path.join(TMPDIR, "me.askalice.SpacialShell/ipc.sock") : ~/Library/Application Support/SpacialShell/ipc.sock` (TMPDIR IS set in Raycast helper; USER/PATH are not) + preference override. Fallback = `execFile` of spacialctl by absolute candidates `["/Applications/SpacialShell.app/Contents/MacOS/spacialctl","/opt/homebrew/bin/spacialctl","/usr/local/bin/spacialctl"]` + preference; never rely on PATH; map exit 2 / ECONNREFUSED / ENOENT → "Is SpacialShell running?" toast.

Local evidence copies: `/private/tmp/claude-501/-Users-alice-mac-material-shell/aa7fe75f-1297-4120-92ea-463238dbfe97/scratchpad/{jb/,sb/,omni/,rift/,OmniWM/,aero_NSPanelHud.swift,aero_goodies.adoc,aero_tree.json,yabai_CHANGELOG.md,yabai.asciidoc,omni_arch.md,lv.swift}`.",
    "tracks": [
      "overlay-panels",
      "ipc-cli"
    ]
  },
  "workflowProgress": [
    {
      "type": "workflow_phase",
      "index": 1,
      "title": "Research"
    },
    {
      "type": "workflow_phase",
      "index": 2,
      "title": "Verify"
    },
    {
      "type": "workflow_phase",
      "index": 3,
      "title": "Synthesize"
    },
    {
      "type": "workflow_agent",
      "index": 1,
      "label": "research:overlay-panels",
      "phaseIndex": 1,
      "phaseTitle": "Research",
      "agentId": "ae12abfa6a075996b",
      "model": "claude-fable-5",
      "state": "done",
      "startedAt": 1787113922949,
      "queuedAt": 1787113916801,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "Recommended concrete recipe distilled from the evidence (al…",
      "promptPreview": "Context: SpacialShell (repo /Users/alice/code/spacial-shell, Swift 6 SwiftPM, macOS 14+ min, dev machine macOS 26.5) is a headless spatial window manager (per-screen workspace stacks, tiled windows, others parked as 1pt slivers) driven by an AX backend + CGEventTap hotkeys. M2 adds: (1) always-visible overlay panels per display — a left workspace rail and a top window-tab bar with layout switcher …",
      "lastProgressAt": 1787115750813,
      "tokens": 259791,
      "toolCalls": 149,
      "durationMs": 1827391,
      "resultPreview": "{"claims":[{"claim":"NSPanel is the right AppKit class: it adds isFloatingPanel, becomesKeyOnlyIfNeeded, worksWhenModal on top of NSWindow; the non-activating behaviour comes from styleMask .nonactivatingPanel (1<<7), which the header says 'Specifies that a panel that does not activate the owning application. Only applicable for NSPanel (or a subclass thereof)'. .hudWindow (1<<13) and .utilityWind…"
    },
    {
      "type": "workflow_agent",
      "index": 2,
      "label": "research:raycast-ext",
      "phaseIndex": 1,
      "phaseTitle": "Research",
      "agentId": "a8b9cc8cead50e6fd",
      "model": "claude-fable-5",
      "state": "error",
      "startedAt": 1787113923790,
      "queuedAt": 1787113916801,
      "attempt": 1,
      "lastToolName": "Bash",
      "lastToolSummary": "cd /private/tmp/claude-501/-Users-alice-mac-material-shell/…",
      "promptPreview": "Context: SpacialShell (repo /Users/alice/code/spacial-shell, Swift 6 SwiftPM, macOS 14+ min, dev machine macOS 26.5) is a headless spatial window manager (per-screen workspace stacks, tiled windows, others parked as 1pt slivers) driven by an AX backend + CGEventTap hotkeys. M2 adds: (1) always-visible overlay panels per display — a left workspace rail and a top window-tab bar with layout switcher …",
      "lastProgressAt": 1787114716980,
      "error": "API Error: Server error mid-response. The response above may be incomplete.",
      "tokens": 182416,
      "toolCalls": 76,
      "durationMs": 790405
    },
    {
      "type": "workflow_agent",
      "index": 3,
      "label": "research:ipc-cli",
      "phaseIndex": 1,
      "phaseTitle": "Research",
      "agentId": "ab1dc82bbc5b77413",
      "model": "claude-fable-5",
      "state": "done",
      "startedAt": 1787113923787,
      "queuedAt": 1787113916801,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "RECOMMENDED DESIGN (derived from the survey; every choice m…",
      "promptPreview": "Context: SpacialShell (repo /Users/alice/code/spacial-shell, Swift 6 SwiftPM, macOS 14+ min, dev machine macOS 26.5) is a headless spatial window manager (per-screen workspace stacks, tiled windows, others parked as 1pt slivers) driven by an AX backend + CGEventTap hotkeys. M2 adds: (1) always-visible overlay panels per display — a left workspace rail and a top window-tab bar with layout switcher …",
      "lastProgressAt": 1787114708271,
      "tokens": 181528,
      "toolCalls": 76,
      "durationMs": 781696,
      "resultPreview": "{"claims":[{"claim":"AeroSpace's server listens on a Unix-domain socket via Network.framework: NWListener with NWParameters.tcp and requiredLocalEndpoint = .unix(path: socketPath); it removes any existing socket file first and does NOT chmod the socket.","evidence":"https://raw.githubusercontent.com/nikitabobko/AeroSpace/main/Sources/AppBundle/server.swift lines 5-18: `try? FileManager.default.rem…"
    },
    {
      "type": "workflow_agent",
      "index": 4,
      "label": "verify:ipc-cli",
      "phaseIndex": 2,
      "phaseTitle": "Verify",
      "agentId": "a1646929e58c1a563",
      "model": "claude-fable-5",
      "state": "done",
      "startedAt": 1787114708291,
      "queuedAt": 1787114708273,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "promptPreview": "Context: SpacialShell (repo /Users/alice/code/spacial-shell, Swift 6 SwiftPM, macOS 14+ min, dev machine macOS 26.5) is a headless spatial window manager (per-screen workspace stacks, tiled windows, others parked as 1pt slivers) driven by an AX backend + CGEventTap hotkeys. M2 adds: (1) always-visible overlay panels per display — a left workspace rail and a top window-tab bar with layout switcher …",
      "lastProgressAt": 1787115734616,
      "tokens": 202304,
      "toolCalls": 101,
      "durationMs": 1026325,
      "resultPreview": "{"verdicts":[{"claim":"AeroSpace's server listens on a Unix-domain socket via Network.framework: NWListener with NWParameters.tcp and requiredLocalEndpoint = .unix(path: socketPath); it removes any existing socket file first and does NOT chmod the socket.","refuted":false,"reason":"Verified against AeroSpace main @ c548c7f8 (2026-08-10) Sources/AppBundle/server.swift L5-18: `try? FileManager.defau…"
    },
    {
      "type": "workflow_agent",
      "index": 5,
      "label": "verify:overlay-panels",
      "phaseIndex": 2,
      "phaseTitle": "Verify",
      "agentId": "a9de1a73fb4f295a7",
      "model": "claude-fable-5",
      "state": "done",
      "startedAt": 1787115750816,
      "queuedAt": 1787115750814,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "promptPreview": "Context: SpacialShell (repo /Users/alice/code/spacial-shell, Swift 6 SwiftPM, macOS 14+ min, dev machine macOS 26.5) is a headless spatial window manager (per-screen workspace stacks, tiled windows, others parked as 1pt slivers) driven by an AX backend + CGEventTap hotkeys. M2 adds: (1) always-visible overlay panels per display — a left workspace rail and a top window-tab bar with layout switcher …",
      "lastProgressAt": 1787116864410,
      "tokens": 193857,
      "toolCalls": 86,
      "durationMs": 1113592,
      "resultPreview": "{"verdicts":[{"claim":"NSPanel adds isFloatingPanel/becomesKeyOnlyIfNeeded/worksWhenModal; .nonactivatingPanel (1<<7), .hudWindow (1<<13), .utilityWindow (1<<4) are NSPanel-only per header","refuted":false,"reason":"Verified in the 26.x SDK on this Mac: MacOSX.sdk/.../AppKit.framework/Versions/C/Headers/NSPanel.h lines 13-19 declare exactly the three properties (`floatingPanel`, `becomesKeyOnlyIfN…"
    },
    {
      "type": "workflow_agent",
      "index": 6,
      "label": "synthesize",
      "phaseIndex": 3,
      "phaseTitle": "Synthesize",
      "agentId": "a4344ec69713d5b2f",
      "model": "claude-fable-5",
      "state": "done",
      "startedAt": 1787116864415,
      "queuedAt": 1787116864413,
      "attempt": 1,
      "promptPreview": "Context: SpacialShell (repo /Users/alice/code/spacial-shell, Swift 6 SwiftPM, macOS 14+ min, dev machine macOS 26.5) is a headless spatial window manager (per-screen workspace stacks, tiled windows, others parked as 1pt slivers) driven by an AX backend + CGEventTap hotkeys. M2 adds: (1) always-visible overlay panels per display — a left workspace rail and a top window-tab bar with layout switcher …",
      "lastProgressAt": 1787117060621,
      "tokens": 107870,
      "toolCalls": 0,
      "durationMs": 196206,
      "resultPreview": "# SpacialShell M2 — spec-ready facts (research merged with verification)

Legend: [H]=high, [M]=medium, [L]=low confidence. "Verified" = independently re-checked in the verdict pass (SDK headers on this Mac, raw upstream sources at pinned commits, or live probe on macOS 26.5).

---

## TOPIC 1: OVERLAY PANELS (workspace rail + window-tab bar)

### 1a. Settled facts

**Window class / style mask**
-…"
    }
  ],
  "totalTokens": 1127766,
  "totalToolCalls": 488
