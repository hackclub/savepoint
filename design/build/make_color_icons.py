"""Writes Save Point's colour icons into design/system/icons-color: MingCute icons redrawn as chunky, saturated stickers,
the way Armand coloured the hourglass (app/assets/images/save_point/hours.png).

Each icon is a layered 24 by 24 SVG built from the MingCute path and a small spec (SPECS below):

1. a rim: the silhouette stroked in a tone a little darker than the body, same hue, round joins, so the shape gets chunky
2. the body: the silhouette filled with a top-lit gradient that stays saturated (light at the top, deeper at the bottom)
3. a thin bevel: a lighter line just inside the edge, strongest at the top
4. details: the holes MingCute cuts out (a gamepad's buttons, a clock's hands) are not see-through. Each is filled in a
   strongly contrasting colour (cream on a dark body, a deep colour on a light one) with a faint shade along its top
   edge, so it reads as set in. A detail can be scaled up when it is too small to read at 48px (the rocket's window)
5. optionally, flat shapes under the parts, filling the gaps between them (the gift's ribbon, the house's door)

Run from the repository root: python3 design/build/make_color_icons.py (make.py runs it too). Then bin/rails style_sheet:sync.
"""
import json, pathlib, re
import tokens

ROOT = pathlib.Path(__file__).resolve().parent.parent / "system" / "icons-color"
MINGCUTE = pathlib.Path.home() / "Documents/Developer/hackatime-editor/node_modules/@iconify-json/mingcute/icons.json"

# Light-theme token values (tokens.py), by name.
T = {name: light for name, light, _dark, _usage in tokens.COLORS}


def palette(hi, mid, lo, rim, bevel, edge):
    """One sticker colouring: body gradient hi → mid → lo, the rim's tone, the bevel's highlight, and the shade along
    the top edge of a detail filled with this palette."""
    return dict(hi=hi, mid=mid, lo=lo, rim=rim, bevel=bevel, edge=edge)


PALETTES = {
    # Armand's hourglass: yellow to gold, a brown-orange rim, a paler bevel. Its bulbs use "orange".
    "gold": palette("#ffe95c", T["gold"], "#f5a300", "#c0702a", "#fff5a8", "#b4651a"),
    "orange": palette("#ffb13a", "#ff8a1e", "#ef5f10", "#b9651c", "#ffd08a", "#a0400a"),
    "royal": palette("#6f88f0", "#3b58d8", "#2440b8", T["royal-lip"], "#b9c6ff", "#15236f"),
    "mint": palette("#6ee6a8", T["mint"], "#16985e", "#0f6b42", "#c8f7df", "#0a4a2c"),
    "violet": palette("#a98cff", T["violet"], T["violet-ink"], "#40279c", "#d9ccff", "#352080"),
    "coral": palette("#ff8aa0", "#f54b6c", "#d92a50", "#a3203f", "#ffd0d9", "#8a1a36"),
    "copper": palette(T["bronze-hi"], T["bronze"], T["copper"], "#7a3608", "#ffe3c9", "#6a2e05"),
    # Light stickers, and the light details on dark bodies.
    "cream": palette("#fffdf0", "#fff3cc", "#ffe6a8", "#d9a74a", "#ffffff", "#c98a2a"),
    "white": palette("#ffffff", "#f4f6ff", "#dfe6fc", T["line-strong"], "#ffffff", T["line-lip"]),
    "sky": palette("#d6ecff", "#8ec8ff", "#4f9ef0", "#2a63b8", "#ffffff", "#234f94"),
}

# Details on a coloured body: white, or a pale tint of the body's own hue. Each keeps the body's rim tone for the faint shade along its
# top edge and for the ribbon's outline, so a light detail never loses its edge against the body.
PALE = dict(mint=("#e3fbef", "#c2f3da", "#9be8c0"), royal=("#eaefff", "#ccd7ff", "#a8baff"),
            violet=("#f1ecff", "#dccfff", "#c3b0ff"), gold=("#fffbe4", "#fff0ae", "#ffdf72"))
