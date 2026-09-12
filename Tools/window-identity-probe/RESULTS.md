# Issue #17 — measured results

Throwaway probe. Not shipped, not imported by any target, not in `Package.swift`.

```
swiftc -O probe.swift -o probe
./probe baseline 10     # sweep every AX window of every app, 10 rounds
./probe order 6         # does CG list order match AXWindows order?
./probe identical <pid> # force windows onto one frame, measure, restore
./probe move <pid>      # sample while an AX move is in flight
./probe park <pid>      # corner sliver, mostly off-screen
./probe hide <pid>      # hidden app (Cmd-H)
```

Ground truth is `_AXUIElementGetWindow`, re-declared locally via `@_silgen_name` so the probe does
not depend on the `PrivateApi` target.

## Predictors measured

| # | predictor | description |
|---|---|---|
| A | frame+title, layer 0 | pid + `kCGWindowLayer == 0`, exact frame (1pt), then title. The approach the issue names. |
| B | frame+title, any layer | as A without the layer filter |
| C | assignment + order tiebreak | per-app bipartite assignment; AX windows sharing a candidate set are paired to it in **onscreen** CG-list order |
| — | ordinal only | AX index vs CG index (control) |

## Pooled result — 858 standard-window observations, live desktop

| predictor | correct | wrong | refused |
|---|---|---|---|
| A frame+title (layer 0) | 556/858 = **64.8%** | 0 | 302 |
| B frame+title (any layer) | 556/858 = **64.8%** | 0 | 302 |
| C assignment + order tiebreak | 810/858 = **94.4%** | 0 | 48 |
| ordinal only | 228/858 = 26.6% | — | — |

Settled desktop, one window per app (N=170): A and C both reach 100% / 94.1%. The problem only
exists when one app owns several windows.

## Adversarial cases

| case | result |
|---|---|
| 6 Finder windows, identical title + identical frame (SpacialShell stacks them in one tile) | A refuses 6/6 every round; C correct 6/6 |
| 19 identical windows of one app | A 102/216 = 47.2%; C 210/216 = 97.2%, 0 wrong |
| **4 minimized windows, identical title + frame** | **C answers all four and is WRONG 16/16.** A refuses. |
| mid-move (AX frame vs CG bounds disagree) | 2/12 in-flight samples lost the moving window; A fell to 1/6 |
| corner-parked sliver | 6/6 correct — parked windows stay in the onscreen list |
| fullscreen window on its own Space | never resolved: `frame-tie`/`title-tie`, 0 answers in 5 samples |
| hidden app (Cmd-H) | 1/1 no answer — window leaves the onscreen list |
| app renaming its window live | 2/152 AX-vs-CG title disagreements, both produced failures; 16/152 = 10.5% no-answer during renaming |

## Structural facts

- **Ordering**: onscreen CG-list order matched AXWindows order **18/18** app samples, coverage
  60/60. `.optionAll` order matched only 12/18 and is not front-to-back. Order is the whole reason
  C beats A, and it exists *only* for windows in the onscreen list.
- **Pool pollution**: 383 layer-0 CG entries system-wide; only 30 named, only 17 onscreen. Mean pool
  per pid 9.8–19.5 entries of which 0.7–8.0 are onscreen. Anything short of exact frame equality
  collides at once.
- **Titles need a second TCC grant**: `kCGWindowName` is populated only with Screen Recording.
  `CGPreflightScreenCaptureAccess()` was `true` on this machine, so 1226/1227 rows had a CG title.
  The title nevertheless broke a tie in only **4/858 = 0.5%** of cases — frame does the work and
  order does the rest.
- AX and CG titles disagreed 49/1227 = 4.0% of the time at rest.
