#!/bin/sh
# Debug run, straight out of .build. The TCC identity of this binary is its *path* — see README.
set -e
cd "$(dirname "$0")/.."
swift build
exec .build/debug/SpacialShell