for _hue, (_hi, _mid, _lo) in PALE.items():
    _body = PALETTES[_hue]
    PALETTES[_hue + "-white"] = palette("#ffffff", "#ffffff", "#eef1fb", _body["rim"], "#ffffff", _body["edge"])
    PALETTES[_hue + "-pale"] = palette(_hi, _mid, _lo, _body["rim"], "#ffffff", _body["edge"])

RIM = 1.0     # How far the rim shows outside the body, in icon units (a 24-unit icon). It also closes 2-unit gaps.
BEVEL = 0.6   # The bevel band's width, inside the edge.
EDGE = 0.7    # The shaded band across the top of a detail.

# name: how to colour it.
#   body: palette for the silhouette, or {subpath index: palette} when parts differ
#   detail: palette for the holes, or {subpath index: palette}
#   raised: palette for a shape inside a hole (the gamepad's d-pad dot), filled flat in its "lo" tone
#   depth: overrides for the automatic nesting (0 body, 1 detail, 2 raised), by subpath index
#   scale: {subpath index: factor} grows a detail about its centre; it is clipped to the body
#   rim: (palette, width) when the rim is not the body's own (none use it now)
#   under: [(palette, path d)] flat shapes drawn over the rim and under the parts, filling gaps between them
#   ribbon: a ribbon wrapped over the parts (the gift's): bands clipped to the bodies, shaded like them, a knot where they cross
#   line: draw a MingCute line icon's stroke as the body (the hourglass), at this stroke width
#   bulbs: with line, the closed regions inside the stroke, as separate paths, each a detail
SPECS = {
    # The four landing steps are one set: a journey from cool to gold, each in its own palette, built the same way (own-hue
    # rim, top-lit body, white details). Gold is kept for the last, the prize, so it stands out.
    "game-2-fill": dict(body="mint", detail="mint-white", raised="mint"),
    "time-fill": dict(body="royal", detail="royal-white"),
    "rocket-fill": dict(body="violet", detail="violet-white", scale={1: 1.35, 2: 1.5}),
    "gift-fill": dict(body="gold", detail="gold-white",
                      ribbon=dict(pal="gold-white", knot="orange", cx=12, cy=8.9, hband=(7.7, 10.2), top=7.4, bottom=21,
                                  fill=["M11 8h2v3h-2z", "M11 11h2v10h-2z"])),
    "trophy-fill": dict(body="gold", detail="cream"),
    "flag-1-fill": dict(body="coral"),
    "shopping-bag-1-fill": dict(body="violet", detail="cream"),
    "calendar-fill": dict(body={0: "white", 1: "coral"}),
    "user-3-fill": dict(body="mint"),
    "save-2-fill": dict(body="royal", detail={1: "cream", 2: "gold"}),
    "question-fill": dict(body="violet", detail="cream"),
    "information-fill": dict(body="royal", detail="cream"),
    "home-4-fill": dict(body="mint", under=[("cream", "M10 15h4v6h-4z")]),
    "hourglass": dict(
        body="gold", detail="orange", line=3.2, source="sandglass-line",
        bulbs=["M12 12L16.219 14.813A4 4 0 0 1 18 18.14V20A1 1 0 0 1 17 21H7A1 1 0 0 1 6 20V18.14A4 4 0 0 1 7.781 14.812Z",
               "M12 12L16.219 9.187A4 4 0 0 0 18 5.86V4A1 1 0 0 0 17 3H7A1 1 0 0 0 6 4V5.86A4 4 0 0 0 7.781 9.187Z"]),
}

# Sticker versions of these would not help: they are UI glyphs that sit in text or on buttons.
SKIPPED = {"down-fill": "an arrow in a control", "close-fill": "a dismiss glyph in a control", "play-fill": "sits on the CTA button, in its text colour"}

