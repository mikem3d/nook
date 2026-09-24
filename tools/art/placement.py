#!/usr/bin/env python3
"""Where a chamber may put things, and how to move the ones that are in the wrong place.

Eight chambers that each lay themselves out differently only stay shippable if the rules are
machine-checked, because the rules are not obvious by eye: a hotspot that looks fine can still be
under the speech bubble at 2x, and a prop that looks clear can still be behind the dwarf.

The rules (docs/ART.md, and Tests/NookTests/HotspotTests, which is the strictest of them):

  header    rows 0..10          the lintel is drawn over everything
  ladder    x 12..25            the shaft hangs the full height of the chamber
  tunnels   x 0..9, x 182..191  rows 62..91, where the tunnel pieces go
  bubble    rows 0..54          a hotspot HIT rectangle may not reach up into them at all
  bubble2x  x >= 76, rows 11..55  the 2x speech bubble's own box: art there must stay calm rock
  dwarf     feet.x +/- 10, 32 tall, standing on the floor
  interior  x 6..185, rows 11..89

and then: no hotspot hit rectangle over another one or over a prop, no prop over another prop, and
nothing behind the dwarf but the wall (a prop drawn in FRONT of him, z > 2, may of course overlap).

Everything here is in IMAGE coordinates - x from the left, y the TOP row - because that is how the
painters are written. `from_scene` converts a theme.json scene, which uses the manifest's
bottom-left origin. Stdlib only: `make_placeholders` imports this.
"""
from __future__ import annotations

W, H = 192, 108
BAR = 11
SIDE = 6
FLOOR = 90
LADDER_X, LADDER_W = 12, 14
TUNNEL_TOP, TUNNEL_H, TUNNEL_W = 62, 30, 10
BUBBLE_ROWS = 55          # a hotspot hit rectangle must clear rows 0..54 entirely
BUBBLE_2X_X = 76          # left edge of the 2x bubble box
BUBBLE_2X_BOTTOM = 56     # and the row under it
FIGURE_W, FIGURE_H = 20, 32

Rect = tuple  # (x, y, w, h), y the top row


def rect(x, y, w, h) -> Rect:
    return (int(x), int(y), int(w), int(h))


def hits(a: Rect, b: Rect) -> bool:
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def inside(a: Rect, b: Rect) -> bool:
    return a[0] >= b[0] and a[1] >= b[1] and a[0] + a[2] <= b[0] + b[2] and a[1] + a[3] <= b[1] + b[3]


