#!/usr/bin/env python3
"""Render M2 chrome stills + looping showcases (webp / gif) for the README.

Usage: render-m2-media.py [scene ...] — no args renders every scene; naming scenes
(e.g. `render-m2-media.py general-showcase ui-showcase`) regenerates only those files.

spatialisation and tiling-showcase are no longer rendered: they are screen recordings from the
test VM now (#149, Scripts/e2e/scenarios/media/), and a render would overwrite them.
"""
from __future__ import annotations
import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 960, 600
RAIL, TOP, GAP, R = 48, 34, 8, 10
ACCENT = (10, 132, 255)
OUT = Path(__file__).resolve().parents[1] / "docs" / "media"
FPS = 14

UI = "/System/Library/Fonts/SFNS.ttf"
MONO = "/System/Library/Fonts/SFNSMono.ttf"
def font(size, mono=False):
    # SF on macOS; DejaVu (bundled with Pillow) keeps the pipeline runnable in Linux containers.
    candidates = [MONO if mono else UI, "/System/Library/Fonts/HelveticaNeue.ttc",
                  "DejaVuSansMono.ttf" if mono else "DejaVuSans.ttf"]
    for c in candidates:
        try: return ImageFont.truetype(c, size)
        except OSError: continue
    return ImageFont.load_default(size)

F12, F11, F10, F9 = font(12), font(11), font(10), font(9)
FCLK = font(11, True)

# Mirrors AppCategories.table in SpacialShellKit for the five apps these scenes use, so the
# rendered rail says the same thing the running app would.
CATEGORY = {
    "Cursor": "coding", "Terminal": "terminal", "Safari": "web browsing",
    "Mail": "productivity", "Notes": "productivity",
}
def summarise(names):
    """Most common category, ties broken by first appearance — same rule as the Swift side."""
    cats = [CATEGORY[n] for n in dict.fromkeys(names) if n in CATEGORY]
    if not cats: return None
    best = max(cats.count(c) for c in cats)
    return next(c for c in cats if cats.count(c) == best)

APPS = {
    "Cursor":   ((28, 30, 38), (90, 200, 250), "C"),
    "Terminal": ((12, 14, 16), (80, 220, 140), "T"),
    "Safari":   ((240, 242, 246), (20, 122, 255), "S"),
    "Mail":     ((236, 238, 242), (255, 90, 80), "M"),
    "Notes":    ((255, 244, 180), (230, 180, 40), "N"),
}

def lerp(a, b, t): return a + (b - a) * t
def ease(t): return t * t * (3 - 2 * t)
def mix(c, d, t): return tuple(int(lerp(c[i], d[i], t)) for i in range(len(c)))

def wallpaper():
    im = Image.new("RGB", (W, H))
    px = im.load()
    for y in range(H):
        t = y / (H - 1)
        c = mix((18, 22, 32), (38, 28, 48), t)
        for x in range(W):
            n = ((x * 17 + y * 31) % 13) - 6
            px[x, y] = (max(0, c[0] + n), max(0, c[1] + n), max(0, c[2] + n))
    return im.filter(ImageFilter.GaussianBlur(0.6))

WALL = wallpaper()

def rr(d, box, r, fill=None, outline=None, width=1):
    d.rounded_rectangle(box, r, fill=fill, outline=outline, width=width)

def layouts(kind, names, focused, box):
    x, y, w, h = box
    n = len(names)
    if n == 0: return []
    vis = [None] * n
    def col(i, k):
        cw = (w - GAP * (k - 1)) / k
        return (x + i * (cw + GAP), y, cw, h)
    if kind == "maximize" or n == 1:
        vis[focused] = (x, y, w, h)
    elif kind == "split":
        other = (focused + 1) % n
        vis[focused] = col(0, 2)
        vis[other] = col(1, 2)
    elif kind == "column":
        for i in range(n): vis[i] = col(i, n)
    elif kind == "half":
        rest = [i for i in range(n) if i != focused]
        vis[focused] = (x, y, (w - GAP) / 2, h)
        rh = (h - GAP * max(0, len(rest) - 1)) / max(1, len(rest))
        rx = x + (w - GAP) / 2 + GAP
        for j, i in enumerate(rest):
            vis[i] = (rx, y + j * (rh + GAP), (w - GAP) / 2, rh)
    else:  # grid
        cols = math.ceil(math.sqrt(n)); rows = math.ceil(n / cols)
        cw = (w - GAP * (cols - 1)) / cols
        rh = (h - GAP * (rows - 1)) / rows
        for i in range(n):
            r, c = divmod(i, cols)
            vis[i] = (x + c * (cw + GAP), y + r * (rh + GAP), cw, rh)
    return vis