NUMBER = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
ARGS = dict(M=2, L=2, H=1, V=1, C=6, S=4, Q=4, T=2, A=7, Z=0)


def tokenize(d):
    """The path's commands and numbers, with arc flags read as single digits."""
    out, i, cmd, argn = [], 0, None, 0
    while i < len(d):
        c = d[i]
        if c.isalpha():
            cmd = c.upper()
            out.append(c)
            i += 1
            argn = 0
        elif c in " ,\t\n":
            i += 1
        else:
            if cmd == "A" and argn % 7 in (3, 4):
                out.append(float(c))  # a flag is one character, even when the next number follows without a space
                i += 1
            else:
                m = NUMBER.match(d, i)
                out.append(float(m.group()))
                i = m.end()
            argn += 1
    return out


def subpaths(d):
    """The path split at each move, every command made absolute. Each is {d, pts, bbox}, the bbox from its points."""
    toks = tokenize(d)
    paths, cur, start, pos, i = [], None, (0, 0), (0, 0), 0
    while i < len(toks):
        c = toks[i]
        i += 1
        rel, C = c.islower(), c.upper()
        n = ARGS[C]
        while True:
            args = toks[i:i + n]
            i += n
            x, y = pos
            if C == "M":
                if rel:
                    args = [x + args[0], y + args[1]]
                if cur:
                    paths.append(cur)
                cur, start, pos = {"d": "", "pts": []}, (args[0], args[1]), (args[0], args[1])
                cur["d"] += f"M{fmt(args[0])} {fmt(args[1])}"
                cur["pts"].append(pos)
                C = "L"  # extra pairs after a move are lines
            elif C == "Z":
                cur["d"] += "Z"
                pos = start
            elif C == "H":
                nx = x + args[0] if rel else args[0]
                cur["d"] += f"L{fmt(nx)} {fmt(y)}"
                pos = (nx, y)
                cur["pts"].append(pos)
            elif C == "V":
                ny = y + args[0] if rel else args[0]
                cur["d"] += f"L{fmt(x)} {fmt(ny)}"
                pos = (x, ny)
                cur["pts"].append(pos)
            elif C == "A":
                rx, ry, rot, large, sweep, ex, ey = args
                if rel:
                    ex, ey = x + ex, y + ey
                cur["d"] += f"A{fmt(rx)} {fmt(ry)} {fmt(rot)} {int(large)} {int(sweep)} {fmt(ex)} {fmt(ey)}"
                pos = (ex, ey)
                cur["pts"].append(pos)
            else:
                pts = []
                for k in range(0, n, 2):
                    px, py = args[k], args[k + 1]
                    if rel:
                        px, py = x + px, y + py
                    pts.append((px, py))
                cur["d"] += C + " ".join(f"{fmt(px)} {fmt(py)}" for px, py in pts)
                pos = pts[-1]
                cur["pts"] += pts
            if n == 0 or i >= len(toks) or isinstance(toks[i], str):
                break
    if cur:
        paths.append(cur)
    for p in paths:
        xs, ys = [q[0] for q in p["pts"]], [q[1] for q in p["pts"]]
        p["bbox"] = (min(xs), min(ys), max(xs), max(ys))
    return paths


def fmt(v):
    s = f"{v:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def inside(a, b, tol=0.05):
    """bbox a within bbox b."""
    return a[0] >= b[0] - tol and a[1] >= b[1] - tol and a[2] <= b[2] + tol and a[3] <= b[3] + tol and a != b


def depths(paths, overrides):
    out = []
    for i, p in enumerate(paths):
        d = sum(1 for j, q in enumerate(paths) if j != i and inside(p["bbox"], q["bbox"]))
        out.append(overrides.get(i, min(d, 2)))
    return out


def pick(setting, index, fallback=None):
    if isinstance(setting, dict):
        return setting.get(index, fallback)
    return setting or fallback


def union(bboxes):
    return (min(b[0] for b in bboxes), min(b[1] for b in bboxes), max(b[2] for b in bboxes), max(b[3] for b in bboxes))


