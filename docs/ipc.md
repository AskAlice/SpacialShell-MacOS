# Control socket

SpacialShell listens on a unix socket, `~/Library/Application Support/SpacialShell/spacialshell.sock`
(or `/tmp/spacialshell-<uid>.sock` when that path is too long), mode `0600`. Framing is
newline-delimited JSON: one request object per line, `{"id":1,"cmd":"state","args":{}}`, and one
`{"id":1,"v":1,"ok":true,"data":…}` reply per request. `spacialctl` is the reference client;
`spacialctl state` prints the `capabilities` a running shell supports.

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
