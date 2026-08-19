# M2 appendix C — Raycast extension (planner output, verbatim)

I have everything I need. Here's the plan.

---

# SpacialShell Raycast extension — implementation plan

## 0. Findings that change the brief

Three things I verified that alter assumptions in the request:

1. **`spacialctl` does not exist yet.** `grep -rn spacialctl` across `/Users/alice/code/spacial-shell` returns nothing; there is no IPC/socket/XPC layer in `Sources/`, and `Sources/SpacialShellKit/Commands/Command.swift` only models *relative* commands (`focusWorkspace(.up)`, `moveWindowToScreen(.next)`, …). Everything absolute in the contract — `focus-workspace --id`, `focus-window --id --pid`, `move-window --to-workspace`, the whole workspace CRUD set, `toggle-zen` (M2 per README line 28) — is daemon work that does not exist. The extension is therefore built against a *contract*, and the contract must be written down and mocked before any TSX is written (task T0).
2. **Menu-bar `interval` minimum is `1m`, not `10s`.** Manifest docs: "The minimum value is 1 minute (1m)." This matters less than it sounds, because menu-bar commands *re-execute every time the user opens the menu* ("Raycast loads the command, executes it, and keeps it in memory while the menu is open"). So `interval: "1m"` drives only the between-opens title, and freshness at open is guaranteed by the lifecycle.
3. **`mdfind` is unnecessary.** `getApplications()` from `@raycast/api` returns `{ name, path, bundleId }` for every installed app, backed by Raycast's own index. The existing `aerospace` store extension uses exactly this to build a `bundleId → path` map for `{ fileIcon }`. No shelling out, no `mdfind` latency.

Versions pinned from npm today: `@raycast/api@1.104.25` (1.x is the only live major — `latest-v0` is a dead 0.71.5 line; engines `node >= 22.22.2`, ships the `ray` bin, pins `react@19.0.0`, `@types/node@22.19.17`, `@types/react@19.0.10` as peers, so those three get exact-pinned in devDependencies), `@raycast/utils@2.3.0` (peers `@raycast/api >= 1.99.4`, `react >= 19`), `@raycast/eslint-config@2.2.0` (flat config; peers `eslint ^8.57 || ^9 || ^10`, `typescript >=4.8.4 <6.1.0`).

Reference implementation to mirror throughout: `raycast/extensions/extensions/aerospace` — same shape of problem (tiling WM + local CLI), already through store review. Its `src/utils/aerospace.ts` is the canonical "resolve binary path, `promisify(execFile)`, map errors to friendly messages, offer an Open-App toast action" pattern.

---

## Design note

**List layout (Switch).** One `List` with `isShowingDetail={false}`. Sections keyed by screen, section title from `screenTitle(screen)` → `"Main display"` / `"Display 2"`; the section header is omitted entirely when `state.screens.length === 1` (Raycast lists read better without a single lone header). Rows are flat `workspace › window` rather than nested: a workspace row followed by its window rows, window rows carrying `title` as the item title and `"› " + workspace.name` folded into `keywords` so typing a workspace name filters its windows too. Nested `Action.Push` sub-lists are wrong here — the whole point is one keystroke to a destination, and Raycast's fuzzy filter across a flat list is the fastest path. A command-level preference `switchListMode` (`workspaces` | `workspaces-and-windows`, default the latter) lets people who only ever jump rows collapse the noise.

**Iconography.** Workspaces use `iconForSymbol(ws.symbol)` — SF Symbol name normalized (lowercased, `.fill`/`.circle`/`.square` suffixes stripped) then looked up in a ~40-entry map, falling back to `Icon.AppWindow`. Windows use `{ fileIcon: appPath }` from the `getApplications()` map, falling back to `Icon.Window`. Layouts get their own glyph set, used as the accessory on workspace rows and as the menu-bar icon: `maximize → Icon.Maximize`, `split → Icon.AppWindowSidebarLeft`, `column → Icon.StackedBars3`, `half → Icon.AppWindowSidebarRight`, `grid → Icon.AppWindowGrid2x2` (all verified present in the Icon enum). The active workspace gets `Icon.CheckCircle` as a leading accessory; pinned gets `Icon.Pin`; the focused window gets a `Color.Green`-tinted `Icon.CircleFilled`.

**Copy.** Command and extension titles in Title Case (store rule, Apple Style Guide, `<verb> <noun>` for commands). Everything else — descriptions, subtitles, toasts, HUDs, empty-state text — in sentence case. Toast titles state what failed, messages state what to do: `"Couldn't reach SpacialShell"` / `"The daemon isn't running. Launch it from /Applications."`