def draw_win(base, name, box, glow=0.0):
    x, y, w, h = [int(v) for v in box]
    if w < 8 or h < 8: return
    bg, accent, letter = APPS[name]
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    if glow > 0.02:
        pad = 6
        a = int(220 * glow)
        rr(d, (x - pad, y - pad, x + w + pad, y + h + pad), R + 4, outline=(*ACCENT, a), width=3)
    rr(d, (x, y, x + w, y + h), R, fill=(*bg, 255))
    tb = 22
    rr(d, (x, y, x + w, y + tb + 8), R, fill=mix(bg, (255, 255, 255), 0.08) + (255,))
    d.rectangle((x, y + tb, x + w, y + tb + 1), fill=(255, 255, 255, 28))
    for i, c in enumerate(((255, 95, 86), (255, 189, 46), (39, 201, 63))):
        d.ellipse((x + 8 + i * 12, y + 7, x + 16 + i * 12, y + 15), fill=c)
    ink = (240, 242, 246) if bg[0] < 80 else (30, 32, 36)
    d.text((x + 48, y + 5), name, font=F10, fill=ink)
    # fake contents
    if name == "Cursor":
        for i in range(6):
            d.rectangle((x + 10, y + tb + 10 + i * 14, x + 28, y + tb + 20 + i * 14), fill=(70, 80, 96, 255))
            d.rectangle((x + 34, y + tb + 12 + i * 14, x + min(w - 12, 80 + i * 30), y + tb + 18 + i * 14), fill=(60, 140, 180, 200))
    elif name == "Terminal":
        d.text((x + 12, y + tb + 10), "alice@mac ~ %", font=F10, fill=accent)
        d.text((x + 12, y + tb + 26), "swift test", font=F10, fill=(200, 200, 200))
    elif name == "Safari":
        d.rectangle((x + 10, y + tb + 8, x + w - 10, y + tb + 24), fill=(220, 222, 226, 255))
        d.text((x + 18, y + tb + 10), "spacial.shell", font=F9, fill=(80, 80, 90))
        d.rectangle((x + 10, y + tb + 32, x + w - 10, y + h - 10), fill=(250, 251, 253, 255))
    else:
        d.rectangle((x + 10, y + tb + 10, x + w * 0.35, y + h - 10), fill=mix(bg, (0, 0, 0), 0.08) + (255,))
    # app badge
    d.rounded_rectangle((x + w - 28, y + 3, x + w - 6, y + 19), 4, fill=accent)
    d.text((x + w - 22, y + 4), letter, font=F10, fill=(255, 255, 255))
    base.alpha_composite(layer)

