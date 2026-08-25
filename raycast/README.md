# SpacialShell for Raycast

Control the [SpacialShell](https://github.com/AskAlice/spacial-shell) tiling window manager from Raycast.

## Requirements

- SpacialShell running (it serves a control socket at `~/Library/Application Support/SpacialShell/spacialshell.sock`)
- `spacialctl` on disk — bundled inside `SpacialShell.app/Contents/MacOS/`, or set a custom path in the extension preferences

## Commands

- **Switch Workspace** — list the current screen's workspaces (categories) and jump to one
- **No-view verbs** — cycle layout, focus workspace up/down, focus/move window in all four directions, toggle float, close window. Bind Raycast hotkeys to any of them.

## Known limits (v0)

- Switch Workspace targets the focused screen only; jump to another screen first (`Fn+]`).
- No window rows yet — the daemon's v0 `state` payload is workspaces only.

## Development

```sh
npm install
npm run dev        # hot-reload into Raycast
npm run typecheck
```