**Empty and error states.** Four distinct `List.EmptyView`s, never a bare spinner-into-nothing:
- binary missing (`ENOENT`) — "Couldn't find spacialctl" / "Set the path in extension preferences, or reinstall SpacialShell." + `Action.OpenExtensionPreferences`.
- exit 3 — "SpacialShell isn't running" / "Launch it from /Applications to manage workspaces." + an Open action (`open("/Applications/SpacialShell.app")`) + Refresh (⌘R).
- zero screens — "No workspaces yet" / "SpacialShell hasn't seen a display — check the Accessibility permission in System Settings." + an action opening `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
- filter-empty — the default `List` behaviour, no override.

**Keyboard shortcuts.** Use `Keyboard.Shortcut.Common` where it exists so the extension feels native: `Common.Edit` (⌘E) rename, `Common.Pin` (⌘⇧P) pin/unpin, `Common.Remove` (⌃X) remove, `Common.Copy` (⌘⇧C) copy id, `Common.New` (⌘N) add workspace, `Common.Refresh` (⌘R) revalidate. Deliberate deviation from the brief: **do not bind ⌘R to Rename** — ⌘R is Raycast's conventional Refresh and users will hit it expecting a reload. Custom bindings only where no convention exists: ⌘M "Move focused window here", ⌘L the "Set layout" submenu (`ActionPanel.Submenu`), ⌘⇧S "Set symbol".

---

## Task sequence

### T0 — Write the CLI contract down, upstream, before any TS *(blocking)*

**Files:** `/Users/alice/code/spacial-shell/docs/cli.md` (new), `/Users/alice/code/spacial-shell/raycast/test/fixtures/*.json` (new).

`docs/cli.md` becomes the single source of truth for both the Swift side and the extension: every subcommand, every flag, the exit-code table (0 ok / 1 daemon error / 2 usage / 3 not running), and the exact `state` payload. Three amendments the contract as drafted needs before it can render the Switch list:

- **`screens[].rows[].workspaceId: string`** — as drafted, `rows` is a flat per-screen array with no workspace association, so "workspace › window" is unrenderable. Adding `workspaceId` (rather than nesting rows under workspaces) keeps the payload diff-friendly and lets the extension group client-side. Ephemeral/visitor windows, which belong to no workspace (README lines 74-75), carry `workspaceId: null` and render in a trailing "Visitors" section.
- **`screens[].rows[].appName: string`** — otherwise every row needs a `getApplications()` lookup just to show an app name, and unknown bundle ids render blank. The daemon already has `NSRunningApplication` in hand.
- **`capabilities: string[]`** at the top level (e.g. `["workspace-crud", "zen", "symbols"]`). M1's daemon has no zen and no workspace CRUD; without a capability list the extension has to discover unsupported subcommands by parsing exit-2 usage errors. With it, unsupported actions are simply not rendered. This is the difference between an extension that degrades and one that shows dead buttons.

Also freeze `"v": 1` semantics: the extension refuses to parse `v !== 1` and shows "This version of SpacialShell is newer than the extension expects."

Fixtures to capture as JSON files (hand-authored against the contract; they become the vitest corpus and the fake-binary payloads): `single-screen.json`, `two-screens.json`, `empty-no-screens.json`, `visitors.json`, `unknown-symbols.json`, `future-version.json`.

**Risk:** the contract's `subscribe` streaming mode is effectively unusable from Raycast (menu-bar and no-view commands are unloaded as soon as `isLoading` flips false; a long-lived child would leak). It stays in the contract for other consumers; the extension polls. See T17 for the narrow case where it's viable.

---

### T1 — `raycast/package.json` (the manifest)

**Files:** `/Users/alice/code/spacial-shell/raycast/package.json`.

```json
{
  "$schema": "https://www.raycast.com/schemas/extension.json",
  "name": "spacial-shell",
  "title": "SpacialShell",
  "description": "Switch workspaces, move windows, and drive the SpacialShell spatial window manager for macOS.",
  "icon": "icon.png",
  "author": "AskAlice",
  "categories": ["Productivity", "System"],
  "license": "MIT",
  "platforms": ["macOS"],
  "keywords": ["window manager", "tiling", "workspace", "spatial", "material-shell"],
  "preferences": [
    {
      "name": "spacialctlPath",
      "title": "spacialctl Path",
      "description": "Path to the spacialctl binary. Leave empty to auto-detect.",
      "type": "textfield",
      "required": false,
      "default": "/Applications/SpacialShell.app/Contents/MacOS/spacialctl",
      "placeholder": "/usr/local/bin/spacialctl"
    }
  ],
  "commands": [
    { "name": "switch", "title": "Switch Workspace", "subtitle": "SpacialShell",
      "description": "Jump to a workspace or a window on any screen.", "mode": "view",
      "preferences": [
        { "name": "switchListMode", "title": "Show", "type": "dropdown", "required": false,
          "default": "workspaces-and-windows",
          "data": [
            { "title": "Workspaces and windows", "value": "workspaces-and-windows" },
            { "title": "Workspaces only", "value": "workspaces" }
          ] }
      ] },
    { "name": "move-window", "title": "Move Window", "subtitle": "SpacialShell",
      "description": "Move the focused window to another workspace or screen.", "mode": "view" },
    { "name": "manage-workspaces", "title": "Manage Workspaces", "subtitle": "SpacialShell",
      "description": "Add, rename, re-symbol, pin, and remove workspaces.", "mode": "view" },
    { "name": "workspace-menu-bar", "title": "Show Workspace in Menu Bar",
      "description": "Show the active workspace and layout in the menu bar.",
      "mode": "menu-bar", "interval": "1m" },
    { "name": "set-layout", "title": "Set Layout", "subtitle": "SpacialShell",
      "description": "Set the active workspace's layout.", "mode": "no-view",
      "arguments": [
        { "name": "layout", "type": "dropdown", "placeholder": "Layout", "required": true,
          "data": [
            { "title": "Maximize", "value": "maximize" },
            { "title": "Split", "value": "split" },
            { "title": "Column", "value": "column" },
            { "title": "Half", "value": "half" },
            { "title": "Grid", "value": "grid" }
          ] }
      ] },
    { "name": "cycle-layout", "title": "Cycle Layout", "subtitle": "SpacialShell", "description": "Cycle the active workspace's layout.", "mode": "no-view" },
    { "name": "toggle-zen", "title": "Toggle Zen Mode", "subtitle": "SpacialShell", "description": "Toggle Zen mode.", "mode": "no-view" },
    { "name": "focus-workspace-up", "title": "Focus Workspace Up", "subtitle": "SpacialShell", "description": "Focus the workspace above.", "mode": "no-view" },
    { "name": "focus-workspace-down", "title": "Focus Workspace Down", "subtitle": "SpacialShell", "description": "Focus the workspace below.", "mode": "no-view" },
    { "name": "focus-window-left", "title": "Focus Window Left", "subtitle": "SpacialShell", "description": "Focus the previous window in the row.", "mode": "no-view" },
    { "name": "focus-window-right", "title": "Focus Window Right", "subtitle": "SpacialShell", "description": "Focus the next window in the row.", "mode": "no-view" },
    { "name": "move-window-up", "title": "Move Window Up", "subtitle": "SpacialShell", "description": "Move the focused window to the workspace above.", "mode": "no-view" },
    { "name": "move-window-down", "title": "Move Window Down", "subtitle": "SpacialShell", "description": "Move the focused window to the workspace below.", "mode": "no-view" },
    { "name": "move-window-left", "title": "Move Window Left", "subtitle": "SpacialShell", "description": "Swap the focused window with its left neighbour.", "mode": "no-view" },
    { "name": "move-window-right", "title": "Move Window Right", "subtitle": "SpacialShell", "description": "Swap the focused window with its right neighbour.", "mode": "no-view" }
  ],
  "dependencies": { "@raycast/api": "^1.104.25", "@raycast/utils": "^2.3.0" },
  "devDependencies": {
    "@raycast/eslint-config": "^2.2.0",
    "@types/node": "22.19.17",
    "@types/react": "19.0.10",
    "eslint": "^9.39.0",
    "prettier": "^3.3.3",
    "typescript": "^5.9.3",
    "vitest": "^3.2.4"
  },
  "scripts": {
    "build": "ray build -e dist",
    "dev": "ray develop",
    "lint": "ray lint",
    "fix-lint": "ray lint --fix",
    "test": "vitest run",
    "typecheck": "tsc --noEmit",
    "publish": "npx @raycast/api@latest publish"
  }
}
```

Notes: `@types/node` and `@types/react` are exact-pinned to `@raycast/api`'s peer versions (unpinned ranges cause `ray build` type mismatches). `platforms: ["macOS"]` matches what shipped extensions now carry. Fifteen commands is a lot for the root search — every one carries `subtitle: "SpacialShell"` so they group visibly, and the directional ones exist purely as hotkey targets.

**Risk:** store reviewers sometimes push back on large no-view command sets. The justification (each must be independently bindable to a Raycast hotkey) goes in the README; if review objects, the twelve directional commands collapse into one `run-command` with a dropdown argument at the cost of per-verb hotkeys.

---

### T2 — Toolchain config

**Files:** `raycast/tsconfig.json`, `raycast/eslint.config.mjs`, `raycast/.prettierrc`, plus one line appended to `/Users/alice/code/spacial-shell/.gitignore`.

`tsconfig.json` copies the current Raycast template verbatim (`"lib": ["ES2023"]`, `module: commonjs`, `target: ES2022`, `strict: true`, `isolatedModules`, `jsx: react-jsx`) with `"include": ["src/**/*", "test/**/*", "raycast-env.d.ts"]` so tests typecheck too. `eslint.config.mjs` is the three-line flat config (`defineConfig([...raycastConfig])`). `.prettierrc`: `{ "printWidth": 120, "singleQuote": false }` — matching the store's house style so `ray lint` passes clean. Root `.gitignore` gains `raycast/node_modules/`, `raycast/dist/`, `raycast/raycast-env.d.ts` (generated by `ray`, and conventionally *not* committed — but note that `raycast/extensions` PRs do commit `package-lock.json`, so that one is tracked).

