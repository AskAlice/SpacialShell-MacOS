# Attention signals — measured results

Throwaway probe. Not shipped, not imported by any target, not in `Package.swift`.
Measured 2026-09-14 on **macOS 26.5 (25F71)**, Apple silicon, unsandboxed, from a shell whose
responsible process holds the Accessibility grant (`AXIsProcessTrusted=true`). Untrusted behaviour
was **not** measured.

```
./build.sh                                   # ./probe + ./AttentionBouncer.app (ad-hoc signed)
./probe dump                                 # every Dock AX item, all attributes
./probe watch 20                             # AXObserver + 50 ms attribute diff + NSWorkspace/distributed firehoses
open -g -n AttentionBouncer.app --args 5 critical "" 8   # background, critical request, no badge
open -g -n AttentionBouncer.app --args 1 none 12 6       # background, badge "12" only
lsappinfo listen +all forever                # LaunchServices notification stream (reference only)
```

`AttentionBouncer` has no windows and shows no alerts; `open -g` keeps it in the background
(it logs `isActive=false` before each request).

## 1. Dock AX structure (`probe dump`)

Dock pid 2122 → one `AXList` → 49 items. Subroles seen:

```
  43     AXSubrole = AXApplicationDockItem
   1     AXSubrole = AXFolderDockItem
   2     AXSubrole = AXMinimizedWindowDockItem
   2     AXSubrole = AXSeparatorDockItem
   1     AXSubrole = AXTrashDockItem
```

Typical application item (no badge):

```
[150.932] ITEM Finder owner=com.apple.finder pid=2128
    AXFrame = <AXValue 0x92ec581c0> {value = x:2584.541016 y:1440.000122 w:30.541016 h:42.541016 type = kAXValueCGRectType}
    AXIsApplicationRunning = 1
    AXPosition = pt(2584.541015625,1440.0001220703125)
    AXProgressValue = err(-25212)
    AXRole = AXDockItem
    AXRoleDescription = application dock item
    AXSelected = 0
    AXShownMenuUIElement = err(-25212)
    AXSize = size(30.541015625,42.541015625)
    AXStatusLabel = err(-25212)
    AXSubrole = AXApplicationDockItem
    AXTitle = Finder
    AXURL = file:///System/Library/CoreServices/Finder.app/
    actions = ["AXPress", "AXShowMenu", "AXShowExpose"]
```

The only item with a value in `AXStatusLabel` on the live desktop was System Settings (its Dock
badge, drawn by its `NSDockTilePlugIn`):

```
[150.957] ITEM System Settings owner=com.apple.systempreferences pid=2091
    AXStatusLabel = 1
```

`-25212` is `kAXErrorNoValue`. Mail, Messages and Slack were not running and were not launched.

## 2. AXObserver registration on Dock elements

Registered on the Dock app element, the list, and every item (52 elements):

```
[266.517] AXObserverAddNotification result codes (code:count) per notification: ["AXFocusedUIElementChanged": [0: 2, -25207: 50], "AXSelectedChildrenChanged": [0: 2, -25207: 50], "AXCreated": [0: 52], "AXTitleChanged": [-25207: 52], "AXLayoutChanged": [-25207: 52], "AXValueChanged": [-25207: 52], "AXElementBusyChanged": [-25207: 52], "AXUIElementDestroyed": [0: 52], "AXMoved": [-25207: 52], "AXResized": [-25207: 52], "AXAnnouncementRequested": [-25207: 52]]
```

`0` = success, `-25207` = `kAXErrorNotificationUnsupported`. Only `AXCreated` and `AXUIElementDestroyed`
register on items (the two `0`s for focus/selection are the app element and the list). So neither
badge nor bounce can be *pushed*; both must be polled. Across all runs the only AX notifications delivered were:

