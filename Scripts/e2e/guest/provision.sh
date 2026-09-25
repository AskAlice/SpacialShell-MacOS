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
say "done"