---

### T3 — `src/lib/types.ts` + parser tests

**Files:** `raycast/src/lib/types.ts`, `raycast/test/types.test.ts`.

Hand-rolled validation, no `zod` — one fewer dependency for review, and the parser is the single place the contract is enforced.

```ts
export const LAYOUTS = ["maximize", "split", "column", "half", "grid"] as const;
export type Layout = (typeof LAYOUTS)[number];
export function isLayout(value: unknown): value is Layout;

export interface WindowRef { id: number; pid: number }
export interface WorkspaceSummary {
  id: string; name: string; symbol: string; layout: Layout;
  pinned: boolean; isActive: boolean; windowCount: number;
}
export interface WindowRow {
  window: WindowRef; workspaceId: string | null; title: string;
  appName: string; bundleId: string | null; pid: number;
  isFocused: boolean; isVisibleUnderLayout: boolean; isFloating: boolean; isHidden: boolean;
}
export interface ScreenState {
  id: string; index: number; isMain: boolean; activeWorkspaceId: string;
  workspaces: WorkspaceSummary[]; rows: WindowRow[];
}
export interface ShellState {
  v: 1; screens: ScreenState[];
  focus: { screen: string; window: WindowRef | null };
  zen: boolean; capabilities: string[];
}

export class StateParseError extends Error { readonly path: string; }
export function parseState(raw: unknown): ShellState;           // throws StateParseError
export function hasCapability(s: ShellState, c: string): boolean;
export function focusedScreen(s: ShellState): ScreenState | undefined;
export function focusedWindow(s: ShellState): WindowRow | undefined;
export function activeWorkspace(screen: ScreenState): WorkspaceSummary | undefined;
export function findWorkspace(s: ShellState, id: string): { screen: ScreenState; workspace: WorkspaceSummary } | undefined;
export function rowsForWorkspace(screen: ScreenState, workspaceId: string): WindowRow[];
export function visitorRows(screen: ScreenState): WindowRow[];  // workspaceId === null
```

`parseState` is forgiving in one direction only: unknown *extra* fields are ignored (forward compatibility with a newer daemon), missing or wrong-typed *known* fields throw with a JSON path (`"screens[1].workspaces[0].layout"`). An unknown `layout` string does **not** throw — it degrades to `"maximize"` with a `console.warn`, because a future sixth layout shouldn't brick the list.

