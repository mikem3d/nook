#!/usr/bin/env python3
"""Generates placeholder pixel art (stdlib only) matching assets/manifest.json.

Real art replaces these files one for one; sizes and layout are the contract.
See docs/ART.md.
"""
import json, os, struct, zlib

ROOT = os.path.join(os.path.dirname(__file__), "..", "Sources", "Nook", "Assets")
W, H = 192, 108
F = 32          # character frame size
COLS = 8

T = (0, 0, 0, 0)
INK = (26, 26, 41, 255)
SKIN = (240, 190, 150, 255)
WHITE = (245, 245, 235, 255)


class Img:
    def __init__(self, w, h, fill=T):
        self.w, self.h = w, h
        self.px = [[fill] * w for _ in range(h)]

    def rect(self, x, y, w, h, c):
        for j in range(max(0, y), min(self.h, y + h)):
            for i in range(max(0, x), min(self.w, x + w)):
                self.px[j][i] = c

    def blit(self, other, ox, oy):
        for j in range(other.h):
            for i in range(other.w):
                if other.px[j][i][3]:
                    self.px[oy + j][ox + i] = other.px[j][i]

    def save(self, path):
        raw = b"".join(b"\x00" + bytes(v for p in row for v in p) for row in self.px)
        def chunk(tag, data):
            body = tag + data
            return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n")
            f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 6, 0, 0, 0)))
            f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
            f.write(chunk(b"IEND", b""))


# ---------- character ----------

SHIRT = (214, 120, 70, 255)
PANTS = (60, 70, 110, 255)
HAIR = (70, 45, 35, 255)


def figure(bob=0, la="down", ra="down", hx=0, eyes="open", mark=None, prop=None, lean=0):
    f = Img(F, F)
    b = bob
    f.rect(11, 24, 4, 8, PANTS)
    f.rect(17, 24, 4, 8, PANTS)
    f.rect(10 + lean, 14 + b, 12, 11 - b, SHIRT)
    hxx = 11 + hx + lean
    f.rect(hxx, 4 + b, 10, 10, SKIN)
    f.rect(hxx, 3 + b, 10, 3, HAIR)
    f.rect(hxx, 5 + b, 1, 4, HAIR)
    if eyes == "open":
        f.rect(hxx + 2 + hx, 9 + b, 2, 2, INK)
        f.rect(hxx + 6 + hx, 9 + b, 2, 2, INK)
    elif eyes == "closed":
        f.rect(hxx + 2, 10 + b, 2, 1, INK)
        f.rect(hxx + 6, 10 + b, 2, 1, INK)
    elif eyes == "wide":
        f.rect(hxx + 2, 8 + b, 2, 3, INK)
        f.rect(hxx + 6, 8 + b, 2, 3, INK)
    for side, pose in (("l", la), ("r", ra)):
        x = (7 if side == "l" else 22) + lean
        inward = 1 if side == "l" else -1
        if pose == "down":
            f.rect(x, 15 + b, 3, 8, SHIRT); f.rect(x, 23 + b, 3, 2, SKIN)
        elif pose == "up":
            f.rect(x, 5 + b, 3, 10, SHIRT); f.rect(x, 3 + b, 3, 2, SKIN)
        elif pose == "fwd":
            f.rect(x + inward, 17 + b, 3, 4, SHIRT); f.rect(x + inward * 2, 21 + b, 3, 2, SKIN)
        elif pose == "fwd2":
            f.rect(x + inward, 16 + b, 3, 4, SHIRT); f.rect(x + inward * 2, 19 + b, 3, 2, SKIN)
        elif pose == "face":
            f.rect(x, 14 + b, 3, 4, SHIRT); f.rect(x + inward * 2, 11 + b, 3, 4, SKIN)
        elif pose == "out":
            f.rect(x + (-3 if side == "l" else 1), 15 + b, 5, 3, SHIRT)
            f.rect(x + (-5 if side == "l" else 5), 15 + b, 2, 3, SKIN)
    if prop == "mug":
        f.rect(25, 9 + b, 4, 4, WHITE)
    elif prop == "mug_low":
        f.rect(25, 20 + b, 4, 4, WHITE)
    elif prop == "book":
        f.rect(11, 17 + b, 10, 6, (90, 140, 200, 255)); f.rect(15, 17 + b, 1, 6, WHITE)
    if mark and mark.startswith("dots"):
        for i in range(int(mark[4])):
            f.rect(23 + i * 3, 1, 2, 2, WHITE)
    elif mark == "!":
        f.rect(26, 0, 3, 7, (255, 90, 80, 255)); f.rect(26, 8, 3, 2, (255, 90, 80, 255))
    elif mark and mark.startswith("z"):
        n = int(mark[1])
        for i in range(n):
            f.rect(23 + i * 3, 6 - i * 3, 3, 1, WHITE); f.rect(24 + i * 3, 7 - i * 3, 1, 1, WHITE); f.rect(23 + i * 3, 8 - i * 3, 3, 1, WHITE)
    elif mark == "spark":
        for x, y in ((3, 3), (27, 5), (5, 12), (28, 13)):
            f.rect(x, y, 2, 2, (255, 225, 90, 255))
    return f


