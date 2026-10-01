# SpacialShell for Raycast

Control the [SpacialShell](https://github.com/AskAlice/spacial-shell) tiling window manager from Raycast.

## Requirements

- SpacialShell running (it serves a control socket at `~/Library/Application Support/SpacialShell/spacialshell.sock`)
- `spacialctl` on disk — bundled inside `SpacialShell.app/Contents/MacOS/`, or set a custom path in the extension preferences

## Commands

- **Switch to Workspace…** — list every display's workspaces by the title the shell shows ("Web browsing") with their windows, focused display first, and jump to one by id
- **Change Layout…** — pick a layout for the focused workspace (`spacialctl change-layout <id>`)
- **Switch to Window…** — every window, searchable by app and title, with a preview of the highlighted one (`spacialctl window-preview`, needs Screen Recording); also `spacialctl focus-window --app brave --title "pull requests"` from a script
- **No-view verbs** — cycle layout, focus workspace up/down, focus/move window in all four directions, toggle float, close window. Bind Raycast hotkeys to any of them.
- **Reload SpacialShell** — `spacialctl reload`: quits the shell (every window is put back on screen first) and starts the same SpacialShell.app again

## Known limits (v0)

- Against a shell older than `focus-workspace` (#131), Switch Workspace falls back to the focused screen's first ten rows.
- No window rows yet — the daemon's v0 `state` payload is workspaces only.

## Development

```sh
npm install
npm run dev        # hot-reload into Raycast
npm run typecheck
```