def figure(feet_x: int) -> Rect:
    """The dwarf's own pixels inside his 32 px frame, standing on the floor."""
    return rect(feet_x - FIGURE_W // 2, FLOOR - FIGURE_H, FIGURE_W, FIGURE_H)


INTERIOR = rect(SIDE, BAR, W - 2 * SIDE, FLOOR - BAR + 1)
BUBBLE_HIT = rect(0, 0, W, BUBBLE_ROWS)
BUBBLE_2X = rect(BUBBLE_2X_X, BAR, W - BUBBLE_2X_X, BUBBLE_2X_BOTTOM - BAR)
STRUCTURE = [
    ("header", rect(0, 0, W, BAR)),
    ("ladder", rect(LADDER_X, 0, LADDER_W, H)),
    ("tunnel-left", rect(0, TUNNEL_TOP, TUNNEL_W, TUNNEL_H)),
    ("tunnel-right", rect(W - TUNNEL_W, TUNNEL_TOP, TUNNEL_W, TUNNEL_H)),
]


# ---------- the rules ----------

def structure(theme: dict | None = None) -> list:
    """The chamber's fixed furniture, read off a theme's own geometry where it has one."""
    if not theme:
        return list(STRUCTURE)
    w, h = theme.get("canvas", [W, H])
    g = theme.get("geometry") or {}
    bar = g.get("header", BAR)
    lx, lw = g.get("ladder", [LADDER_X, LADDER_W])
    tfoot, th = g.get("tunnel", [H - TUNNEL_TOP - TUNNEL_H, TUNNEL_H])
    ttop = h - tfoot - th
    return [("header", rect(0, 0, w, bar)), ("ladder", rect(lx, 0, lw, h)),
            ("tunnel-left", rect(0, ttop, TUNNEL_W, th)), ("tunnel-right", rect(w - TUNNEL_W, ttop, TUNNEL_W, th))]


def hotspot_blockers(feet_x: int, props: dict, other_spots: dict, struct: list | None = None) -> list:
    """Everything a hotspot hit rectangle has to keep off, named so a failure says why."""
    out = list(struct or STRUCTURE) + [("bubble", BUBBLE_HIT), ("dwarf", figure(feet_x))]
    for name, r in props.items():
        out.append((f"prop {name}", r))
    for ident, r in other_spots.items():
        out.append((f"hotspot {ident}", r))
    return out


def prop_blockers(name: str, feet_x: int, z: float, props: dict, spots: dict, struct: list | None = None) -> list:
    out = list(struct or STRUCTURE)
    if z <= 2.0:                              # drawn behind the dwarf, so it must not be behind him
        out.append(("dwarf", figure(feet_x)))
    for other, r in props.items():
        if other != name:
            out.append((f"prop {other}", r))
    for ident, r in spots.items():
        out.append((f"hotspot {ident}", r))
    return out


def check(where: str, r: Rect, blockers: list, bounds: Rect = INTERIOR) -> list[str]:
    bad = [f"{where} {r} is not inside the chamber {bounds}"] if not inside(r, bounds) else []
    bad += [f"{where} {r} collides with {name} {b}" for name, b in blockers if hits(r, b)]
    return bad


def search(r: Rect, blockers: list, bounds: Rect = INTERIOR, reach: int = 48) -> Rect | None:
    """The nearest position that breaks no rule, preferring a sideways move to a vertical one.

    Sideways first because the chambers have room across and almost none up and down: between the
    bubble above and the floor below, a hotspot has about fifteen rows to live in.
    """
    if not check("", r, blockers, bounds):
        return r
    x, y, w, h = r
    offsets = sorted({(dx, dy) for dx in range(-reach, reach + 1) for dy in range(-reach, reach + 1)},
                     key=lambda v: (abs(v[1]) * 3 + abs(v[0]), abs(v[1]), v[0], v[1]))
    for dx, dy in offsets:
        cand = rect(x + dx, y + dy, w, h)
        if not check("", cand, blockers, bounds):
            return cand
    return None


def resolve(feet_x: int, props: dict, spots: dict, sizes: dict, hit_sizes: dict):
    """Check a whole chamber and move whatever is in the wrong place.

    `props`/`spots` map a name to its top-left (x, y); `sizes` maps a prop name to (w, h, z) and
    `hit_sizes` a hotspot id to (frame_w, frame_h, hit_x, hit_y_from_top, hit_w, hit_h).
    Returns (props, spots, moves, unfixable): the corrected positions, what had to move and why,
    and anything no nearby position could satisfy.
    """
    prect = {n: rect(x, y, sizes[n][0], sizes[n][1]) for n, (x, y) in props.items()}
    srect = {i: rect(x + hit_sizes[i][2], y + hit_sizes[i][3], hit_sizes[i][4], hit_sizes[i][5])
             for i, (x, y) in spots.items()}
    moves, unfixable = [], []

    # Props first: they are the chamber's furniture and the art is built around them. Then the
    # hotspots, which are the most constrained things in the room, against the settled furniture.
    for name in sorted(prect, key=lambda n: -sizes[n][2]):
        blockers = prop_blockers(name, feet_x, sizes[name][2], prect, {})
        why = check(f"prop {name}", prect[name], blockers)
        if not why:
            continue
        found = search(prect[name], blockers)
        if found is None:
            unfixable += why
            continue
        moves.append((f"prop {name}", prect[name][:2], found[:2], why[0]))
        prect[name] = found

    for ident in sorted(srect):
        others = {i: r for i, r in srect.items() if i != ident}
        blockers = hotspot_blockers(feet_x, prect, others, {})
        why = check(f"hotspot {ident}", srect[ident], blockers)
        if not why:
            continue
        found = search(srect[ident], blockers)
        if found is None:
            unfixable += why
            continue
        moves.append((f"hotspot {ident}", srect[ident][:2], found[:2], why[0]))
        srect[ident] = found

    props = {n: (r[0], r[1]) for n, r in prect.items()}
    spots = {i: (srect[i][0] - hit_sizes[i][2], srect[i][1] - hit_sizes[i][3]) for i in srect}
    return props, spots, moves, unfixable


def calm_bubble(props: dict, sizes: dict) -> list[str]:
    """Art-level warning: a prop parked in the 2x speech bubble's box. Legal, never good."""
    out = []
    for name, (x, y) in props.items():
        r = rect(x, y, sizes[name][0], sizes[name][1])
        if hits(r, BUBBLE_2X):
            out.append(f"prop {name} {r} sits in the 2x speech bubble's box {BUBBLE_2X}")
    return out


# ---------- the same rules, read off a built theme.json ----------

def from_scene(scene: dict, theme: dict) -> list[str]:
    """Every rule above, checked against one scene of a generated theme. Bottom-left in, errors out."""
    canvas_h = theme.get("canvas", [W, H])[1]
    props = {p["name"]: p for p in theme.get("props") or []}
    spots = {h["id"]: h for h in theme.get("hotspots") or []}
    feet = scene.get("feet") or theme["character"]["feet"]
    feet_x = int(feet[0])
    prect, zs = {}, {}
    for place in scene.get("props") or []:
        spec = props.get(place["name"])
        if spec is None:
            continue
        w, h = spec["frame"]
        x, y = place["position"]
        prect[place["name"]] = rect(x, canvas_h - y - h, w, h)
        zs[place["name"]] = place.get("z", spec.get("z", 0.5))
    srect = {}
    for place in scene.get("hotspots") or []:
        spec = spots.get(place["id"])
        if spec is None:
            continue
        fw, fh = spec["frame"]
        hx, hy, hw, hh = spec.get("hit") or [0, 0, fw, fh]
        x, y = place["position"]
        srect[place["id"]] = rect(x + hx, canvas_h - (y + hy) - hh, hw, hh)

    struct = structure(theme)
    bad = []
    for name, r in prect.items():
        bad += check(f"prop {name}", r, prop_blockers(name, feet_x, zs[name], prect, {}, struct))
    for ident, r in srect.items():
        others = {i: o for i, o in srect.items() if i != ident}
        bad += check(f"hotspot {ident}", r, hotspot_blockers(feet_x, prect, others, struct))
    return bad


if __name__ == "__main__":
    import json
    import sys
    from pathlib import Path

    root = Path(__file__).resolve().parents[2] / "Sources/Nook/Assets/themes/dwarf-mine"
    theme = json.loads((root / "theme.json").read_text())
    fails = 0
    for scene in theme["scenes"]:
        for msg in from_scene(scene, theme):
            print(f"  ERROR {scene['id']}: {msg}")
            fails += 1
    print(f"{'FAIL' if fails else 'PASS'}: {len(theme['scenes'])} chambers, {fails} placement errors")
    sys.exit(1 if fails else 0)