ANIMS = [
    ("idle_breathe", 3, True, [dict(), dict(bob=1), dict(bob=1), dict(eyes="closed")]),
    ("idle_sip", 5, False, [dict(ra="fwd", prop="mug_low"), dict(ra="face", prop="mug"), dict(ra="face", prop="mug", eyes="closed"),
                            dict(ra="face", prop="mug", eyes="closed"), dict(ra="face", prop="mug"), dict(ra="fwd", prop="mug_low")]),
    ("idle_stretch", 5, False, [dict(la="out", ra="out"), dict(la="up", ra="up"), dict(la="up", ra="up", eyes="closed", bob=1),
                                dict(la="up", ra="up", eyes="closed"), dict(la="out", ra="out"), dict()]),
    ("idle_read", 4, False, [dict(la="fwd", ra="fwd", prop="book")] * 2 + [dict(la="fwd", ra="fwd", prop="book", hx=1)] * 2 +
                            [dict(la="fwd", ra="fwd2", prop="book")] + [dict(la="fwd", ra="fwd", prop="book", hx=-1)] * 2 + [dict()]),
    ("idle_look", 4, False, [dict(hx=-1), dict(hx=-1), dict(), dict(hx=1), dict(hx=1), dict()]),
    ("think", 3, True, [dict(ra="face", hx=1, mark="dots1"), dict(ra="face", hx=1, mark="dots2"),
                        dict(ra="face", hx=1, mark="dots3"), dict(ra="face", hx=1, eyes="closed", mark="dots3")]),
    ("type", 8, True, [dict(la="fwd", ra="fwd2"), dict(la="fwd2", ra="fwd"), dict(la="fwd", ra="fwd2", bob=1), dict(la="fwd2", ra="fwd")]),
    ("talk", 5, True, [dict(ra="out", lean=1), dict(ra="out", lean=1, bob=1), dict(la="out", lean=-1), dict(la="out", lean=-1, bob=1)]),
    ("alert", 4, True, [dict(la="up", eyes="wide", mark="!"), dict(la="up", eyes="wide", bob=1)]),
    ("celebrate", 8, False, [dict(la="out", ra="out"), dict(la="up", ra="up", mark="spark"), dict(la="up", ra="up", bob=1),
                             dict(la="up", ra="up", mark="spark"), dict(la="out", ra="out", bob=1), dict(eyes="closed")]),
    ("sleep", 2, True, [dict(eyes="closed", bob=1, mark="z1"), dict(eyes="closed", bob=1, mark="z2"),
                        dict(eyes="closed", bob=2, mark="z3"), dict(eyes="closed", bob=2)]),
]


def character():
    sheet = Img(F * COLS, F * len(ANIMS))
    for row, (_, _, _, frames) in enumerate(ANIMS):
        assert len(frames) <= COLS
        for col, kw in enumerate(frames):
            sheet.blit(figure(**kw), col * F, row * F)
    sheet.save(os.path.join(ROOT, "character", "sheet.png"))


# ---------- rooms ----------

ROOMS = {
    "study": dict(wall=(70, 120, 125, 255), floor=(120, 85, 60, 255), sky=(150, 210, 240, 255), desk=(150, 100, 60, 255)),
    "workshop": dict(wall=(150, 105, 75, 255), floor=(80, 70, 70, 255), sky=(250, 190, 120, 255), desk=(95, 95, 110, 255)),
    "nightlab": dict(wall=(60, 55, 100, 255), floor=(40, 40, 65, 255), sky=(25, 25, 60, 255), desk=(70, 110, 120, 255)),
}


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3]) + (255,)


