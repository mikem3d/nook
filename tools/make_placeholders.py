#!/usr/bin/env python3
"""Generates the placeholder dwarf mine theme (stdlib only): every PNG plus theme.json and the
root manifest.json. Real art replaces these files one for one; sizes, anchors and connector
positions are the contract. See docs/ART.md.

  python3 tools/make_placeholders.py

The painters live in tools/placeholders/: pixels (canvas and the 32-colour palette), layout (the
shared geometry), dwarf (character and portrait), frame (rock, connectors, orb), props, hotspots
(the props that are buttons), scenes.
"""
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "art"))
import placement  # noqa: E402
from placeholders import dwarf, frame, hotspots, props, scenes  # noqa: E402
from placeholders.layout import W, H, BAR, FLOOR, FEET, LADDER_X, LADDER_W, LADDER_BOTTOM_TOP, TUNNEL_TOP, TUNNEL_H, TUNNEL_W, ORB, bl  # noqa: E402
from placeholders.pixels import HEX  # noqa: E402
from placeholders.plans import PLANS  # noqa: E402

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ASSETS = os.path.join(REPO, "Sources", "Nook", "Assets")
THEME_ID = "dwarf-mine"
ROOT = os.path.join(ASSETS, "themes", THEME_ID)


def save(img, rel):
    img.save(os.path.join(ROOT, rel))
    return rel


