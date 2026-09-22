# Attention signals: can the rail show "wants attention" and "has notifications"?

Date: 2026-09-14
Status: **research, not a design.** Nothing here is approved. It records what was measured so a
future design does not have to re-argue feasibility.
Probe and raw output: `Tools/attention-probe/` (`RESULTS.md` holds every number quoted here).
Tested on: macOS 26.5 (25F71), unsandboxed, Accessibility granted (`AXIsProcessTrusted() == true`).

## Questions

1. **Urgency.** When another app calls `NSApplication.requestUserAttention(_:)` (Dock bounce), can
   SpacialShell observe it, and attribute it to the right app?
2. **Badge.** Can SpacialShell read the per-app Dock badge (`NSDockTile.badgeLabel`) so the rail can
   show "this app has notifications"?

## Verdicts

| | verdict | mechanism | public? |
|---|---|---|---|
| Q1 urgency | **works, heuristically** | poll `AXPosition` of the app's `AXDockItem` in the Dock process; y lifts ~52 pt once per ~2 s while a critical request is pending | AX API is public; the Dock's AX tree and its animation are undocumented |
| Q1 (exact) | works, **private** | LaunchServices key `LSWantsAttention` + `kLSNotifyApplicationWantsAttentionChanged` (seen via `lsappinfo`) | no — SPI, off the table for App Store |
| Q1 via public notifications | **doesn't** | nothing in `NSWorkspace` notifications or `NSRunningApplication` | — |
| Q2 badge | **works** | read `AXStatusLabel` on the app's `AXDockItem`; string value is the badge text, `kAXErrorNoValue` when none | AX API is public; the attribute name is not in the SDK |

## Q1 — urgency

### What Apple documents

- `requestUserAttention(_:)`: "Starts a user attention request … Activating the app cancels the user
  attention request … Sending `requestUserAttention(_:)` to an app that is already active has no
  effect." — https://developer.apple.com/documentation/appkit/nsapplication/requestuserattention(_:)
- `.criticalRequest`: "The dock icon will bounce until either the app becomes active or the request
  is canceled." — https://developer.apple.com/documentation/appkit/nsapplication/requestuserattentiontype/criticalrequest
- `.informationalRequest`: "The dock icon will bounce for one second. The request, though, remains
  active until either the app becomes active or the request is canceled." —
  https://developer.apple.com/documentation/appkit/nsapplication/requestuserattentiontype/informationalrequest

