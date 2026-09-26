#!/usr/bin/env python3
"""Fail if a target imports a sibling target it does not declare as a direct dependency (#156).

SwiftPM only rebuilds a target when one of its *declared* dependencies' modules changes on disk.
A module reached transitively (ShellStoryTests -> SpacialShellUI -> SpacialShellKit) is visible to
`import`, but it is not a build input. The compiler also leaves a `.swiftmodule` untouched when its
interface did not change, so adding a stored property to a Kit struct rewrites
SpacialShellKit.swiftmodule and nothing else. The test target is never recompiled, and its objects
keep the struct's old layout. Outlined copy helpers ("outlined init with copy of Config") are weak
symbols, so the linker may keep the stale copy for every caller, and `swift test` segfaults in
`swift_retain`. `--explicit-target-dependency-import-check` accepts transitive modules, so it does
not catch this; this script does.

Checks package-local targets only: external products change only on a version bump, which rebuilds.
Usage: Scripts/check-target-deps.py   (exit 1 and a list of missing dependencies on failure)
"""
import json
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
manifest = json.loads(subprocess.run(
    ["swift", "package", "--package-path", str(root), "dump-package"],
    check=True, capture_output=True, text=True).stdout)

targets = manifest["targets"]
local = {t["name"] for t in targets}
# `import X`, `@testable import X`, `import struct X.Y`, `@preconcurrency import X`, ...
import_re = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*import\s+(?:(?:struct|class|enum|protocol|typealias|func|var|let)\s+)?(\w+)",
    re.M)

missing = []
for t in targets:
    declared = set()
    for dep in t["dependencies"]:
        for kind in ("byName", "target"):
            if kind in dep:
                declared.add(dep[kind][0])
    base = "Tests" if t["type"] == "test" else "Sources"
    path = root / (t.get("path") or f"{base}/{t['name']}")
    imported = set()
    for f in sorted(path.rglob("*.swift")):
        if "__Snapshots__" in f.parts:
            continue
        imported |= {m for m in import_re.findall(f.read_text(errors="replace"))}
    for m in sorted((imported & local) - declared - {t["name"]}):
        missing.append(f"{t['name']} imports {m} but does not list it in its dependencies")

if missing:
    print("Package.swift: undeclared target dependencies (#156, see docs/testing.md):", file=sys.stderr)
    for line in missing:
        print("  " + line, file=sys.stderr)
    sys.exit(1)
print(f"check-target-deps: {len(targets)} targets, every local import is a declared dependency.")
