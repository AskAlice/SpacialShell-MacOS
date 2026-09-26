# Design system — rules for integrating designs (Figma MCP included)

SpacialShell is a macOS spatial window manager: Swift 6 / SwiftPM, SwiftUI hosted in AppKit
panels. **There is no web stack** — no HTML, CSS, stylesheets, npm UI packages, or token
transformation pipeline. A Figma design lands here as SwiftUI views in `Sources/SpacialShellUI/`,
styled with system materials and semantic colors, driven by pure view-state from
`SpacialShellKit`.

The authorities, in order: `docs/superpowers/specs/2026-08-19-m2-shell-ui-design.md`
("Design system (frontend-design pass)" section — its rulings are **binding**, don't re-open
them), then `AGENTS.md` (layering + PR media rules), then the code as it stands. Where the code
diverges from the spec today, that is a bug to close toward the spec, not a precedent
(see "Known divergences" at the end).

## 1. Tokens

**Color: there is no palette.** The OS owns appearance; the ruling is "the OS material *is* the
palette". Binding assignments:

| Role | Value |
|---|---|
| Rail background | `NSVisualEffectView(.sidebar)` vibrancy (SwiftUI material until then) |
| Top bar background | `NSVisualEffectView(.headerView)`, `blendingMode: .behindWindow`, `state: .active` |
| Active workspace / tab | `controlAccentColor` — **18 % fill** on the rounded shape, glyph/text at 100 % |
| Inactive glyphs / text | `secondaryLabelColor` (SwiftUI `.secondary`) |
| Hover | `quaternaryLabelColor` |
| Hairlines | `separatorColor` (SwiftUI `.separator`) |

Light/dark and the accent come from System Settings. Never define a named color, an asset-catalog
palette, a hex constant, or a theme switch. If a Figma file carries a color style, map it to the
nearest semantic above or reject it.

**Type (SF Pro, `.system`):** 12 pt tab titles · 12 pt medium hover labels · 11 pt tooltips ·
9 pt semibold rounded "+N" badge · clock 11 pt medium **monospaced**, HH stacked over MM.
No custom fonts, no font config key — deliberately (see §Config below).