```
watch-bounce.txt:[282.772] AXNOTE AXUIElementDestroyed on ? role=nil status=nil
watch-bounce.txt:[282.772] AXNOTE AXUIElementDestroyed on ? role=nil status=nil
watch-bounce.txt:[282.772] AXNOTE AXUIElementDestroyed on ? role=nil status=nil
watch-critical.txt:[153.954] AXNOTE AXCreated on AttentionBouncer role=AXDockItem status=nil
watch-critical.txt:[153.955] AXNOTE AXCreated on AttentionBouncer role=AXDockItem status=nil
watch-critical.txt:[172.514] AXNOTE AXUIElementDestroyed on ? role=nil status=nil
watch-critical.txt:[172.514] AXNOTE AXUIElementDestroyed on ? role=nil status=nil
```

## 3. Badge (Q2) — `AXStatusLabel`

Run A (critical request + badge "7", probe polling at 50 ms):

```
bouncer: isActive=false pid=92930
bouncer: badgeLabel=7
bouncer: requestUserAttention(.criticalRequest) -> 0
bouncer: badge cleared
[153.925] NEWITEM AttentionBouncer owner=me.askalice.spacialshell.attention-bouncer pid=92930 ["AXURL": "file:///Users/alice/code/spacial-shell/.claude/worktree
[159.266] DIFF AttentionBouncer owner=me.askalice.spacialshell.attention-bouncer pid=92930 AXStatusLabel: err(-25212) -> 7
[169.765] DIFF AttentionBouncer owner=me.askalice.spacialshell.attention-bouncer pid=92930 AXStatusLabel: 7 -> err(-25212)
```

Run C (badge "12" only), AX read side by side with LaunchServices' `StatusLabel`, ~0.7 s samples:

```
bouncer: isActive=false pid=46908
bouncer: badgeLabel=12
bouncer: badge cleared
bouncer: exit
1789399339.45 lsappinfo["StatusLabel"=[ NULL ] ] ax[    AXStatusLabel = err(-25212)]
1789399340.21 lsappinfo["StatusLabel"=[ NULL ] ] ax[    AXStatusLabel = err(-25212)]
1789399340.97 lsappinfo["StatusLabel"={ "label"="12" }] ax[    AXStatusLabel = 12]
1789399341.66 lsappinfo["StatusLabel"={ "label"="12" }] ax[    AXStatusLabel = 12]
1789399342.33 lsappinfo["StatusLabel"={ "label"="12" }] ax[    AXStatusLabel = 12]
1789399343.06 lsappinfo["StatusLabel"={ "label"="12" }] ax[    AXStatusLabel = 12]
1789399343.74 lsappinfo["StatusLabel"={ "label"="12" }] ax[    AXStatusLabel = 12]
1789399344.40 lsappinfo["StatusLabel"={ "label"="12" }] ax[    AXStatusLabel = 12]
1789399345.12 lsappinfo["StatusLabel"={ "label"="12" }] ax[    AXStatusLabel = 12]
1789399345.80 lsappinfo["StatusLabel"={ "label"="12" }] ax[    AXStatusLabel = 12]
1789399346.48 lsappinfo["StatusLabel"={ "label"="12" }] ax[    AXStatusLabel = 12]
1789399347.18 lsappinfo["StatusLabel"={ "label"=kCFNULL }] ax[    AXStatusLabel = err(-25212)]
1789399347.85 lsappinfo["StatusLabel"={ "label"=kCFNULL }] ax[    AXStatusLabel = err(-25212)]
1789399348.51 lsappinfo["StatusLabel"={ "label"=kCFNULL }] ax[    AXStatusLabel = err(-25212)]
1789399349.21 lsappinfo[] ax[    AXStatusLabel = err(-25212)]
1789399349.89 lsappinfo[] ax[]
1789399350.58 lsappinfo[] ax[]
1789399351.34 lsappinfo[] ax[]
```

For System Settings (badge via dock tile plug-in) the two disagree: AX shows `1`, LaunchServices shows NULL:

```
"StatusLabel"=[ NULL ] 
AXStatusLabel = 1          (probe dump, same session)
```

## 4. Attention request (Q1)

Run B — critical request, no badge. Test app output:

```
bouncer: isActive=false pid=33081
bouncer: requestUserAttention(.criticalRequest) -> 0
bouncer: exit
```