def draw_chrome(base, workspaces, active, layout, tabs, focused_tab):
    d = ImageDraw.Draw(base, "RGBA")
    # rail
    rail = Image.new("RGBA", (RAIL, H), (36, 36, 40, 210))
    base.paste(rail, (0, 0), rail)
    d.line((RAIL, 0, RAIL, H), fill=(255, 255, 255, 28))
    # search
    d.ellipse((12, 12, 36, 36), outline=(200, 200, 205, 180), width=2)
    d.line((32, 32, 38, 38), fill=(200, 200, 205, 180), width=2)
    # workspace rows: app icons + window count + category label, as the shell draws them
    y0 = 52
    row_h = 44
    for i, (_name, apps) in enumerate(workspaces):
        x, y = 6, y0 + i * row_h
        on = i == active
        fill = (*ACCENT, 46) if on else (255, 255, 255, 14)
        rr(d, (x, y, RAIL - 6, y + row_h - 6), 8, fill=fill)
        seen = list(dict.fromkeys(apps))
        for j, app in enumerate(seen[:4]):
            accent = APPS[app][1] if app in APPS else (160, 160, 165)
            rr(d, (x + 7 + j * 19, y + 7, x + 7 + j * 19 + 16, y + 23), 4, fill=(*accent, 255))
        if len(seen) > 4:
            d.text((x + 7 + 4 * 19, y + 10), f"+{len(seen) - 4}", font=F9, fill=(210, 210, 215, 200))
        d.text((RAIL - 22, y + 10), str(len(apps)), font=F9, fill=(230, 230, 235, 200) if on else (180, 180, 185, 190))
        label = summarise(apps)
        if label:
            d.text((x + 7, y + 26), label, font=F9,
                   fill=(235, 235, 240, 230) if on else (185, 185, 190, 200))
    plus_y = y0 + len(workspaces) * row_h
    rr(d, (6, plus_y, RAIL - 6, plus_y + row_h - 6), 8, fill=(255, 255, 255, 10))
    d.text((14, plus_y + 10), "+  New", font=F11, fill=(180, 180, 185, 210))
    # settings cog (primary display only), and the stacked clock above it
    d.text((14, H - 56), "21", font=FCLK, fill=(230, 230, 235, 230))
    d.text((14, H - 42), "14", font=FCLK, fill=(230, 230, 235, 230))
    d.ellipse((14, H - 26, 28, H - 12), outline=(200, 200, 205, 180), width=2)
    d.ellipse((18, H - 22, 24, H - 16), fill=(200, 200, 205, 180))
    # top bar
    bar = Image.new("RGBA", (W - RAIL, TOP), (44, 44, 48, 200))
    base.paste(bar, (RAIL, 0), bar)
    d.line((RAIL, TOP, W, TOP), fill=(255, 255, 255, 28))
    tx = RAIL + 8
    for i, name in enumerate(tabs):
        tw = min(160, max(88, 28 + len(name) * 7))
        on = i == focused_tab
        rr(d, (tx, 4, tx + tw, 30), 6, fill=(*ACCENT, 46) if on else (255, 255, 255, 16))
        _, accent, letter = APPS[name]
        d.rounded_rectangle((tx + 8, 8, tx + 24, 24), 4, fill=accent)
        d.text((tx + 11, 9), letter, font=F9, fill=(255, 255, 255))
        d.text((tx + 28, 9), name, font=F12, fill=(245, 245, 247) if on else (180, 180, 186))
        tx += tw + 8
    # layout glyph
    lx, ly = W - 36, 5
    rr(d, (lx, ly, lx + 24, ly + 24), 6, fill=(255, 255, 255, 16))
    marks = {"maximize": [(4, 6, 16, 14)], "split": [(3, 6, 8, 14), (12, 6, 17, 14)],
             "column": [(2, 6, 6, 14), (9, 6, 13, 14), (16, 6, 20, 14)],
             "half": [(3, 6, 10, 14), (13, 6, 20, 9), (13, 11, 20, 14)],
             "grid": [(3, 6, 9, 11), (12, 6, 18, 11), (3, 13, 9, 18), (12, 13, 18, 18)]}
    for (a, b, c, e) in marks.get(layout, marks["maximize"]):
        d.rectangle((lx + a, ly + b, lx + c, ly + e), outline=(220, 220, 225, 220), width=1)

def content_box():
    return (RAIL + GAP, TOP + GAP, W - RAIL - GAP * 2, H - TOP - GAP * 2)

def frame(workspaces, active, layout, tabs, focused, glow=1.0):
    im = WALL.copy().convert("RGBA")
    names = workspaces[active][1]
    vis = layouts(layout, names, focused, content_box())
    # parked first (none drawn), then visible, glow last
    for i, box in enumerate(vis):
        if box and i != focused: draw_win(im, names[i], box, 0)
    if focused < len(vis) and vis[focused]:
        draw_win(im, names[focused], vis[focused], glow)
    draw_chrome(im, workspaces, active, layout, tabs, focused)
    return im.convert("RGB")

def tween(a, b, n):
    for i in range(n):
        yield ease(i / max(1, n - 1))

def hold(im, n):
    return [im] * n

def encode(frames, stem):
    OUT.mkdir(parents=True, exist_ok=True)
    ms = int(1000 / FPS)
    webp, gif = OUT / f"{stem}.webp", OUT / f"{stem}.gif"
    frames[0].save(webp, "WEBP", save_all=True, append_images=frames[1:],
                   duration=ms, loop=0, quality=72, method=4)
    frames[0].save(gif, "GIF", save_all=True, append_images=frames[1:],
                   duration=ms, loop=0, optimize=True)
    print(f"{stem}: {webp.stat().st_size//1024}k webp, {gif.stat().st_size//1024}k gif, {len(frames)}f")

def still(im, stem):
    OUT.mkdir(parents=True, exist_ok=True)
    im.save(OUT / f"{stem}.webp", "WEBP", quality=86, method=6)
    im.save(OUT / f"{stem}.png")

# One fixture world for every scene.
CODE = ("Code", ["Cursor", "Terminal", "Safari"])
BROWSE = ("Browse", ["Safari", "Mail"])
NOTES = ("Notes", ["Notes"])
WS = [CODE, BROWSE, NOTES]