**Space: 8 pt grid.** Rail **48 pt** wide (`panel-width`): 32 pt tiles, radius 8, 8 pt gaps,
16 pt between groups. A tile shows up to four app icons in a 2x2 grid plus its window count; the
app names, category and window previews belong to the hover popover, not the tile — the rail stays
narrow because it is furniture, and detail is one hover away. Top bar **34 pt** tall (`panel-height`): 26 pt tabs, radius 6, 16 pt icons,
10 pt h-padding, tab width 88–220 pt; layout switcher 24 pt glyph, 12 pt from the trailing edge;
badge offset (+7, −7). Panels sit flush to screen edges. (Tried and rejected 2026-09-21: floating cards inset by a `panel-margin`, per `claude/mockup-look` — see #59. There is no margin knob, and the rail stays 48 pt: a wider rail to hold per-workspace layout schematics was rejected with it, #61.)

**The only mutable "tokens" are config keys** (`Sources/SpacialShellKit/Config/Config.swift`),
TOML, kebab-case:

```swift
public var panelWidth: Double = 48      // panel-width
public var panelHeight: Double = 34     // panel-height
public var railSide: RailSide = .left   // rail-side: left | right
public var gap: Double = 8              // gap between tiled windows
```

Deliberately **not** configurable: theme, font, icon set. `theme`/`font`/`icon-set` keys once
existed as dead surface and were **removed** (gap-analysis spec §C: "they contradict the design's
own theming ruling"). Do not reintroduce them, and do not build a token-transformation layer —
Config → views is the entire pipeline.

## 2. Component library

`Sources/SpacialShellUI/` — one view or controller per file. Current inventory:

| File | Role |
|---|---|
| `ScreenPanelView.swift` | Workspace rail (search glyph, tiles, trailing "+") |
| `WorkspacePanelView.swift` | Tab bar + layout switcher (bar set, active-outside, `⋯`, cog) |
| `LayoutGlyph.swift` | A layout's glyph: its SF Symbol, or its zones outlined at 16 × 12 pt (#10) |
| `LayoutMenu.swift` | The switcher's `⋯` `NSMenu`: every layout, sectioned built-in / config.toml / drawn |
| `LayoutPopover.swift` | The tab-bar cog's popover (a non-activating panel) + its controller |
| `LayoutEditorView.swift` | The layout editor: presets, grid canvas, name/id, Copy as TOML (model: Kit `GridEditor`) |
| `LayoutsController.swift` | The editor window and the popover's `settings.json` edits |
| `OverviewView.swift` | Launcher overlay (search, windows + apps grid) |
| `CheatSheetOverlay.swift` | Fn-hold keybinding sheet (view + controller) |
| `PanelWindow.swift` | The non-activating `NSPanel` all chrome lives in |
| `ShellController.swift` / `OverviewController.swift` | AppKit owners: panel lifecycle, geometry, hosting |
| `RailHoverCard.swift` | Rail hover popover: window miniatures, or why there are none |
| `RailHoverController.swift` | Places the hover card beside the tile; owns its capture |
| `WindowPreview.swift` | ScreenCaptureKit per-hover window shots + the Screen Recording grant |
| `AppMetaCache.swift` | pid → app name + icon (`NSRunningApplication`) |

Every view is a pure function of state: **props in, `Command` out.** The canonical shape
(`ScreenPanelView.swift`):

```swift
struct ScreenPanelView: View {
    let state: ScreenShellState          // pure view-state from Kit
    let launcherURL: String              // config value, passed down
    let send: (Command) -> Void          // the ONLY way out
    // ...
    Button { send(.focusWorkspaceID(item.id)) } label: { ... }
```

Controllers (`@MainActor final class`) own `PanelWindow`s and `NSHostingView`s, receive
`update(world:)` / `update(config:)` from AppRuntime, derive per-screen state, set
`host.rootView`, and forward `send`. Views never see `World`, controllers never mutate it.

## 3. Frameworks

- SwiftUI views inside `NSHostingView`, inside borderless **non-activating** `NSPanel`s
  (`PanelWindow.swift`: `canBecomeKey/Main = false`, `.floating`, `backgroundColor = .clear`,
  `isOpaque = false` — the material is the only background; opaque panels render black).
- SwiftPM only (`Package.swift`), macOS 14+, Swift 6 strict concurrency (`@MainActor` UI,
  `@Sendable` send closures). No xcodeproj, no storyboards, no xibs, no asset catalogs.
- Target graph: `SpacialShellProtocol` (wire types, leaf) ← `SpacialShellKit` (pure model,
  no AppKit) ← `SpacialShellPlatform` / `SpacialShellUI` ← `SpacialShell` app.
  `SpacialShellUI` depends on Kit (+ Platform temporarily, for `DisplayTopology.uuid` only).
  Kit must never grow an AppKit import.

## 4. Assets

There are no runtime image assets — icons are SF Symbols and live app icons (§5). The only
committed media is documentation/PR media in `docs/media/`:

- webp preferred, **gif alongside** for inline GitHub playback; stills webp/png. Loops ≲10 s,
  small — the existing showcase loops are the size reference.
- `Scripts/render-m2-media.py` regenerates the rendered loops/stills; new features extend it so
  the overview loop stays current. Renders must be labelled as renders, never passed off as
  captures.
- Embedding (private repo): **only**
  `https://github.com/AskAlice/alice-material/blob/<branch>/docs/media/<file>?raw=true`.
  Never `raw.githubusercontent.com`, `data:` URIs, or `?token=…` links.
- Snapshot references under `Tests/ShellStoryTests/__Snapshots__/` are committed and double as
  PR media.

## 5. Icons

**SF Symbols only.** No icon fonts, no SVG imports, no bundled icon set (`icon-set` was removed
deliberately). Binding assignments from the spec:

| Use | Symbol |
|---|---|
| Search / launcher | `magnifyingglass` |
| Add / trailing empty workspace | `plus` |
| Rail tray (hidden windows + popups, #73) | `tray.full` |
| App menu | `square.stack.3d.up` |
| Layouts | `rectangle` · `rectangle.split.2x1` · `rectangle.split.3x1` · `sidebar.left` (half) · `square.grid.2x2` (grid); a drawn layout without a `symbol` draws its zones (`LayoutGlyph`) |
| All layouts menu · layout popover | `ellipsis` · `gearshape` (the rail's `gearshape` is settings) |
| Missing layout badge | `exclamationmark.triangle.fill`, multicolor |
| Workspace tile | per `rail-icon-style` (#115, `RailTile.face`): `app` — up to four app icons, the workspace's `symbol` when it has none; `category` — the chosen `symbol`, else its category's (`AppCategory.symbol`); `hybrid` — that glyph over the top two app icons. Optional `category-colors` tint the glyph on inactive tiles |
| Category glyphs | `globe` web · `chevron.left.forwardslash.chevron.right` coding · `terminal` · `bubble.left.and.bubble.right` communication · `play.rectangle` media · `paintbrush` design · `doc.text` productivity · `wrench.and.screwdriver` utilities |
| Floating pin | `pin.fill` · close `xmark` |
| Wants attention (#126) | not a symbol: `AttentionDot`, a 7 pt `systemRed` circle ringed in the window background — top-right of a rail tile (opposite the count), on a tab icon's corner, or beside the title when the tab has no icon |
| Native-fullscreen tab | `arrow.up.left.and.arrow.down.right` |
| On-another-Space tab | `macwindow.on.rectangle` (not drawn on hidden tabs, which read as dimmed, nor on fullscreen ones, whose marker already says "own Space") |

Window tabs and overview cells use real app icons via `AppMetaCache`
(`NSRunningApplication(processIdentifier:).icon`), cached per pid. Exporting icons from Figma is
wrong here — find the SF Symbol.

## 6. Styling

- SwiftUI modifiers only. Materials via `.background(.thinMaterial)` today (target:
  `NSVisualEffectView` per the §1 table); state-dependent fills via `AnyShapeStyle` conditionals:

```swift
.fill(tab.isFocused ? AnyShapeStyle(Color.accentColor.opacity(0.22))
                    : AnyShapeStyle(Color.primary.opacity(0.001)))   // ~clear but hit-testable
```

- Hover labels appear after **250 ms** (`.onHover` + `NSTrackingArea` exit guard — hovers stick
  across screen edges otherwise).
- Zen: panels fade 180 ms. `reduce-motion` → instant. There is no focus ring or glow (removed
  2026-09-25, #60).
- Light/dark come from the OS; every story is snapshot-tested in both (`.aqua` / `.darkAqua`).
- Copy: sentence case; verbs on controls ("Rename workspace…"); direct empty states. Raycast
  command names are Title Case (store rule).

## 7. Structure + Figma-integration rules

New UI **must**:

1. **Consume `ShellUIState`, never `World`.** If the design needs data the view-state lacks,
   extend `ScreenShellState`/`ShellUI.state(for:in:)` in
   `Sources/SpacialShellKit/ShellUI/ShellUIState.swift` **first** (pure, unit-testable), then
   render it. No AX, `NSRunningApplication`, or model spelunking in views — non-spatial lookups
   (names, icons) resolve platform-side by pid via `AppMetaCache`.
2. **Send `Command`s, never mutate.** Every interaction goes through `send:` into
   `WorldStore.run(_:)`, exactly like a hotkey. Purely-visual toggles (overview open/close) route
   through their controller, not the store.
3. **Respect panel geometry from Config.** `panel-width`/`panel-height`/`rail-side`/`gap` are the
   layout inputs; the reconciler owns window geometry, insets are data (`ShellInsets`). Don't
   hardcode a Figma frame size where a config key exists.
4. **Add a story.** Every new view/state gets an entry in `Tests/ShellStoryTests/Stories.swift`
   at its true geometry (rail 48×800, bar 1200×34, or fitting size), which buys light+dark image
   snapshots **and** a `LayoutLint` pass (content fits, no text overlap/escape). Unhandled
   overflow states go in flagged `knownOverflow: true`, not omitted. `swift test` is the gate.
5. **Ship PR media** per `AGENTS.md`: screenshots + ≲10 s webp/gif loops of (a) the change and
   (b) the whole shell, inline in the PR body via the `blob/<branch>/...?raw=true` schema;
   extend `Scripts/render-m2-media.py` when the feature changes the showcase.
6. **Never introduce a palette, theme, custom font, or non-SF icon.** Map every Figma color to
   the §1 semantic table; every icon to an SF Symbol; every radius/spacing to the 8 pt grid.
   A design that can't be expressed that way needs a spec amendment, not a workaround.

## Known divergences (code vs binding spec — close toward the spec)

- Both panels use SwiftUI `.thinMaterial`; spec says rail `.sidebar` / bar `.headerView`
  `NSVisualEffectView` with `state: .active`.
- Active rail tile is `accentColor.opacity(0.85)` + white glyph
  (`ScreenPanelView.swift`); spec says 18 % accent fill, glyph at 100 %.
- Tab titles are 11.5 pt (`WorkspacePanelView.swift`); spec says 12 pt. Rail tiles 36 pt; spec 32.
- Half-layout glyph is `rectangle.lefthalf.filled`; spec assigns `sidebar.left`.
- Tab overflow scrolls instead of a "+N" badge: tabs squeeze to the 88 pt floor (focused tab
  +16 for its close button), then the row scrolls with the focused tab kept in view (#14).
  Scrolling the panels (#121) steps on the **vertical** axis only: one step per wheel notch or
  trackpad gesture, momentum swallowed. The rail steps workspaces, the tab row steps the focused
  tab (which the row then scrolls into view), and the layout icons cycle. A **sideways** gesture
  (trackpad, Shift-wheel) passes through untouched, so it still pans an overflowing tab row.
  Layout-switcher hover names are unbuilt.