The request is a Dock/LaunchServices concern. No public API reports another app's pending request:
`NSRunningApplication` exposes no attention property
(https://developer.apple.com/documentation/appkit/nsrunningapplication), and the 21 notification
names declared in `NSWorkspace.h` (SDK 26.5) include none for attention or badges
(https://developer.apple.com/documentation/appkit/nsworkspace).

### What was measured

A background test app (`isActive=false`) issued `.criticalRequest`. The probe watched four channels:

1. **NSWorkspace notifications** (nil-name and named observers): delivered the app's termination,
   delivered nothing at the request. *Doesn't work.*
2. **Distributed notifications, nil name**: received nothing, not even the probe's own control post
   that the named observer received. The firehose is closed to ordinary processes, so this channel
   cannot be used to discover anything. *Doesn't work.*
3. **AX notifications on Dock elements**: every item accepts only `AXCreated` and
   `AXUIElementDestroyed`; `AXValueChanged`, `AXTitleChanged`, `AXMoved`, `AXLayoutChanged` and the
   rest return `kAXErrorNotificationUnsupported` (-25207,
   https://developer.apple.com/documentation/applicationservices/axerror/notificationunsupported).
   No push signal for a bounce.
4. **AX attribute polling (50 ms)**: the only attribute that changed was the item's geometry.
   `AXPosition.y` went 1440 → min 1388 → 1440, **6 lifts at a ~2.0 s cadence** from the request until
   the app exited 11 s later. Nothing else on the item (`AXStatusLabel`, `AXSelected`,
   `AXIsApplicationRunning`) changed. *Works.*

Attribution is exact: the item carries `AXURL` (the app bundle URL), which matched the running
app's `NSRunningApplication.bundleURL`, giving bundle id and pid.

For reference, `lsappinfo listen` showed LaunchServices flipping `LSWantsAttention` to true at the
request and back to false when the app died. That is the precise state SpacialShell would want, but
it is reachable only through private LaunchServices SPI, which the window-identity ruling
(2026-09-12) already put off-limits.

### Caveats

- **Undocumented surface.** `kAXDockItemRole` and `kAXApplicationDockItemSubrole` are public constants
  in `HIServices/AXRoleConstants.h`; that the Dock's AX position follows the bounce animation is
  observed behaviour, not a contract. It can break in any macOS release.
- **Heuristic, not state.** A lift is a *symptom*. It is indistinguishable from a launch bounce
  (filter on `NSRunningApplication.isFinishedLaunching`), and "stopped bouncing" does not mean the
  request ended. An informational request (one bounce, request still pending) would register once
  and then look idle. Not measured.
- **Polling cost.** A bounce is ~1 s of motion every ~2 s, so sampling must be ≤ ~250 ms per
  running-app item to catch it. The cost was not measured.
- **Not measured:** Dock auto-hide, Dock on another edge, Reduce Motion, and behaviour without the
  Accessibility grant.

## Q2 — badge

### What Apple documents

`NSDockTile.badgeLabel`: "The string to be displayed in the tile's badging area. The appearance of the
badge area is system defined." —
https://developer.apple.com/documentation/appkit/nsdocktile/badgelabel.
There is no documented way to read another app's badge.

### What was measured

- Every `AXApplicationDockItem` exposes `AXStatusLabel`. With no badge it returns
  `kAXErrorNoValue` (-25212,
  https://developer.apple.com/documentation/applicationservices/axerror/novalue).
- Test app set `badgeLabel = "12"`: `AXStatusLabel` read `12` within one ~0.7 s sample, and went back
  to no value within one sample after it was set to `nil`. Repeated with `"7"` under 50 ms polling:
  set and clear both observed.
- Live desktop: System Settings (badge drawn by its `NSDockTilePlugIn`) read `AXStatusLabel = 1`.
  LaunchServices' private `StatusLabel` key showed NULL for it. So AX reports the Dock's rendered
  badge, which is what the user sees and what the rail should mirror. LaunchServices only sees
  `NSDockTile` badges set in-process.
- `AXValueChanged` is unsupported on items (see Q1), so badges must be polled. Items appear and
  disappear with `AXCreated` / `AXUIElementDestroyed`, which do register.
- `AXStatusLabel` does not appear in any AppKit or HIServices SDK header. It is observed, not
  documented.

### Caveats

- **Only badges.** Apps that post `UNUserNotificationCenter` banners without a Dock badge produce
  nothing here. Notification Center contents are not readable.
- **Only Dock-present apps.** An app with no Dock tile (accessory or agent apps) has no item.
- **Real messaging apps were not measured.** Mail, Messages and Slack were not running and were not
  launched. The mechanism is app-agnostic (the Dock renders every badge), but that is inference.
- `AXStatusLabel`'s value is whatever the app wrote (`"12"`, `"•"`, `"99+"`). The rail should treat
  it as opaque text or as "present / absent".

## If this becomes a design

Layering that fits `CLAUDE.md`: a platform-side Dock watcher (AppKit/AX, outside Kit) turns polled
Dock state into plain data, `[bundleID: (badge: String?, bouncing: Bool)]`, fed into the store as
Commands. The rail renders from `World` like everything else. The open questions a design must
settle: poll interval versus CPU, whether a heuristic "bouncing" flag is honest enough to show, and
behaviour when the Dock is hidden.
