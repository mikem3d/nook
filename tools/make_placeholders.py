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
    bg.rect(128, 44, 50, 3, shade(p["desk"], 0.7))
    for i, c in enumerate(((200, 80, 80), (80, 160, 120), (230, 200, 90), (90, 120, 200), (180, 110, 190))):
        bg.rect(131 + i * 6, 32 + (i % 2) * 2, 4, 12 - (i % 2) * 2, c + (255,))
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
    }
    with open(os.path.join(ROOT, "manifest.json"), "w") as f:
        json.dump(data, f, indent=2)


if __name__ == "__main__":
    character()
    for n, p in ROOMS.items():
        room(n, p)
    manifest()
    print("placeholders written to", os.path.abspath(ROOT))
