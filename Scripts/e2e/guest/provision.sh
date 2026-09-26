#!/bin/bash
# Runs INSIDE the golden guest, once, from golden.sh. Everything here is baked into the image
# every e2e run clones.
set -euo pipefail
say() { echo "provision: $*"; }

# SIP must be off: the per-run Accessibility grant (guest/run.sh) writes the system TCC.db.
if csrutil status | grep -q enabled; then
    say "SIP is enabled — per-run TCC grants cannot be written. Use a SIP-disabled image" >&2
    say "(Cirrus base images are), or boot 'tart run --recovery' and run 'csrutil disable'." >&2
    exit 1
fi

# Swift toolchain: the base image ships the Command Line Tools (Homebrew needs them).
if ! xcrun --find swift >/dev/null 2>&1; then
    say "installing Command Line Tools"
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    label="$(softwareupdate -l 2>/dev/null | sed -n 's/^\* Label: \(Command Line Tools.*\)$/\1/p' | tail -1)"
    sudo softwareupdate -i "$label" --agree-to-license
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
fi
say "$(swift --version 2>&1 | head -1)"

# Nothing may interrupt a scenario or change a screenshot: no sleep, no screen saver, no display
# sleep, no window restoration, no "reopen windows" prompt, a plain grey desktop.
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
defaults -currentHost write com.apple.screensaver idleTime 0
defaults write NSGlobalDomain NSQuitAlwaysKeepsWindows -bool false
defaults write com.apple.loginwindow TALLogoutSavesState -bool false
defaults write com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false
defaults write com.apple.TextEdit RichText -bool false
# ponytail: goes through System Events, so it times out like any Apple Event from the agent and
# the image keeps the default wallpaper. Harmless: references are recorded against that wallpaper.
osascript -e 'tell application "System Events" to tell every desktop to set picture to "/System/Library/Desktop Pictures/Solid Colors/Stone.png"' || true
defaults write com.apple.dock autohide -bool true && killall Dock || true

# Notes' first-run "Welcome to Notes" sheet (#154), which sat in the media recordings. Notes shows
# it until its container's prefs say it was shown for this macOS version: hasShownWelcomeScreen
# alone is not enough, lastShownStartupVersion-1 (the [major, minor, patch] it was last shown for)
# gates it. Measured on 26.6.2: pressing Continue writes exactly these two, and a clean prefs
# domain with just them opens straight to the notes list. Sandboxed, so the container's plist,
# through cfprefsd (`defaults` with a path); the container comes with the base image.
NOTES_PREFS="$HOME/Library/Containers/com.apple.Notes/Data/Library/Preferences/com.apple.Notes"
if [ -d "$(dirname "$NOTES_PREFS")" ]; then
    IFS=. read -r v_major v_minor v_patch <<<"$(sw_vers -productVersion)"
    defaults write "$NOTES_PREFS" hasShownWelcomeScreen -bool true
    defaults write "$NOTES_PREFS" lastShownStartupVersion-1 -array \
        -int "$v_major" -int "${v_minor:-0}" -int "${v_patch:-0}"
    say "Notes welcome marked as shown for $(sw_vers -productVersion)"
else
    say "no Notes container yet; its welcome sheet will show on first launch" >&2
fi

# Terminal opens clean (#158). The base image's Terminal was left running with the image's setup
# history on screen (`sudo spctl --global-disable` among it), and it sat in the Terminal row of the
# docs media. Measured on 26.6.2: loginwindow relaunches Terminal on every boot (TAL, even with
# TALLogoutSavesState off, since `tart stop` is not a logout), and Terminal restores its windows'
# scrollback from saved state, which macOS 26 keeps in talagent's daemon container under a UUID
# (ApplicationMapping.plist maps it to the bundle id), not in ~/Library/Saved Application State.
# So: quit Terminal, drop its saved state in both places and zsh's history and per-session files,
# and turn off both restoring mechanisms: Terminal's window restoration and Apple's zsh session
# save/restore. loginwindow still relaunches Terminal at boot (the snapshot references have its
# rail row), and with nothing to restore it opens one new window: a "Last login" line, a prompt.
killall Terminal 2>/dev/null && sleep 2 || true
rm -rf ~/.zsh_history ~/.zsh_sessions ~/.bash_history ~/.bash_sessions \
    "$HOME/Library/Saved Application State/com.apple.Terminal.savedState"
for c in "$HOME/Library/Daemon Containers"/*; do
    [ "$(sudo plutil -extract MCMMetadataIdentifier raw "$c/.com.apple.containermanagerd.metadata.plist" 2>/dev/null)" = com.apple.talagent ] || continue
    S="$c/Data/Library/Saved Application State"
    uuids="$(sudo python3 -c '
import plistlib, sys
try:
    m = plistlib.load(open(sys.argv[1], "rb"))
except (OSError, ValueError):
    sys.exit(0)
for app, uuid in zip(m[::2], m[1::2]):
    if isinstance(app, dict) and app.get("protected", {}).get("signingIdentifier") == "com.apple.Terminal":
        print(uuid)' "$S/ApplicationMapping.plist")"
    for uuid in $uuids; do sudo rm -rf "$S/$uuid.savedState"; done
done
defaults write com.apple.Terminal NSQuitAlwaysKeepsWindows -bool false
grep -qs SHELL_SESSIONS_DISABLE ~/.zshenv || echo 'export SHELL_SESSIONS_DISABLE=1   # no zsh session restore (#158)' >> ~/.zshenv
say "Terminal: history and saved state cleared, session restore off"

# The runner's grants: Accessibility and Screen Recording for tart-guest-agent, the responsible
# process of every `tart exec` command (its per-user LaunchAgent, `--run-agent`). Cirrus's image
# already has both; written again so the image does not depend on that. System and user DBs, as
# Cirrus does. No Apple Events rows: tccd ignores a written kTCCServiceAppleEvents row for the
# agent, prompts anyway (-1712 once the prompt times out) and overwrites the row with a denial.
# The runner does not need them: `fullscreen` goes straight through AX (axfullscreen.swift).
AGENT="$(realpath /opt/homebrew/bin/tart-guest-agent)"
USER_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"   # macOS ≤ 26 location
for db in "/Library/Application Support/com.apple.TCC/TCC.db" "$USER_DB"; do
    sudo sqlite3 "$db" "INSERT OR REPLACE INTO access
        (service, client_type, client, auth_value, auth_reason, auth_version,
         indirect_object_identifier_type, indirect_object_identifier) VALUES
        ('kTCCServiceAccessibility', 1, '$AGENT', 2, 0, 1, NULL, 'UNUSED'),
        ('kTCCServiceScreenCapture', 1, '$AGENT', 2, 0, 1, NULL, 'UNUSED');"
done

# Smoke: the runner's own tools answer without a prompt.
osascript -l JavaScript -e 'ObjC.import("CoreGraphics"); "cg ok"'
screencapture -x /tmp/provision.png && say "screencapture ok"

# golden.sh stops the guest seconds after this returns, and `tart stop` is not a clean shutdown:
# writes still in the guest's cache are lost. Measured (#158): the Terminal cleanup above, then
# `tart stop` at once, and the next boot had every file back (history, saved state, no ~/.zshenv).
sync
say "done"