def room(name, p):
    bg = Img(W, H, p["wall"])
    for x in range(0, W, 16):
        bg.rect(x, 11, 1, 67, shade(p["wall"], 0.93))
    bg.rect(0, 78, W, 30, p["floor"])
    bg.rect(0, 78, W, 2, shade(p["floor"], 0.7))
    bg.rect(18, 22, 44, 34, INK); bg.rect(20, 24, 40, 30, p["sky"])
    bg.rect(39, 24, 2, 30, INK); bg.rect(20, 38, 40, 2, INK)
    if name == "nightlab":
        for x, y in ((25, 28), (33, 45), (47, 30), (54, 47)):
            bg.rect(x, y, 1, 1, WHITE)
    bg.save(os.path.join(ROOT, "rooms", f"{name}_bg.png"))

    fg = Img(W, H)
    fg.rect(44, 70, 104, 4, shade(p["desk"], 1.15))
    fg.rect(46, 74, 100, 30, p["desk"])
    fg.rect(46, 74, 100, 2, shade(p["desk"], 0.75))
    fg.rect(50, 74, 4, 34, shade(p["desk"], 0.6)); fg.rect(138, 74, 4, 34, shade(p["desk"], 0.6))
    fg.rect(108, 60, 22, 10, INK); fg.rect(110, 62, 18, 7, (120, 220, 190, 255)); fg.rect(104, 69, 30, 2, shade(INK, 2.2))
    fg.rect(60, 64, 6, 6, WHITE)
    fg.rect(164, 84, 14, 18, (170, 90, 60, 255))
    for x, y, w, h in ((166, 66, 4, 18), (171, 60, 4, 24), (175, 70, 4, 14), (162, 72, 4, 12)):
        fg.rect(x, y, w, h, (70, 150, 90, 255))
    fg.save(os.path.join(ROOT, "rooms", f"{name}_fg.png"))


# ---------- props (vital signs) ----------
#
# One sheet per prop, its states side by side. Frame coordinates below count from the frame's
# top-left; "position" in the manifest is the frame's bottom-left from the canvas bottom-left.

WOOD = (120, 78, 48, 255)
GOLD = (240, 200, 70, 255)
GLASS = (190, 225, 235, 255)
BOOKS = ((200, 80, 80), (80, 160, 120), (230, 200, 90), (90, 120, 200), (180, 110, 190))


def window_state(f, i):
    sky = ((150, 210, 240, 255), (240, 150, 100, 255), (25, 25, 60, 255))[i]
    f.rect(0, 0, 40, 30, sky)
    if i == 0:
        f.rect(28, 4, 6, 6, (255, 235, 130, 255)); f.rect(6, 8, 10, 3, WHITE); f.rect(9, 6, 5, 2, WHITE)
    elif i == 1:
        f.rect(0, 20, 40, 10, (225, 110, 90, 255)); f.rect(25, 16, 8, 6, (255, 215, 120, 255))
    else:
        f.rect(27, 4, 6, 6, WHITE); f.rect(29, 4, 4, 4, sky)
        for x, y in ((5, 5), (13, 21), (22, 12), (34, 23), (9, 14)):
            f.rect(x, y, 1, 1, WHITE)
    f.rect(19, 0, 2, 30, INK); f.rect(0, 14, 40, 2, INK)


def bookshelf_state(f, i):
    f.rect(0, 0, 36, 34, WOOD)
    f.rect(2, 2, 32, 14, shade(WOOD, 0.45)); f.rect(2, 18, 32, 14, shade(WOOD, 0.45))
    for n in range(i):  # bottom shelf fills first, left to right
        shelf, slot = divmod(n, 5)
        h = 12 - (n % 3)
        f.rect(3 + slot * 6, (32 if shelf == 0 else 16) - h, 5, h, BOOKS[(n * 2) % 5] + (255,))


