#!/bin/sh
# Install build/SpacialShell.app to /Applications and, optionally, restart the shell on it.
#
#   Scripts/install.sh                  copy it in; a running shell keeps running (the pre-commit hook)
#   Scripts/install.sh --relaunch       copy it in and restart the shell on it (make install)
#   Scripts/install.sh --relaunch-only  restart the installed shell, no copy (make relaunch)
#
# #184: while no shell runs, every bound chord reaches macOS instead: Globe+S opens Type to Siri.
# So a restart keeps that gap to the bare quit-then-launch. The new bundle is copied in *before* the
# old shell is asked to quit, the exit is polled every 50 ms rather than slept for, and the new app
# is opened the moment the old process is gone. Deleting the old bundle waits until after the launch.
set -e
cd "$(dirname "$0")/.."

DEST=/Applications/SpacialShell.app
SRC=build/SpacialShell.app
STAGED=/Applications/.SpacialShell.app.staged
OLD=/Applications/.SpacialShell.app.old

mode=${1:-install}
case "$mode" in
    install|--relaunch|--relaunch-only) ;;
    *) echo "usage: $0 [--relaunch | --relaunch-only]" >&2; exit 2 ;;
esac

running() { pgrep -x SpacialShell >/dev/null 2>&1; }

stage() {
    [ -d "$SRC" ] || { echo "install: no $SRC; run Scripts/bundle.sh first" >&2; exit 1; }
    rm -rf "$STAGED"
    cp -R "$SRC" "$STAGED"
}

# Renames, not a copy over: the bundle at $DEST is never half-copied, and a shell still running
# from the old one keeps its files, moved aside to $OLD, until it exits. When a shell is running and
# $OLD already exists, that is where it runs from (an earlier install moved it there), so $OLD is
# kept and the never-launched bundle at $DEST is the one replaced.
swap() {
    if running && [ -e "$OLD" ]; then
        rm -rf "$DEST"
    else
        rm -rf "$OLD"
        if [ -e "$DEST" ]; then mv "$DEST" "$OLD"; fi
    fi
    mv "$STAGED" "$DEST"
}

# The moved-aside bundle, once no shell can be running from it.
tidy() { running || rm -rf "$OLD"; }

# Quitting restores every managed window before exit (spec 7.4), bounded by the termination gate's
# budgets (about 11 s all told), so allow 12 s. SIGTERM, like `spacialctl quit`, goes through that gate.
quit_and_wait() {
    running || return 0
    killall SpacialShell 2>/dev/null && echo "install: stopping the running instance" || true
    i=0
    while running; do
        i=$((i + 1))
        if [ "$i" -gt 240 ]; then
            echo "install: SpacialShell is still quitting after 12 s; open $DEST once it has gone" >&2
            return 1
        fi
        sleep 0.05
    done
}

# LaunchServices can refuse (-600) for a moment after the old instance goes: ask again at once.
launch() {
    i=0
    until open "$DEST" 2>/dev/null; do
        i=$((i + 1))
        if [ "$i" -ge 50 ]; then open "$DEST"; return; fi
        sleep 0.1
    done
}

case "$mode" in
    install)
        stage
        swap
        tidy
        ;;
    --relaunch)
        stage
        # Still quitting after the budget: install anyway, leave the old bundle to the process
        # still running from it, and don't launch a second shell it would refuse (#131).
        if ! quit_and_wait; then swap; exit 1; fi
        swap
        launch
        rm -rf "$OLD"
        ;;
    --relaunch-only)
        quit_and_wait
        launch
        rm -rf "$OLD"
        ;;
esac