def frame_zen(workspaces, active, layout, tabs, focused, glow=1.0):
    """Zen mode: no chrome, the panel edges given back to the windows."""
    im = WALL.copy().convert("RGBA")
    names = workspaces[active][1]
    vis = layouts(layout, names, focused, (GAP, GAP, W - GAP * 2, H - GAP * 2))
    for i, box in enumerate(vis):
        if box and i != focused: draw_win(im, names[i], box, 0)
    if focused < len(vis) and vis[focused]:
        draw_win(im, names[focused], vis[focused], glow)
    return im.convert("RGB")

def draw_overview(im, query, highlight=None, t=1.0):
    """The Fn+Tab overview: search field over Windows + Applications app-chip grids."""
    base = im.convert("RGBA")
    d = ImageDraw.Draw(base, "RGBA")
    dim = Image.new("RGBA", (W, H), (8, 10, 14, int(110 * t)))
    base.alpha_composite(dim)
    ow, oh = 460, 262
    ox, oy = (W - ow) // 2, int(100 - 14 * t)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    rr(ld, (ox, oy, ox + ow, oy + oh), 14, fill=(40, 42, 50, int(242 * t)), outline=(255, 255, 255, int(40 * t)))
    rr(ld, (ox + 14, oy + 14, ox + ow - 14, oy + 44), 8, fill=(66, 70, 82, 160))
    ld.ellipse((ox + 24, oy + 21, ox + 36, oy + 33), outline=(190, 192, 200, 220), width=2)
    ld.text((ox + 46, oy + 21), query if query else "Type to search…", font=F12,
            fill=(240, 242, 246, 255) if query else (150, 152, 160, 255))
    windows = [n for n in ("Cursor", "Terminal", "Safari") if not query or query.lower() in n.lower()]
    apps = [n for n in APPS if not query or query.lower() in n.lower()]
    cw = 76
    ld.text((ox + 18, oy + 54), "WINDOWS", font=F9, fill=(150, 153, 162, 255))
    for i, name in enumerate(windows):
        cx, cy = ox + 18 + i * (cw + 8), oy + 68
        on = highlight == name
        rr(ld, (cx, cy, cx + cw, cy + 74), 8, fill=(*ACCENT, 110) if on else (255, 255, 255, 18))
        _bg, accent, letter = APPS[name]
        ld.rounded_rectangle((cx + cw // 2 - 14, cy + 8, cx + cw // 2 + 14, cy + 36), 7, fill=accent)
        ld.text((cx + cw // 2 - 4, cy + 14), letter, font=F12, fill=(255, 255, 255))
        ld.text((cx + 8, cy + 44), name[:9], font=F10, fill=(235, 236, 240, 255))
        ld.text((cx + 8, cy + 58), "Code", font=F9, fill=(150, 153, 162, 255))
    ld.text((ox + 18, oy + 154), "APPLICATIONS", font=F9, fill=(150, 153, 162, 255))
    for i, name in enumerate(list(APPS)[:5]):
        cx, cy = ox + 18 + i * (cw + 8), oy + 168
        if name not in apps: continue
        rr(ld, (cx, cy, cx + cw, cy + 66), 8, fill=(255, 255, 255, 18))
        _bg, accent, letter = APPS[name]
        ld.rounded_rectangle((cx + cw // 2 - 14, cy + 6, cx + cw // 2 + 14, cy + 34), 7, fill=accent)
        ld.text((cx + cw // 2 - 4, cy + 12), letter, font=F12, fill=(255, 255, 255))
        ld.text((cx + 8, cy + 42), name[:9], font=F10, fill=(235, 236, 240, 255))
    base.alpha_composite(layer)
    return base.convert("RGB")

def draw_cheatsheet(im):
    """The hold-Fn cheat sheet: grouped bindings, centred card."""
    base = im.convert("RGBA")
    d = ImageDraw.Draw(base, "RGBA")
    dim = Image.new("RGBA", (W, H), (8, 10, 14, 90))
    base.alpha_composite(dim)
    groups = [
        ("Navigate", [("Workspace up", "Fn W"), ("Workspace down", "Fn S"),
                      ("Window left", "Fn A"), ("Window right", "Fn D")]),
        ("Move & tiling", [("Move left", "Fn ⇧A"), ("Move right", "Fn ⇧D"),
                           ("To workspace above", "Fn ⇧W"), ("Toggle float", "Fn G")]),
        ("App", [("Cycle layout", "Fn Spc"), ("Zen mode", "Fn Esc"),
                 ("Overview", "Fn Tab"), ("Open config", "Fn ,")]),
    ]
    colw, pad, gap = 214, 18, 20
    cw = pad * 2 + len(groups) * colw + (len(groups) - 1) * gap
    ch = 152
    cx, cy = (W - cw) // 2, (H - ch) // 2
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    rr(ld, (cx, cy, cx + cw, cy + ch), 14, fill=(40, 42, 50, 242), outline=(255, 255, 255, 40))
    for g, (title, items) in enumerate(groups):
        gx = cx + pad + g * (colw + gap)
        ld.text((gx, cy + 14), title, font=F11, fill=(150, 153, 162, 255))
        for i, (label, key) in enumerate(items):
            yy = cy + 40 + i * 25
            ld.text((gx, yy), label, font=F11, fill=(235, 236, 240, 255))
            kw = ld.textlength(key, font=FCLK)
            ld.text((gx + colw - kw, yy), key, font=FCLK, fill=(170, 173, 182, 255))
    base.alpha_composite(layer)
    return base.convert("RGB")

def scene_hero():
    still(frame(WS, 0, "split", CODE[1], 0, 1), "hero-still")

def scene_general():
    code, browse, notes = CODE, BROWSE, NOTES
    ws = WS

    # general showcase: split → focus right → workspace down → back
    seq = []
    seq += hold(frame(ws, 0, "split", code[1], 0, 1), 10)
    for t in tween(0, 1, 8):
        seq.append(frame(ws, 0, "split", code[1], 0, 1 - t))
    seq += hold(frame(ws, 0, "split", code[1], 1, 0), 2)
    for t in tween(0, 1, 8):
        seq.append(frame(ws, 0, "split", code[1], 1, t))
    seq += hold(frame(ws, 0, "split", code[1], 1, 1), 8)
    for t in tween(0, 1, 10):
        seq.append(frame(ws, 0 if t < 0.5 else 1, "maximize", (code[1] if t < 0.5 else browse[1]), 0, 1))
    seq += hold(frame(ws, 1, "maximize", browse[1], 0, 1), 10)
    for t in tween(0, 1, 10):
        seq.append(frame(ws, 1 if t < 0.5 else 0, "split", (browse[1] if t < 0.5 else code[1]), 0, 1))
    encode(seq, "general-showcase")

def scene_interface():
    ws, code, browse, notes = WS, CODE, BROWSE, NOTES
    seq = []
    for active, tabs, foc, lay in (
        (0, code[1], 0, "split"),
        (0, code[1], 1, "split"),
        (0, code[1], 2, "column"),
        (1, browse[1], 0, "maximize"),
        (2, notes[1], 0, "maximize"),
        (0, code[1], 0, "split"),
    ):
        seq += hold(frame(ws, active, lay, tabs, foc, 1), 12)
    encode(seq, "interface-showcase")

def scene_ui():
    """UI showcase: overview opens on Fn+Tab, search filters, Enter jumps; hold-Fn cheat
    sheet; Fn+Esc Zen round trip. Renders only what is implemented on this branch."""
    ws, code = WS, CODE
    base = frame(ws, 0, "split", code[1], 0, 1)
    seq = hold(base, 12)
    for t in tween(0, 1, 6):
        seq.append(draw_overview(base, "", t=t))
    seq += hold(draw_overview(base, ""), 10)
    seq += hold(draw_overview(base, "sa"), 8)
    seq += hold(draw_overview(base, "sa", highlight="Safari"), 8)
    focused = frame(ws, 0, "maximize", code[1], 2, 1)
    seq += hold(focused, 12)
    seq += hold(draw_cheatsheet(focused), 18)
    seq += hold(focused, 6)
    zen = frame_zen(ws, 0, "maximize", code[1], 2, 0)
    for t in tween(0, 1, 5):
        seq.append(Image.blend(focused, zen, t))
    seq += hold(zen, 12)
    for t in tween(0, 1, 5):
        seq.append(Image.blend(zen, base, t))
    seq += hold(base, 8)
    encode(seq, "m2-ui-showcase")

SCENES = {
    "hero-still": scene_hero,
    "general-showcase": scene_general,
    "interface-showcase": scene_interface,
    "ui-showcase": scene_ui,
}

def main(argv):
    names = argv or list(SCENES)
    unknown = [n for n in names if n not in SCENES]
    if unknown:
        sys.exit(f"unknown scene(s): {', '.join(unknown)}; have: {', '.join(SCENES)}")
    for n in names:
        SCENES[n]()

if __name__ == "__main__":
    main(sys.argv[1:])