def gradient(gid, stops, bbox):
    """A vertical gradient over a bbox, in user space, so strokes and fills share it."""
    inner = "".join(f'<stop offset="{o}" stop-color="{c}"' + (f' stop-opacity="{a}"' if a is not None else "") + "/>" for o, c, a in stops)
    return f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="0" y1="{fmt(bbox[1])}" x2="0" y2="{fmt(bbox[3])}">{inner}</linearGradient>'


def stroke(d, paint, width, extra=""):
    return f'<path d="{d}" fill="none" stroke="{paint}" stroke-width="{fmt(width)}" stroke-linejoin="round" stroke-linecap="round"{extra}/>'


def body_layers(gid, d, pal, bbox, rim_color, rim_width):
    """Rim, body fill and bevel for one body part: (defs, rim, [body, bevel])."""
    defs = [gradient(f"{gid}-b", [(0, pal["hi"], None), (0.5, pal["mid"], None), (1, pal["lo"], None)], bbox),
            gradient(f"{gid}-v", [(0, pal["bevel"], 0.8), (0.55, pal["bevel"], 0.2), (1, pal["bevel"], 0.0)], bbox),
            f'<clipPath id="{gid}-c"><path d="{d}"/></clipPath>']
    rim = f'<path d="{d}" fill="{rim_color}" stroke="{rim_color}" stroke-width="{fmt(2 * rim_width)}" stroke-linejoin="round" stroke-linecap="round"/>'
    body = [f'<path d="{d}" fill="url(#{gid}-b)"/>',
            stroke(d, f"url(#{gid}-v)", 2 * BEVEL, f' clip-path="url(#{gid}-c)"')]
    return defs, rim, body


def detail_layers(gid, d, pal, bbox):
    """A set-in detail: its own gradient, a faint shade along its top edge, a faint light along the bottom."""
    defs = [gradient(f"{gid}-r", [(0, pal["mid"], None), (1, pal["lo"], None)], bbox),
            gradient(f"{gid}-e", [(0, pal["edge"], 0.45), (0.5, pal["edge"], 0.0), (1, pal["hi"], 0.5)], bbox),
            f'<clipPath id="{gid}-rc"><path d="{d}"/></clipPath>']
    layers = [f'<path d="{d}" fill="url(#{gid}-r)"/>', stroke(d, f"url(#{gid}-e)", 2 * EDGE, f' clip-path="url(#{gid}-rc)"')]
    return defs, layers


def line_layers(gid, d, pal, width, bulbs, detail_pal):
    """A line icon's stroke as the body (the hourglass): rim, bulbs set in between the strokes, then the stroke on top."""
    bbox = union([p["bbox"] for p in subpaths(d)])
    defs = [gradient(f"{gid}-b", [(0, pal["hi"], None), (0.5, pal["mid"], None), (1, pal["lo"], None)], bbox),
            gradient(f"{gid}-v", [(0, pal["bevel"], 0.8), (0.55, pal["bevel"], 0.25), (1, pal["bevel"], 0.0)], bbox)]
    layers = [stroke(d, pal["rim"], width + 2 * RIM)]
    for k, bulb in enumerate(bulbs):
        rd, rl = detail_layers(f"{gid}-u{k}", bulb, detail_pal, subpaths(bulb)[0]["bbox"])
        defs += rd
        layers += rl
    # The bevel is a stroke under the body stroke, a little wider, so it shows as a band along both edges.
    layers.append(stroke(d, f"url(#{gid}-v)", width))
    layers.append(stroke(d, f"url(#{gid}-b)", width - 2 * BEVEL))
    return defs, layers, bbox


