#!/usr/bin/env python3
"""Generates the placeholder dwarf mine theme (stdlib only): every PNG plus theme.json and the
root manifest.json. Real art replaces these files one for one; sizes, anchors and connector
positions are the contract. See docs/ART.md.

  python3 tools/make_placeholders.py

The painters live in tools/placeholders/: pixels (canvas and the 32-colour palette), layout (the
shared geometry), dwarf (character and portrait), frame (rock, connectors, orb), props, scenes.
"""
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from placeholders import dwarf, frame, props, scenes  # noqa: E402
from placeholders.layout import W, H, BAR, FLOOR, FEET, LADDER_X, LADDER_W, LADDER_BOTTOM_TOP, TUNNEL_TOP, TUNNEL_H, TUNNEL_W, ORB, bl  # noqa: E402
from placeholders.pixels import HEX  # noqa: E402

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

    scene_defs = []
    for ident, name, paint in scenes.SCENES:
        bg, fg, ambient, extra = paint()
        entry = {"id": ident, "name": name, "bg": save(bg, f"scenes/{ident}/bg.png"), "fg": save(fg, f"scenes/{ident}/fg.png"), "feet": list(FEET)}
        placements = extra.get("props", {})
        entry["props"] = [{"name": p["name"], "position": placements.get(p["name"], {}).get("position", p["position"]), "z": p["z"]} for p in prop_defs]
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
        "orb": orb, "props": prop_defs, "scenes": scene_defs,
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