### 4a. Public notification channels: nothing

The probe observed `NSWorkspace.shared.notificationCenter` with `name: nil` **and** with explicit
names, plus `DistributedNotificationCenter` with `name: nil` and one explicit name, and posted a
control distributed notification to itself. Complete list of those lines for run B:

```
[267.582] posted distributed control
[267.583] DISTRIBUTED(named) control received
[282.223] NSWORKSPACE NSWorkspaceDidTerminateApplicationNotification <NSRunningApplication: 0x9f483fc00 (me.askalice.spacialshell.attention-bouncer - 33081) LSASN:{hi=0x0;lo=0x16ed6ec}>
[282.223] NSWORKSPACE(named) NSWorkspaceDidTerminateApplicationNotification <NSRunningApplication: 0x9f483fc00 (me.askalice.spacialshell.attention-bouncer - 33081) LSASN:{hi=0x0;lo=0x16ed6ec}>
```

- Workspace channel is live (terminate delivered on both observers) but carries nothing at the request.
- The distributed nil-name observer did not receive even the probe's own control post; the named
  observer did. The distributed firehose is closed to this process, so it proves nothing either way.
- `NSWorkspace.h` (SDK 26.5) declares no attention or badge notification — full list:

```
NSWorkspaceActiveSpaceDidChangeNotification
NSWorkspaceDidActivateApplicationNotification
NSWorkspaceDidChangeFileLabelsNotification
NSWorkspaceDidDeactivateApplicationNotification
NSWorkspaceDidHideApplicationNotification
NSWorkspaceDidLaunchApplicationNotification
NSWorkspaceDidMountNotification
NSWorkspaceDidPerformFileOperationNotification
NSWorkspaceDidRenameVolumeNotification
NSWorkspaceDidTerminateApplicationNotification
NSWorkspaceDidUnhideApplicationNotification
NSWorkspaceDidUnmountNotification
NSWorkspaceDidWakeNotification
NSWorkspaceScreensDidSleepNotification
NSWorkspaceScreensDidWakeNotification
NSWorkspaceSessionDidBecomeActiveNotification
NSWorkspaceSessionDidResignActiveNotification
NSWorkspaceWillLaunchApplicationNotification
NSWorkspaceWillPowerOffNotification
NSWorkspaceWillSleepNotification
NSWorkspaceWillUnmountNotification
```

### 4b. AX: the bouncing item's `AXPosition.y` moves

No attribute other than geometry changes. The item's y (resting 1440, top-of-Dock origin) lifts and
lands once per bounce. Summary of every `AXPosition` diff for the test app's item (request issued at
~271.5, app exited at 282.2):

```
first 266.647 1440.7830810546875
lift   271.721 1433.176025390625
land   272.761 1439.9998779296875
lift   273.719 1432.4049072265625
land   274.825 1439.9998779296875
lift   275.718 1437.53662109375
land   276.775 1439.9998779296875
lift   277.794 1407.0076904296875
land   278.772 1439.9998779296875
lift   279.715 1436.327392578125
land   280.762 1439.9998779296875
lift   281.718 1434.3453369140625
land   282.582 1442.5814208984375
bounces 6 min y 1388.0662841796875
```

Raw samples of the first bounce:

