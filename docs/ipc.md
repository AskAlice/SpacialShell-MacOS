# Control socket

SpacialShell listens on a unix socket, `~/Library/Application Support/SpacialShell/spacialshell.sock`
(or `/tmp/spacialshell-<uid>.sock` when that path is too long), mode `0600`. Framing is
newline-delimited JSON: one request object per line, `{"id":1,"cmd":"state","args":{}}`, and one
`{"id":1,"v":1,"ok":true,"data":…}` reply per request. `spacialctl` is the reference client;
`spacialctl state` prints the `capabilities` a running shell supports.

## One shell per socket (#131)

At launch the shell connects to the socket before touching it. If another SpacialShell answers,
the new one prints "SpacialShell is already running" and exits 1 before it moves a window. A socket
file nobody answers on (the last shell crashed) is stale: it is removed and replaced. Quit the
running shell first with `spacialctl quit` or the rail menu's Quit.

## Verbs

`capabilities` (in `state`) lists every verb below and the `state` payload features
(`window-rows`, `layouts`, `problems`), and nothing else. A client checks it before using a verb a
shell may be too old for. The list only grows: `v` stays 1 and a new verb adds a capability string.

| `cmd` | `args` | Does |
|---|---|---|
| `version` | — | `data.version` |
| `state` | — | the model: screens, workspaces, windows, layouts, problems, `capabilities` |
| `run` | `command` | a bound command by name, exactly like its hotkey (`spacialctl run focus-workspace-2`) |
| `set-layout` | `layout`, `workspace?` | a workspace's layout; the focused one when `workspace` is absent |
| `quit` | — | quits through the same path as the rail menu's Quit: every window is put back first. The reply comes before the shell stops; its process exits a few seconds later. |
| `subscribe` | — | the event stream (below) |

**Id-addressed verbs.** These are the shell's own clicks and drags with wire names. Each names its
target outright, so it works on any display without moving focus there first, and on any row, not
only the first ten. A workspace is its `id` from `state`. A window is `{"id": <window id>, "pid":
<pid>}`, as in `state` and the events.

| `cmd` | `args` | Same as |
|---|---|---|
| `focus-workspace` | `workspace` | a rail click: that workspace becomes active on its display, and that display gets focus |
| `focus-window` | `window` | a tab click; a minimized or hidden window is brought back |
| `close-window` | `window` | a tab's close button |
| `toggle-float` | `window` | the tab menu's Float / Tile |
| `recover-window` | `window` | the rail tray: bring back a window no tab reaches |
| `move-window` | `window`, `workspace`, `follow?` | a tab dropped on a rail row. `follow` (default `true`) switches to it as the keyboard does; `false` only re-files it, like a drop |
| `move-window-before` | `window`, `before?` | a tab dragged within the bar: before `before`, or at the row's end when it is absent or `null` |
| `move-app` | `window`, `workspace` | ⌥-drop: all of that window's app to the workspace, without following |
| `swap-window` | `window`, `onto` | a window dropped on a tile: same row, they swap; another row, it takes that slot |
| `move-workspace` | `workspace`, `index` | a rail tile dragged within its display; `index` is 0-based, as `activeIndex` in `state` |
| `remove-workspace` | `workspace` | the workspace menu's Remove |
| `set-symbol` | `workspace`, `symbol` | the workspace menu's icon (an SF Symbol name) |
| `set-category` | `workspace`, `category` | the workspace menu's category: `web`, `coding`, `terminal`, `communication`, `media`, `design`, `productivity`, `utilities`, or `null` to clear. The argument is required, so leaving it out cannot clear a category |
| `set-split-columns` | `workspace`, `columns` | the layout popover's split −/+ |

The reply is the `run` reply: `data.outcome` is `ok`, `noop` (with `reason`), or `failed`. **An id
that names nothing** (a workspace or window that is gone, or a string that is not an id at all) is
`ok: false`, `data.error` `unknown-workspace` or `unknown-window`, and `spacialctl` exits 1. A
missing or ill-typed argument is `ok: false` with a message that names it.

The shell checks every id when it runs the command, so a keystroke landing between your `state`
and your request can at worst turn it into `unknown-…`, never move the wrong thing.

```sh
ws=$(spacialctl state | jq -r '.screens[1].workspaces[0].id')
spacialctl focus-workspace "$ws"                     # a row on the second display
spacialctl call move-window "{\"window\":{\"id\":4242,\"pid\":501},\"workspace\":\"$ws\",\"follow\":false}"
spacialctl quit
```

`spacialctl call <cmd> [<json-object>]` sends any verb with its args as written.

## Event subscription (`subscribe`, #117)

`{"id":1,"cmd":"subscribe"}` turns the connection into an event stream. The shell replies
`{"id":1,"v":1,"ok":true}`, then sends one line per event, each `{"v":1,"event":<name>,"data":…}`:

1. **One `shell` event** first: `data` is the full current `ShellSnapshot` (screens, workspaces,
   windows, focus). This is the baseline; it is not repeated.
2. **Only changes after that**, in this order within one update:

| `event` | `data` |
|---|---|
| `workspace-activated` | `display`, `workspace` (uuid), `name`, `symbol`, `previous` (uuid, absent the first time) |
| `workspaces-changed` | `display`, `workspaces`: that display's full workspace rows (names, layout, `isActive`, `windowCount`, …) |
| `window-adopted` | `display`, `window`: the full window row (`window` `{id,pid}`, `workspaceId`, `title`, `appName`, `bundleID`, …) |
| `window-moved` | `window` `{id,pid}`, `from`, `to` (workspace uuids, absent for a visitor), `fromDisplay`, `display` |
| `window-title-changed` | `window` `{id,pid}`, `title` |
| `window-closed` | `window` `{id,pid}`, `pid` |
| `focus-changed` | `display`, and when a window has focus: `window`, `workspaceId`, `title`, `appName`, `bundleID` |

The stream is additive to the wire: `v` stays 1, new event names and new fields may appear, and a
client ignores what it does not know. The requests the connection sent before `subscribe` are
still answered.

```sh
spacialctl subscribe | jq -c 'select(.event == "workspace-activated") | .data.name'
```

`spacialctl subscribe` flushes after every line. `| head -1` kills it with SIGPIPE (exit 141);
that is normal for a streaming CLI.

**Slow clients are dropped.** The shell never waits on a subscriber: each has a fixed kernel
buffer (1 MiB), and a write that would not fit closes the connection. Deltas cannot be skipped
safely, so dropping is the only honest option. A client that sees EOF reconnects and starts from a
fresh `shell` baseline. `spacialctl subscribe` exits 3 with "connection closed" when that happens
or when the shell quits.

**Privacy.** Events carry window titles and app names, the same ones the tabs show (#110). The
socket is local and readable only by your user, so nothing leaves the machine through it. Treat a
captured stream like a screenshot of your tab bar. Telemetry is separate: spans record only the
request verb (`ipc.cmd = "subscribe"`), never a title or any event payload.

## Resetting saved state (`reset-state`, #139)

`{"id":1,"cmd":"reset-state"}` deletes `state.json` and stops the shell writing it until it next
launches, which then starts fresh. The windows stay where they are for the rest of the session.
The reply's `data.message` says what happened; `spacialctl reset-state` prints it. It is the same
action as the settings window's **Reset saved state…** button; see
[config: resetting saved state](config.md#resetting-saved-state).