**Tests:** every fixture parses; `future-version.json` throws; each field-omission mutation throws with the right `path`; unknown layout degrades; `capabilities` defaults to `[]` when absent (so the extension works against a daemon predating T0's amendment).

---

### T4 — `src/lib/spacialctl.ts` (the one exec layer)

**Files:** `raycast/src/lib/spacialctl.ts`, `raycast/test/spacialctl.test.ts`, `raycast/test/fixtures/fake-spacialctl` (executable shell stub).

**`useExec` vs `execFile` — decision: `execFile`.** `useExec` is a hook, so it cannot be called from an `Action.onAction` handler, from a `no-view` command's default export, or from `MenuBarExtra.Item.onAction` — which is where every mutation in this extension happens. Binary resolution is also async (`fs.access` probing across candidate paths), so the `file` argument isn't available at first render and `useExec` would need `execute: false` plus a re-render dance. One `promisify(execFile)` layer, wrapped by `useCachedPromise` in T6, keeps a single error-mapping path for views, menu bar, and hotkey commands alike.

```ts
export type SpacialctlErrorKind = "not-found" | "not-running" | "daemon" | "usage" | "timeout" | "unknown";
export class SpacialctlError extends Error {
  readonly kind: SpacialctlErrorKind;
  readonly exitCode?: number;
  readonly stderr: string;
}

export function resolveBinary(): Promise<string>;              // memoized in module scope
export function run(args: string[], opts?: { timeoutMs?: number; signal?: AbortSignal }): Promise<string>;
export function runJson<T>(args: string[], opts?: { timeoutMs?: number; signal?: AbortSignal }): Promise<T>;
export function getState(signal?: AbortSignal): Promise<ShellState>;

export type NamedCommand =
  | "focus-workspace-up" | "focus-workspace-down"
  | "focus-window-left" | "focus-window-right" | "close-window"
  | "move-window-left" | "move-window-right" | "move-window-up" | "move-window-down"
  | "cycle-layout" | "toggle-shell-ui"
  | "focus-screen-prev" | "focus-screen-next"
  | "move-window-to-screen-prev" | "move-window-to-screen-next" | "toggle-float"
  | `focus-workspace-${1|2|3|4|5|6|7|8|9|10}`;
export function runNamed(name: NamedCommand): Promise<void>;

export function focusWorkspace(t: { id: string } | { index: number } | { name: string }): Promise<void>;
export function focusWindow(ref: WindowRef): Promise<void>;
export function moveWindowToWorkspace(workspaceId: string, ref?: WindowRef): Promise<void>;
export function moveWindowToScreen(target: string | "next" | "prev", ref?: WindowRef): Promise<void>;
export function addWorkspace(o: { screen?: string; name?: string; pinned?: boolean }): Promise<void>;
export function renameWorkspace(id: string, name: string): Promise<void>;
export function setSymbol(id: string, symbol: string): Promise<void>;
export function setLayout(layout: Layout, id?: string): Promise<void>;
export function pinWorkspace(id: string, pinned: boolean): Promise<void>;
export function removeWorkspace(id: string): Promise<void>;
export function toggleZen(): Promise<void>;
```

Implementation details that matter:

- `runJson` prepends `--json` (`spacialctl --json state`), `run` does not. `execFile(file, args)` — never `shell: true`, so workspace names with quotes, `$`, or spaces need no escaping.
- **Exit-code disambiguation trap:** promisified `execFile` rejects with `err.code` set to the *numeric* exit status on a non-zero exit, but to the *string* `"ENOENT"` when the binary itself is missing. Branch on `typeof err.code === "number"` first; `3 → "not-running"`, `1 → "daemon"`, `2 → "usage"`; `"ENOENT" → "not-found"`; `err.killed && err.signal === "SIGTERM" → "timeout"`.
- `resolveBinary()` order: the `spacialctlPath` preference if non-empty (with an `fs.access` check that throws a *specific* "the path you set doesn't exist" message), then `/Applications/SpacialShell.app/Contents/MacOS/spacialctl`, then `/usr/local/bin/spacialctl`, then `/opt/homebrew/bin/spacialctl`, then `~/Applications/SpacialShell.app/...`. **Never rely on `PATH`** — Raycast's node process gets a minimal environment and does not source the user's shell profile; `/usr/local/bin` in particular is not guaranteed. This is exactly why the `aerospace` extension probes absolute paths.
- Timeouts: 4000 ms for `state`, 8000 ms for mutations. A hung daemon must not wedge the UI (the daemon's own `ax-timeout-ms` defaults to 1000 ms per `docs/config.md`, so 4 s is generous).
- Memoize the resolved path in module scope, and invalidate it on any `not-found` so a mid-session reinstall recovers without a Raycast restart.

**Tests:** point the preference at `test/fixtures/fake-spacialctl`, a stub script that echoes a fixture for `--json state` and exits with a code chosen by an env var. Cases: happy path parses; exit 3 → `kind: "not-running"`; exit 1 with stderr → `kind: "daemon"` and stderr's first line as `message`; exit 2 → `"usage"`; nonexistent path → `"not-found"`; args containing spaces and `"` survive round-trip (assert the stub's echoed `$@`).

---

### T5 — `src/lib/feedback.ts`

**Files:** `raycast/src/lib/feedback.ts`.

```ts
export function failureToastOptions(error: unknown): { title: string; message?: string; primaryAction?: Toast.ActionOptions };
export function reportFailure(error: unknown, fallbackTitle?: string): Promise<void>;   // wraps showFailureToast
export function reportFailureHud(error: unknown): Promise<void>;                        // for no-view commands
export function emptyViewProps(error: unknown): { icon: Image.ImageLike; title: string; description: string };
```

The `not-running` case gets `primaryAction: { title: "Open SpacialShell", onAction: (toast) => { open("/Applications/SpacialShell.app"); toast.hide(); } }`; the `not-found` case gets `{ title: "Open Extension Preferences", onAction: openExtensionPreferences }`. `reportFailureHud` exists because no-view commands have no window to host a toast — a toast shown from a no-view command may never be seen; `showHUD` always is.

---

### T6 — `src/lib/useShellState.ts`

**Files:** `raycast/src/lib/useShellState.ts`.

```ts
export interface ShellStateHandle {
  state?: ShellState;
  isLoading: boolean;
  error?: Error;
  revalidate: () => void;
  mutate: MutatePromise<ShellState | undefined>;
  /** run a mutation, then optimistically refresh */
  act: (fn: () => Promise<void>, opts?: { hud?: string; close?: boolean }) => Promise<void>;
}
export function useShellState(options?: { pollMs?: number; execute?: boolean }): ShellStateHandle;
```

Built on `useCachedPromise(getState, [], { keepPreviousData: true, abortable, failureToastOptions })` — `useCachedPromise` has **no built-in polling**, so the interval is ours: a `useEffect` with `setInterval`, guarded by an `isLoading` ref so a slow `state` call can't stack up, and **disabled entirely (`pollMs: 0`) by default**. Views opt in with `pollMs: 2000`; the menu-bar command must not, because a live interval keeps `isLoading` churning and Raycast will not unload the command ("set it to `true` while it's performing an async task and then `false` once it's done" is a hard lifecycle requirement for menu-bar). Polling also self-suspends after two consecutive `not-found` / `not-running` errors so a dead daemon doesn't spawn a process every two seconds forever — the empty view's Refresh action re-arms it.

`act()` is the shared mutation path: run the CLI call, `await mutate(...)` or `revalidate()`, and on failure route through `reportFailure`. Views that close on success pass `{ close: true, hud: "Switched to Code" }`, which calls `showHUD` — note `showHUD` **closes the main window itself** ("showHUD closes the main window when called"), so calling `closeMainWindow()` beforehand is redundant. Use `showHUD(text, { popToRootType: PopToRootType.Immediate })` so the next invocation starts at root rather than back inside a stale list.

---

### T7 — `src/lib/icons.ts` + tests

**Files:** `raycast/src/lib/icons.ts`, `raycast/test/icons.test.ts`.

```ts
export function normalizeSymbol(symbol: string): string;   // "terminal.fill" -> "terminal"
export function iconForSymbol(symbol: string): Icon;       // fallback Icon.AppWindow
export function iconForLayout(layout: Layout): Icon;
export function glyphForLayout(layout: Layout): string;    // "▣" "◧" "▥" "◨" "⊞"
export function layoutTitle(layout: Layout): string;       // "Maximize" ... (Title Case, for menus)
export const SYMBOL_CHOICES: ReadonlyArray<{ symbol: string; title: string; icon: Icon }>;
```

`normalizeSymbol` lowercases, then strips trailing `.fill`, `.circle`, `.square`, `.circle.fill`, `.square.fill`, and finally tries the first dot-segment — so `terminal.fill`, `folder.circle.fill`, and `folder` all land on one entry. Map (all Icon names verified against the current enum): `terminal→Terminal`, `chevron.left.forwardslash.chevron.right`/`curlybraces`/`code→Code`, `safari`/`globe`/`network→Globe`, `message`/`bubble.left→Message`, `music.note`/`music→Music`, `folder→Folder`, `square.grid.2x2→AppWindowGrid2x2`, `square.grid.3x3→AppWindowGrid3x3`, `envelope→Envelope`, `calendar→Calendar`, `doc`/`doc.text→Document`, `paintbrush→Brush`, `hammer`/`wrench→Hammer`, `gear`/`gearshape→Gear`, `star→Star`, `heart→Heart`, `bolt→Bolt`, `moon→Moon`, `sun.max→Sun`, `camera→Camera`, `photo→Image`, `play.rectangle`/`film→FilmStrip`, `cart→Cart`, `book→Book`, `pencil→Pencil`, `magnifyingglass→MagnifyingGlass`, `lock→Lock`, `person`/`person.2→Person`/`TwoPeople`, `display`/`macwindow→Monitor`, `desktopcomputer→Desktop`, `list.bullet→BulletPoints`, `tag→Tag`, `flag→Flag`, `pin→Pin`, `trash→Trash`, `cloud→Cloud`, `chart.bar→BarChart`, `phone→Phone`, `headphones→Headphones`, `gamecontroller→GameController`, `airplane→Airplane`, `house→House`.

`SYMBOL_CHOICES` is that same table projected into a curated ~24-entry picker for the Add/Set-Symbol form, so users pick from a dropdown with live icons rather than typing an SF Symbol name blind — but the form also accepts a free-text symbol for anything not in the list (the daemon stores the string regardless; the map only affects Raycast rendering).

**Tests:** the fallback path for junk input; `.fill`/`.circle` normalization; every `SYMBOL_CHOICES.symbol` resolves to a non-fallback icon (guards against a typo silently degrading the picker); `glyphForLayout` is total over `LAYOUTS`.

---

### T8 — `src/lib/apps.ts` + `src/lib/format.ts` + tests

**Files:** `raycast/src/lib/apps.ts`, `raycast/src/lib/format.ts`, `raycast/test/format.test.ts`.

```ts
// apps.ts
export function useAppPaths(): { paths: Map<string, string>; isLoading: boolean };
export function appIcon(bundleId: string | null, paths: Map<string, string>): Image.ImageLike;

// format.ts
export function screenTitle(screen: ScreenState, total: number): string;   // "Main display" | "Display 2"
export function workspaceSubtitle(ws: WorkspaceSummary): string;           // "3 windows · Half"
export function workspaceAccessories(ws: WorkspaceSummary): List.Item.Accessory[];
export function windowAccessories(row: WindowRow): List.Item.Accessory[];  // Floating / Hidden / focused dot
export function windowKeywords(row: WindowRow, ws?: WorkspaceSummary): string[];
export function pluralize(n: number, one: string, many: string): string;
```

`useAppPaths` = `useCachedPromise(getApplications, [], { initialData: [] })` reduced to a `Map`; `getApplications()` is one native call (no `mdfind`, no per-row shelling), and `useCachedPromise` keeps the previous result in Raycast's cache so the icons paint on first frame of subsequent launches. `appIcon` returns `{ fileIcon: path }` when known, `Icon.Window` otherwise.

**Tests:** `format.ts` is pure and fully unit-testable — singular/plural, layout capitalization, "Empty" for zero windows, accessory ordering (active before pinned before count), `screenTitle` collapsing to `"Main display"` only when `isMain`, keyword generation including both window title tokens and the workspace name.

---

### T9 — Switch (view)

**Files:** `raycast/src/switch.tsx`, `raycast/src/components/WorkspaceActions.tsx`, `raycast/src/components/RenameWorkspaceForm.tsx`.

`switch.tsx` renders `<List isLoading={isLoading} searchBarPlaceholder="Search workspaces and windows…">`, one `List.Section` per screen (header suppressed when there's one screen), interleaving workspace rows and their window rows; a trailing "Visitors" section for `workspaceId === null` rows. `useShellState({ pollMs: 2000 })` + `useAppPaths()`.

- Workspace row: `id={ws.id}`, `icon={iconForSymbol(ws.symbol)}`, `title={ws.name}`, `subtitle={workspaceSubtitle(ws)}`, `accessories={workspaceAccessories(ws)}`. Primary action `Enter` → `act(() => focusWorkspace({ id: ws.id }), { close: true, hud: \`Switched to ${ws.name}\` })`.
- Window row: `icon={appIcon(row.bundleId, paths)}`, `title={row.title || row.appName}`, `subtitle={row.appName}`, `keywords={windowKeywords(row, ws)}`. Primary action → `focusWindow(row.window)`.

`WorkspaceActions.tsx` is one shared `<ActionPanel.Section>` reused by Switch and Manage: Move Focused Window Here (⌘M, disabled — not hidden — when `state.focus.window == null`, with a subtitle explaining why), Rename (⌘E → `Action.Push` to `RenameWorkspaceForm`), Set Layout (`ActionPanel.Submenu` ⌘L with the five `layoutTitle` items, current one carrying `Icon.CheckCircle`), Pin/Unpin (⌘⇧P), Remove (⌃X, `style: Action.Style.Destructive`, gated behind `confirmAlert({ title: \`Remove ${ws.name}?\`, message: "Its windows move to the workspace below.", primaryAction: { title: "Remove", style: Alert.ActionStyle.Destructive }, rememberUserChoice: true })`), Copy Workspace ID (⌘⇧C), Refresh (⌘R). Every workspace-CRUD action is wrapped in `hasCapability(state, "workspace-crud")` so an M1 daemon shows only focus + move.

**Risk:** ⌘M is not a Raycast convention and could collide with a future built-in; documented in the README's shortcut table. **Risk:** 2 s polling means a `spacialctl` process every 2 s while the list is open — acceptable for a local Swift binary answering from memory, but the T17 subscribe path removes it entirely if profiling says otherwise.

---

### T10 — Move Window To… (view)

**Files:** `raycast/src/move-window.tsx`.

`useShellState({ pollMs: 0 })` — a one-shot list; nothing should shift under the user's cursor mid-selection. Sections: "Workspaces" (all screens, every workspace, the current one marked `Icon.CheckCircle` and its action a no-op-with-HUD rather than hidden), then "Screens" with "Next screen" / "Previous screen" (`Icon.ArrowRight` / `Icon.ArrowLeft`) — rendered only when `state.screens.length > 1`, plus a per-screen "Move to Display N" entry using the screen uuid.

Guard first: if `state.focus.window == null`, render a single `List.EmptyView` — "No focused window" / "Focus a window first, then run this command." — rather than a list of destinations that will all fail.

Success: `showHUD(\`Moved to ${ws.name}\`, { popToRootType: PopToRootType.Immediate })`. The window ref is captured from `state.focus.window` at render and passed explicitly as `--id/--pid`, **not** left implicit — between opening Raycast and pressing Enter the daemon's idea of "focused" is Raycast itself or whatever the reconciler saw last, and an implicit target would move the wrong window. This is the single highest-consequence correctness detail in the extension.

---

### T11 — Manage Workspaces (view)

**Files:** `raycast/src/manage-workspaces.tsx`, `raycast/src/components/WorkspaceForm.tsx`.

List identical in shape to Switch's workspace rows (no window rows), `pollMs: 5000`. Actions: Add (⌘N → push `WorkspaceForm` in create mode) plus the whole `WorkspaceActions` set, with Set Symbol (⌘⇧S) added.

`WorkspaceForm.tsx` serves create and edit from one component:

```tsx
export function WorkspaceForm(props: {
  mode: "create" | "edit";
  screens: ScreenState[];
  workspace?: WorkspaceSummary;
  defaultScreenId?: string;
  onSaved: () => void;   // revalidate + pop
}): JSX.Element;
```

Fields via `useForm<{ name: string; symbol: string; customSymbol: string; pinned: boolean; screenId: string; layout: Layout }>` with `validation: { name: FormValidation.Required }`. `Form.Dropdown` for symbol built from `SYMBOL_CHOICES` (each `Form.Dropdown.Item` carrying its `icon`) with a trailing `"custom"` option that reveals a `Form.TextField` for a raw SF Symbol name; `Form.Checkbox` for pinned; `Form.Dropdown` for screen (hidden when there's one screen, value pre-filled); `Form.Dropdown` for layout. Create issues `add-workspace` then, if the symbol/layout differ from defaults, follow-up `set-symbol` / `set-layout` calls — **which needs the new workspace's id**. `add-workspace` as specified returns nothing useful; T0 should extend it to print `{"id":"<uuid>"}` on stdout under `--json`. Fallback if that amendment doesn't land: re-fetch `state` and diff workspace ids before/after — race-prone and worth avoiding.

---

### T12 — Menu bar

**Files:** `raycast/src/workspace-menu-bar.tsx`.

`useShellState({ pollMs: 0 })` — critical, per T6. Render:

```tsx
<MenuBarExtra icon={iconForLayout(layout)} title={ws?.name} tooltip={`SpacialShell — ${screenTitle(...)}, ${layoutTitle(layout)}`} isLoading={isLoading}>
```

Sections: one per screen (title = screen name) listing workspaces, each `MenuBarExtra.Item` with `icon={iconForSymbol}`, `title={ws.name}`, `subtitle={String(ws.windowCount)}`, `onAction={() => focusWorkspace({ id })}`; a "Layout" section with the five layouts (current one `Icon.CheckCircle`); "Toggle Zen" (`Icon.Moon`, rendered only when `hasCapability(state, "zen")`); a final section with "Open SpacialShell docs" (`open(...)` — the repo README URL, TBD until the GitHub remote is public) and "Preferences…" (`openExtensionPreferences`).

Error state: `title="SpacialShell"`, `icon={Icon.Warning}`, one item "SpacialShell isn't running" and one "Open SpacialShell".

The brief's "refresh after any action" is a lifecycle no-op *inside* the menu — clicking an item closes the menu and unloads the command, so there is nothing left to re-render. The refresh that matters is from *elsewhere*: every no-view command (T13) fires `launchCommand({ name: "workspace-menu-bar", type: LaunchType.Background }).catch(() => {})` after a successful mutation, so hotkey-driven workspace changes update the title immediately instead of waiting up to a minute. The `.catch` is mandatory — `launchCommand` throws if the user has disabled the menu-bar command, and an unhandled rejection in a no-view command surfaces as a scary error toast.

**Risk:** whether `launchCommand` can target a `menu-bar` command with `LaunchType.Background` should be smoke-tested on day one; if it can't, fall back to `interval: "1m"` alone and document the lag.

---

### T13 — No-view commands

**Files:** `raycast/src/lib/noView.ts`, `raycast/src/set-layout.ts`, and twelve ~3-line files (`raycast/src/cycle-layout.ts`, `focus-workspace-up.ts`, …).

```ts
// lib/noView.ts
export function noViewCommand(name: NamedCommand): () => Promise<void>;
export function refreshMenuBar(): Promise<void>;   // launchCommand(...).catch(() => {})
```

Each leaf file is `export default noViewCommand("focus-window-left");`. Success is silent — the windows move, that *is* the feedback; a HUD on every arrow press would be maddening. Only failure speaks, via `reportFailureHud`. `set-layout.ts` is the one with an argument:

```ts
export default async function Command(props: LaunchProps<{ arguments: Arguments.SetLayout }>): Promise<void>;
```

using the `Arguments.SetLayout` type generated into `raycast-env.d.ts`, validating with `isLayout()` before calling `setLayout(...)` (the dropdown constrains it, but a deep link can't be trusted). `toggle-zen.ts` calls `toggleZen()` and maps a `usage` error to the HUD "This version of SpacialShell doesn't support Zen mode yet."

---

### T14 — Assets, changelog, readme, licence

**Files:** `raycast/assets/icon.png`, `raycast/scripts/generate-icon.mjs`, `raycast/CHANGELOG.md`, `raycast/README.md`, `raycast/LICENSE`.

The store hard-requires a **custom** 512×512 PNG ("Extensions that use the default Raycast icon will be rejected"). Generate a placeholder with a zero-dependency Node script — `raycast/scripts/generate-icon.mjs` writes a valid PNG by hand (IHDR/IDAT/IEND chunks, `zlib.deflateSync` for the pixel data, a CRC32 table), drawing a rounded-square field with three stacked rows and one highlighted active row — the spatial model in one glyph. Zero deps means no `sharp`/`canvas` in `devDependencies` for reviewers to question, and the script is ~90 readable lines. It emits both `icon.png` and `icon@dark.png` (same geometry, inverted field) so the icon reads in both themes. Flag in the README that this is a placeholder pending a designed icon; the store also wants `metadata/*.png` screenshots at 2000×1250 for the listing, captured later with Raycast's own "Create Screenshot" developer command.

`CHANGELOG.md` uses the enforced header format: `## [Initial Version] - {PR_MERGE_DATE}`. `LICENSE` is a copy of the repo's MIT text (the extension folder in `raycast/extensions` needs its own). `README.md` covers: what SpacialShell is, that the extension needs the app installed and running, the optional `/usr/local/bin/spacialctl` symlink, the `spacialctlPath` preference, the shortcut table, and the hotkey-binding recipe for the no-view commands.

---

### T15 — CI

**Files:** `/Users/alice/code/spacial-shell/.github/workflows/raycast.yml` (the repo has no `.github/` yet — this is the first workflow).

Two jobs, `paths: ["raycast/**", ".github/workflows/raycast.yml"]`, `defaults.run.working-directory: raycast`:

- **`check`** on `macos-latest`, `actions/setup-node@v4` with `node-version: 22` (matching `@raycast/api`'s `engines: node >= 22.22.2`) and `cache: npm`: `npm ci` → `npm run typecheck` → `npx prettier --check .` → `npm test`. This job is the gate; it needs no Raycast account and no Raycast.app.
- **`ray`** on `macos-latest`, `continue-on-error: true` initially: `npm run lint` (`ray lint`) then `npm run build` (`ray build -e dist`).

The `continue-on-error` is deliberate and evidence-based: raycast/extensions' own `extensions_build_publish.yml` runs the Ray CLI through `raycast/github-actions/ray@v1.18.0` with `access_token: ${{ secrets.RAYCAST_CLI_ACCESS_TOKEN }}`, and third-party build actions document that without a login "some linting checks are skipped". So `ray build` in an unauthenticated headless runner is unproven. Flip the job to required once one green run proves it works; if it can't, either add the third-party `timrogers/build-raycast-extension` action or drop to lint-only in CI and rely on the raycast/extensions PR CI for the real build check.

---

### T16 — Dev loop and publishing runbook

**Files:** `raycast/README.md` (dev section), `/Users/alice/code/spacial-shell/docs/cli.md` (cross-link).

Dev loop: `cd raycast && npm install && npm run dev`. `ray develop` "imports the extension to Raycast if it wasn't before" — so **Raycast.app must be installed and running** (it is here: `/Applications/Raycast.app`); the extension appears immediately in root search with hot reload and errors surfaced in the terminal. `raycast-env.d.ts` regenerates on every `ray develop`/`ray build`, which is where `Preferences`, `Preferences.Switch`, and `Arguments.SetLayout` come from — the first `npm run dev` must run before `tsc --noEmit` will pass locally, and CI must run `ray build` or commit the file if `typecheck` is to be independent (recommendation: commit `raycast-env.d.ts` after all, contrary to the usual template `.gitignore`, precisely so CI's `check` job needs no Raycast CLI).

Testing against a real daemon: build and install the app (`Scripts/bundle.sh`, move to `/Applications`, grant Accessibility), run it, then `spacialctl --json state | jq` in a terminal to confirm the payload before touching the extension. For pre-daemon development, point the `spacialctlPath` preference at `raycast/test/fixtures/fake-spacialctl` — the same stub the unit tests use — which makes every view fully exercisable, including error paths, by flipping an env var.

Publishing: `npm run publish` (`npx @raycast/api@latest publish`) authenticates via GitHub and opens the PR automatically; the manual route is fork `raycast/extensions`, copy `raycast/` to `extensions/spacial-shell/`, PR to `main`. Store rules that bear on this extension: **calling system/local binaries is explicitly allowed** (✅ "Calling system binaries"), while bundling opaque binaries is not — so shipping `spacialctl` inside the extension is out, and the README must explain how to get it. The guideline "avoid asking users to perform additional downloads and try to automate as much as possible" cuts against us slightly; the mitigation is a good empty state with a one-click "Open SpacialShell" / preferences action rather than a wall of setup text, and a note that the CLI ships inside the app the user already installed. Also required: `CHANGELOG.md` (enforced by `changelog_enforcer.yml`), a custom icon, at least one Title-Case category, and `metadata/` screenshots (enforced by `metadata_image_enforcer.yml`).

---

### T17 — Optional: event-driven updates via `subscribe`

**Files:** `raycast/src/lib/useShellStream.ts`.

Only viable inside `view` commands, which stay resident while open. `child_process.spawn(bin, ["subscribe"])`, `readline` over stdout, `JSON.parse` each `{"event":"shell","data":<state>}` line into the same `parseState`, `child.kill()` in the `useEffect` cleanup. Strictly better than 2 s polling (no process churn, instant updates) but carries real risk: an orphaned child if Raycast tears the command down without running cleanup, partial-line buffering, and backpressure if the daemon emits rapidly. Ship polling first; add this behind a `liveUpdates` preference once the daemon exists and the stream's behaviour is observable.

---

## Consolidated risks

| Risk | Impact | Mitigation |
|---|---|---|
| `spacialctl` does not exist | The entire extension is unrunnable | T0 contract doc + fake binary; extension developed and tested against fixtures |
| `rows[]` has no `workspaceId` | Switch list cannot be rendered as specified | Contract amendment in T0 |
| M1 daemon lacks zen and workspace CRUD | Dead actions that error on click | `capabilities[]` in state; every action gated on `hasCapability` |
| Menu-bar `interval` min is `1m` | Stale title between opens | Re-execution on menu open + `launchCommand` background refresh from no-view commands |
| Polling keeps menu-bar command loaded | Command never unloads; Raycast complains | `pollMs: 0` default; only views opt in |
| `PATH` is minimal in Raycast's node | `spacialctl` not found despite being installed | Absolute-path probing, never bare `spacialctl` |
| `err.code` is number *or* `"ENOENT"` | Exit-3 mis-classified as ENOENT | `typeof err.code === "number"` branch first, unit-tested |
| Implicit focused-window target | Wrong window moved | Always pass explicit `--id/--pid` captured at render |
| `ray build` may need a Raycast token in CI | Red CI on a working extension | `continue-on-error` until proven; `tsc`+`eslint`+`vitest` are the real gate |
| `add-workspace` returns no id | Symbol/layout can't be applied to a new workspace | Contract amendment: print `{"id":…}` under `--json` |
| 15 commands in root search | Store-review pushback / user clutter | `subtitle: "SpacialShell"` on all; documented rationale; collapsible to one dropdown command |
| ⌘R would shadow Refresh | Muscle-memory misfires | Rename bound to ⌘E (`Keyboard.Shortcut.Common.Edit`) |

Sources: [Raycast manifest](https://developers.raycast.com/information/manifest), [store preparation](https://developers.raycast.com/basics/prepare-an-extension-for-store), [menu-bar commands](https://developers.raycast.com/api-reference/menu-bar-commands), [useExec](https://developers.raycast.com/utilities/react-hooks/useexec), [useCachedPromise](https://developers.raycast.com/utilities/react-hooks/usecachedpromise), [raycast/extensions aerospace](https://github.com/raycast/extensions/tree/main/extensions/aerospace), [raycast/github-actions](https://github.com/raycast/github-actions).

### Critical Files for Implementation
- /Users/alice/code/spacial-shell/docs/cli.md (new — the contract everything else depends on)
- /Users/alice/code/spacial-shell/raycast/package.json (manifest: commands, modes, interval, preferences)
- /Users/alice/code/spacial-shell/raycast/src/lib/spacialctl.ts (the single exec + error-mapping layer)
- /Users/alice/code/spacial-shell/raycast/src/lib/types.ts (state parsing, capability gating)
- /Users/alice/code/spacial-shell/raycast/src/switch.tsx (the flagship view; sets the pattern for the other three)