def coinjar_state(f, i):
    f.rect(1, 1, 8, 11, GLASS); f.rect(2, 2, 6, 9, shade(GLASS, 0.55)); f.rect(2, 0, 6, 2, shade(WOOD, 1.3))
    f.rect(2, 11 - i, 6, i, GOLD)
    if i:
        f.rect(3, 11 - i, 2, 1, WHITE)


def papers_state(f, i):
    for n in range(i):
        f.rect(1 + (n % 2), 7 - n, 12, 1, WHITE if n % 2 == 0 else (215, 215, 225, 255))
    if i:
        f.rect(3 + (i % 2), 8 - i, 6, 1, (150, 150, 170, 255))


def clock_state(f, i):
    f.rect(1, 0, 11, 13, INK); f.rect(0, 1, 13, 11, INK); f.rect(1, 1, 11, 11, WHITE)
    for x, y in ((1, 1), (11, 1), (1, 11), (11, 11)):
        f.rect(x, y, 1, 1, INK)
    dx, dy = ((0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1))[i]
    for k in range(1, 5 if dx == 0 or dy == 0 else 4):
        f.rect(6 + dx * k, 6 + dy * k, 1, 1, (200, 60, 60, 255))
    f.rect(6, 6, 1, 1, INK)


def hourglass_state(f, i):
    f.rect(0, 0, 8, 1, WOOD); f.rect(0, 9, 8, 1, WOOD)
    for row, (x, w) in enumerate(((1, 6), (1, 6), (2, 4), (3, 2), (3, 2), (2, 4), (1, 6), (1, 6))):
        f.rect(x, 1 + row, w, 1, GLASS)
    # Sand moves from the top bulb to the bottom one across the states.
    top, bottom = ((3, 0), (2, 1), (1, 2), (0, 3))[i]
    bulb = ((3, 2), (2, 4), (2, 4))  # rows from the neck outward: x, width
    for k in range(top):
        f.rect(bulb[k][0], 4 - k, bulb[k][1], 1, GOLD)
    for k in range(bottom):
        f.rect(bulb[2 - k][0], 8 - k, bulb[2 - k][1], 1, GOLD)
    if 0 < i < 3:
        f.rect(4, 5, 1, 1, GOLD)


# name, frame, states, position (bottom-left, canvas px from bottom-left), z, painter
PROPS = [
    ("window", (40, 30), 3, (20, 54), 0.5, window_state),       # day, dusk, night
    ("bookshelf", (36, 34), 11, (4, 8), 0.5, bookshelf_state),   # context used: 0 to 10 books
    ("coinjar", (10, 12), 9, (26, 42), 0.6, coinjar_state),      # cost, log scale
    ("papers", (14, 8), 6, (47, 38), 2.5, papers_state),         # uncommitted files: 0 to 5+
    ("clock", (13, 13), 8, (3, 67), 0.5, clock_state),           # hand sweeps during a turn
    ("hourglass", (8, 10), 4, (138, 38), 2.5, hourglass_state),  # only shown once a turn passes 5 minutes
]


def props():
    for name, (w, h), states, _, _, paint in PROPS:
        sheet = Img(w * states, h)
        for i in range(states):
            frame = Img(w, h)
            paint(frame, i)
            sheet.blit(frame, i * w, 0)
        sheet.save(os.path.join(ROOT, "props", f"{name}.png"))


def manifest():
    data = {
        "canvas": [W, H],
        "character": {
            "sheet": "character/sheet.png",
            "frame": [F, F],
            "columns": COLS,
            "rows": len(ANIMS),
            "feet": [84, 26],
            "animations": {n: {"row": i, "frames": len(fr), "fps": fps, "looping": loop} for i, (n, fps, loop, fr) in enumerate(ANIMS)},
        },
        "rooms": [{"id": n, "bg": f"rooms/{n}_bg.png", "fg": f"rooms/{n}_fg.png"} for n in ROOMS],
        "props": [{"name": n, "sheet": f"props/{n}.png", "frame": list(fr), "states": st, "position": list(pos), "z": z}
                  for n, fr, st, pos, z, _ in PROPS],
    }
    with open(os.path.join(ROOT, "manifest.json"), "w") as f:
        json.dump(data, f, indent=2)


if __name__ == "__main__":
    character()
    for n, p in ROOMS.items():
        room(n, p)
    props()
    manifest()
    print("placeholders written to", os.path.abspath(ROOT))