def main():
    shutil.rmtree(ROOT, ignore_errors=True)

    character = {
        "sheet": save(dwarf.character(), "character/sheet.png"),
        "frame": [dwarf.F, dwarf.F], "columns": dwarf.COLS, "rows": len(dwarf.ANIMS),
        "feet": list(FEET),
        "animations": {n: {"row": i, "frames": len(fr), "fps": fps, "looping": loop} for i, (n, fps, loop, fr) in enumerate(dwarf.ANIMS)},
    }
    portrait = {"sheet": save(dwarf.portraits(), "character/portrait.png"), "frame": [dwarf.P, dwarf.P],
                "states": {s: i for i, s in enumerate(dwarf.PORTRAIT_STATES)}}

    def piece(img, rel, x, y_top):
        return {"sprite": save(img, rel), "position": bl(x, y_top, img.h)}
    right = W - TUNNEL_W
    connectors = {
        "top": {"open": piece(frame.ladder_top(), "frame/ladder_top.png", LADDER_X, 0),
                "sealed": piece(frame.sealed_top(), "frame/sealed_top.png", LADDER_X, 0)},
        "bottom": {"open": piece(frame.ladder_bottom(), "frame/ladder_bottom.png", LADDER_X, LADDER_BOTTOM_TOP),
                   "sealed": piece(frame.sealed_bottom(), "frame/sealed_bottom.png", LADDER_X, FLOOR - 1)},
        "left": {"open": piece(frame.tunnel_left(), "frame/tunnel_left.png", 0, TUNNEL_TOP),
                 "sealed": piece(frame.tunnel_left(False), "frame/sealed_left.png", 0, TUNNEL_TOP)},
        "right": {"open": piece(frame.tunnel_right(), "frame/tunnel_right.png", right, TUNNEL_TOP),
                  "sealed": piece(frame.tunnel_right(False), "frame/sealed_right.png", right, TUNNEL_TOP)},
    }
    orb = {
        "size": ORB,
        "back": save(frame.orb_back(), "orb/back.png"),
        "ring": save(frame.orb_ring(), "orb/ring.png"),
        "portraitPosition": [4, 4],
        "gem": {"sprite": save(frame.orb_gem(), "orb/gem.png"), "position": [11, 0]},
        "alert": save(frame.orb_alert(), "orb/alert.png"),
        "work": {"sheet": save(frame.orb_work(), "orb/work.png"), "frame": [10, 10], "frames": 4, "fps": 4, "position": [18, 1]},
    }

    prop_defs = []
    for name, sheet in props.sheets():
        save(sheet, f"props/{name}.png")
    for name, size, states, position, z, _ in props.PROPS:
        prop_defs.append({"name": name, "sheet": f"props/{name}.png", "frame": list(size), "states": states, "position": position, "z": z})
    prop_size = {p["name"]: (p["frame"][0], p["frame"][1], p["z"]) for p in prop_defs}

    def dressing(name, kit):
        """The sheet for one chamber's own filling of a shared prop, written once per kit used."""
        if not kit or kit not in (props.DRESSED.get(name) or {}):
            return None
        rel = f"props/{name}_{kit}.png"
        if not os.path.exists(os.path.join(ROOT, rel)):
            save(props.one(name, kit), rel)
        return rel

    hotspot_defs = []
    for ident, name, size, levels, paint, hit, position, z, news, number in hotspots.HOTSPOTS:
        entry = {"id": ident, "name": name, "sheet": save(hotspots.grid(size, levels, paint), f"hotspots/{ident}.png"),
                 "frame": list(size), "levels": levels, "hit": hit, "position": position, "z": z}
        if news:
            mark, mark_size, place = news
            entry["news"] = {"sprite": save(hotspots.overlay(mark_size, mark), f"hotspots/{ident}_news.png"), "position": place}
        if number:
            entry["digits"] = {"sheet": save(hotspots.digits(), "hotspots/digits.png"), "frame": [3, 5], "position": number}
        hotspot_defs.append(entry)

    hit_size = {}
    for h in hotspot_defs:
        fw, fh = h["frame"]
        hx, hy, hw, hh = h.get("hit") or [0, 0, fw, fh]
        hit_size[h["id"]] = (fw, fh, hx, fh - hy - hh, hw, hh)

    scene_defs = []
    for ident, name, paint in scenes.SCENES:
        # The plan is the chamber's floor plan; placement.py is the referee. Anything the plan gets
        # wrong is moved to the nearest place that breaks no rule, and said out loud.
        plan = PLANS[ident]
        places, spots, moves, stuck = placement.resolve(plan.feet, dict(plan.props), dict(plan.spots), prop_size, hit_size)
        for what, was, now, why in moves:
            print(f"  {ident}: moved {what} {was} -> {now} ({why})")
        for msg in stuck:
            print(f"  {ident}: CANNOT PLACE {msg}")
        for msg in placement.calm_bubble(places, prop_size):
            print(f"  {ident}: {msg}")

        bg, fg, ambient, extra = paint(plan)
        entry = {"id": ident, "name": name, "bg": save(bg, f"scenes/{ident}/bg.png"), "fg": save(fg, f"scenes/{ident}/fg.png"),
                 "feet": [plan.feet, H - FLOOR]}
        entry["props"] = []
        for p in prop_defs:
            x, y_top = places[p["name"]]
            place = {"name": p["name"], "position": bl(x, y_top, p["frame"][1]), "z": p["z"]}
            dressed = dressing(p["name"], plan.kits.get(p["name"]))
            if dressed:
                place["sheet"] = dressed
            entry["props"].append(place)
        moved = extra.get("hotspots", {})
        entry["hotspots"] = [dict({"id": h["id"], "position": bl(*spots[h["id"]], h["frame"][1]), "z": h["z"]},
                                  **moved.get(h["id"], {})) for h in hotspot_defs]
        entry["ambient"] = []
        for spec, sheet in ambient:
            spec = dict(spec, sheet=save(sheet, f"scenes/{ident}/{spec['name']}.png"))
            entry["ambient"].append(spec)
        if "animations" in extra:
            entry["animations"] = extra["animations"]
        scene_defs.append(entry)

    theme = {
        "id": THEME_ID, "name": "Dwarf Mine", "canvas": [W, H],
        "palette": list(HEX.values()),
        "geometry": {"header": BAR, "floor": H - FLOOR, "ladder": [LADDER_X, LADDER_W], "tunnel": [H - TUNNEL_TOP - TUNNEL_H, TUNNEL_H]},
        "character": character, "avatars": dwarf.avatar_swaps(), "portrait": portrait,
        "frame": {"overlay": save(frame.overlay(), "frame/frame.png"), "connectors": connectors},
        "orb": orb, "props": prop_defs, "hotspots": hotspot_defs, "scenes": scene_defs,
    }
    with open(os.path.join(ROOT, "theme.json"), "w") as f:
        json.dump(theme, f, indent=2)
        f.write("\n")
    with open(os.path.join(ASSETS, "manifest.json"), "w") as f:
        json.dump({"theme": THEME_ID}, f, indent=2)
        f.write("\n")
    with open(os.path.join(REPO, "tools", "art", "palettes", "dwarfmine.hex"), "w") as f:
        f.write("; Nook dwarf mine theme, written by tools/make_placeholders.py\n" + "\n".join(HEX.values()) + "\n")
    print("placeholders written to", os.path.abspath(ROOT))


if __name__ == "__main__":
    main()