def ribbon_layers(gid, r, defs, bodies, parts):
    """A ribbon over the bodies: a horizontal band across the lid, a vertical band down lid and box, a knot where they cross.
    Each band has a darker rim, a top-lit gradient and a lighter lip. The bands are clipped to the bodies plus the notch and
    the gap between lid and box, which the vertical band crosses."""
    pal, kpal = PALETTES[r["pal"]], PALETTES[r["knot"]]
    cid = f"{gid}-rc2"
    defs.append(f'<clipPath id="{cid}">' + "".join(f'<path d="{parts[i]["d"]}"/>' for i in bodies)
                + "".join(f'<path d="{d}"/>' for d in r["fill"]) + "</clipPath>")
    defs.append(gradient(f"{gid}-rb", [(0, pal["hi"], None), (0.5, pal["mid"], None), (1, pal["lo"], None)], (0, r["top"], 0, r["bottom"])))
    y0, y1 = r["hband"]
    defs.append(gradient(f"{gid}-rh", [(0, pal["hi"], None), (1, pal["lo"], None)], (0, y0, 0, y1)))
    defs.append(gradient(f"{gid}-rk", [(0, kpal["hi"], None), (0.5, kpal["mid"], None), (1, kpal["lo"], None)], (0, r["cy"] - 1.5, 0, r["cy"] + 1.5)))
    cx, cy, k, w = r["cx"], r["cy"], 1.5, 1.0
    rim, lip = pal["rim"], pal["bevel"]
    vx, vt, vb = cx - w, r["top"], r["bottom"]
    g = [
        # The vertical band: rim, face, a light lip down its left side and a shade where the lid's lip falls on it.
        f'<rect x="{fmt(vx - 0.4)}" y="{fmt(vt)}" width="{fmt(2 * w + 0.8)}" height="{fmt(vb - vt + 0.4)}" fill="{rim}"/>',
        f'<rect x="{fmt(vx)}" y="{fmt(vt)}" width="{fmt(2 * w)}" height="{fmt(vb - vt)}" fill="url(#{gid}-rb)"/>',
        f'<rect x="{fmt(vx)}" y="{fmt(vt)}" width="0.5" height="{fmt(vb - vt)}" fill="{lip}" fill-opacity="0.8"/>',
        f'<rect x="{fmt(vx)}" y="11" width="{fmt(2 * w)}" height="2" fill="{rim}" fill-opacity="0.4"/>',
        # The horizontal band across the lid.
        f'<rect x="2" y="{fmt(y0 - 0.4)}" width="20" height="{fmt(y1 - y0 + 0.8)}" fill="{rim}"/>',
        f'<rect x="2" y="{fmt(y0)}" width="20" height="{fmt(y1 - y0)}" fill="url(#{gid}-rh)"/>',
        f'<rect x="2" y="{fmt(y0)}" width="20" height="0.6" fill="{lip}" fill-opacity="0.9"/>',
    ]
    knot = [
        f'<circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(k + 0.5)}" fill="{kpal["rim"]}"/>',
        f'<circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(k)}" fill="url(#{gid}-rk)"/>',
        f'<circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(k - 0.3)}" fill="none" stroke="{kpal["bevel"]}" stroke-width="0.5" stroke-opacity="0.7" '
        f'stroke-dasharray="{fmt(3.14 * (k - 0.3))} 20" transform="rotate(180 {fmt(cx)} {fmt(cy)})"/>',
    ]
    return [f'<g clip-path="url(#{cid})">' + "".join(g) + "</g>"] + knot