```
[271.721] pt(3884.880126953125,1439.9998779296875) -> pt(3884.880126953125,1433.176025390625)
[271.758] pt(3884.880126953125,1433.176025390625) -> pt(3884.880126953125,1420.6395263671875)
[271.817] pt(3884.880126953125,1420.6395263671875) -> pt(3884.880126953125,1401.6748046875)
[271.862] pt(3884.880126953125,1401.6748046875) -> pt(3884.880126953125,1395.24658203125)
[271.912] pt(3884.880126953125,1395.24658203125) -> pt(3884.880126953125,1389.5247802734375)
[271.965] pt(3884.880126953125,1389.5247802734375) -> pt(3884.880126953125,1388.159423828125)
[272.014] pt(3884.880126953125,1388.159423828125) -> pt(3884.880126953125,1391.462890625)
[272.061] pt(3884.880126953125,1391.462890625) -> pt(3884.880126953125,1399.4351806640625)
[272.115] pt(3884.880126953125,1399.4351806640625) -> pt(3884.880126953125,1412.076416015625)
[272.165] pt(3884.880126953125,1412.076416015625) -> pt(3884.880126953125,1429.0166015625)
[272.213] pt(3884.880126953125,1429.0166015625) -> pt(3884.880126953125,1437.817138671875)
[272.266] pt(3884.880126953125,1437.817138671875) -> pt(3884.880126953125,1424.6016845703125)
[272.310] pt(3884.880126953125,1424.6016845703125) -> pt(3884.880126953125,1416.57177734375)
[272.364] pt(3884.880126953125,1416.57177734375) -> pt(3884.880126953125,1414.033203125)
[272.410] pt(3884.880126953125,1414.033203125) -> pt(3884.880126953125,1416.9862060546875)
[272.468] pt(3884.880126953125,1416.9862060546875) -> pt(3884.880126953125,1425.4306640625)
[272.511] pt(3884.880126953125,1425.4306640625) -> pt(3884.880126953125,1434.0177001953125)
[272.557] pt(3884.880126953125,1434.0177001953125) -> pt(3884.880126953125,1433.1732177734375)
[272.624] pt(3884.880126953125,1433.1732177734375) -> pt(3884.880126953125,1427.019287109375)
[272.659] pt(3884.880126953125,1427.019287109375) -> pt(3884.880126953125,1428.197998046875)
[272.717] pt(3884.880126953125,1428.197998046875) -> pt(3884.880126953125,1435.3643798828125)
[272.761] pt(3884.880126953125,1435.3643798828125) -> pt(3884.880126953125,1439.9998779296875)
[273.719] pt(3884.880126953125,1439.9998779296875) -> pt(3884.880126953125,1432.4049072265625)
```

The first two diffs (266.6–266.7) are the Dock inserting the new item (size grows 20.7→29.9),
not a lift. No launch bounce was observed in this session.

### 4c. LaunchServices (private, reference only): exact signal

`lsappinfo listen +all` during run B, attention-related lines verbatim (truncated to 260 chars):

```
Notification: kLSNotifyApplicationWantsAttentionChanged time=+5.17248s  dataRef={ "ChangeCount"=531, "LSASN"=ASN:0x0-0x16ed6ec:, "LSPreviousValue"=false, "LSWantsAttention"=true } affectedASN="AttentionBouncer" ASN:0x0-0x16ed6ec:  context=0 sessionID=186a2 not
Notification: kLSNotifyApplicationDeath time=+10.5091s  dataRef={ "ApplicationType"="Foreground", "BundleIdentifierLowerCase"="me.askalice.spacialshell.attention-bouncer", "CFBundleExecutable"="AttentionBouncer", "CFBundleExecutablePath"="/Users/alice/code/spa
Notification: kLSNotifyApplicationWantsAttentionChanged time=+0.000775933s  dataRef={ "ChangeCount"=534, "LSASN"=ASN:0x0-0x16ed6ec:, "LSPreviousValue"=true, "LSWantsAttention"=false } affectedASN=ASN:0x0-0x16ed6ec:  context=0 sessionID=186a2 notificationID=0x1
```

`LSWantsAttention` goes true at the request and false only when the app dies (it was never
activated). `lsappinfo` is a CLI over private LaunchServices SPI; no public API exposes the key.

## Not measured

- `.informationalRequest` (docs: one-second bounce, request stays active).
- Dock auto-hide, Dock on another display edge, reduced motion.
- Probe without the Accessibility grant.
- Real messaging apps (Mail/Messages/Slack not running; not launched to avoid first-run dialogs).
- CPU cost of polling 49 items × 11 attributes at 50 ms.
- Screen captures: the `screencapture -R` rectangle missed the Dock (multi-display coordinate
  mismatch); visual confirmation of the bounce was not obtained. Evidence is the AX series above.