def build(name, spec, data):
    gid = "spc-" + name
    source = spec.get("source", name)
    d = re.search(r'd="([^"]+)"', data["icons"][source]["body"]).group(1)
    defs, layers = [], []
    if "line" in spec:
        ld, ll, bbox = line_layers(gid, d, PALETTES[spec["body"]], spec["line"], spec["bulbs"], PALETTES[spec["detail"]])
        defs += ld
        layers += ll
        extent = spec["line"] / 2 + RIM
    else:
        parts = subpaths(d)
        level = depths(parts, spec.get("depth", {}))
        rim_pal, rim_width = spec.get("rim", (None, RIM))
        extent = rim_width
        bodies = [i for i, lvl in enumerate(level) if lvl == 0]
        bbox = union([parts[i]["bbox"] for i in bodies])
        defs.append(f'<clipPath id="{gid}-bc">' + "".join(f'<path d="{parts[i]["d"]}"/>' for i in bodies) + "</clipPath>")
        # Rims first, under every part, so one part's rim never crosses another's face.
        rims, faces, under, details, raised = [], [], [], [], []
        for i in bodies:
            pal = PALETTES[pick(spec["body"], i)]
            pd, rim, body = body_layers(f"{gid}-p{i}", parts[i]["d"], pal, parts[i]["bbox"], PALETTES[rim_pal]["rim"] if rim_pal else pal["rim"], rim_width)
            defs += pd
            rims.append(rim)
            faces += body
        for pal_name, shape in spec.get("under", []):
            under.append(f'<path d="{shape}" fill="{PALETTES[pal_name]["mid"]}"/>')
        for i, p in enumerate(parts):
            if level[i] == 1:
                pal = PALETTES[pick(spec.get("detail"), i, "cream")]
                dd, dl = detail_layers(f"{gid}-p{i}", p["d"], pal, p["bbox"])
                defs += dd
                factor = spec.get("scale", {}).get(i)
                if factor:
                    cx, cy = (p["bbox"][0] + p["bbox"][2]) / 2, (p["bbox"][1] + p["bbox"][3]) / 2
                    dl = [f'<g clip-path="url(#{gid}-bc)"><g transform="translate({fmt(cx)} {fmt(cy)}) scale({factor}) translate({fmt(-cx)} {fmt(-cy)})">' + "".join(dl) + "</g></g>"]
                details += dl
            elif level[i] == 2:
                pal = PALETTES[pick(spec.get("raised"), i, "white")]
                raised.append(f'<path d="{p["d"]}" fill="{pal["lo"]}"/>')
        ribbon = ribbon_layers(gid, spec["ribbon"], defs, bodies, parts) if "ribbon" in spec else []
        layers = rims + under + faces + ribbon + details + raised
    assert bbox[0] - extent >= 0 and bbox[1] - extent >= 0 and bbox[2] + extent <= 24 and bbox[3] + extent <= 24, f"{name} overflows the 24-unit box"
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="1em" height="1em">'
            f'<defs>{"".join(defs)}</defs>{"".join(layers)}</svg>\n')


README = """# Colour icons

MingCute Icon (`@iconify-json/mingcute` 1.2.8, by MingCute Design, Apache-2.0), redrawn as chunky, saturated stickers in Save
Point's palette, the way the hourglass (`hours.png`) is coloured: a rim a little darker than the body in the same hue, a
top-lit gradient body, a thin lighter bevel inside the edge, and the icon's holes set in as details in a strongly contrasting
colour (cream on a dark body, a deep colour on a light one). Each is a 24 by 24 layered SVG with its gradients' ids prefixed
by `spc-<name>`, so several can be inlined on one page.

They are decorative illustrations, 48px or larger: the steps on the landing page, empty states, headers. For an icon in text
or on a control, use the single-ink Icons set.

Built by `design/build/make_color_icons.py` from a per-icon spec (palettes, which parts are details, what to enlarge or fill
under). Edit the spec, run it, then `bin/rails style_sheet:sync` to copy them into the app.
"""


def main():
    data = json.loads(MINGCUTE.read_text())
    ROOT.mkdir(parents=True, exist_ok=True)
    for old in ROOT.glob("*.svg"):
        old.unlink()
    for name, spec in SPECS.items():
        (ROOT / f"{name}.svg").write_text(build(name, spec, data))
    (ROOT / "README.md").write_text(README)
    print("colour icons:", len(SPECS), "skipped:", ", ".join(f"{k} ({v})" for k, v in SKIPPED.items()))


if __name__ == "__main__":
    main()
