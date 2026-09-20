"""The dwarf: a 32x32 animation sheet and a 20x20 portrait sheet.

Beard, tunic and helmet each use a main and a shade colour that appear NOWHERE else in these two
sheets. The engine recolours exactly those six "key" colours to make the avatar variants
(theme.json "avatars"), so keep marks, tools and props off them.
"""
from .pixels import Img, sheet

F, COLS = 32, 8
KEYS = {"beard": ("orange", "wood_lt"), "tunic": ("green", "green_dk"), "helmet": ("stone", "rock_lt")}
BEARD, BEARD_DK = KEYS["beard"]
TUNIC, TUNIC_DK = KEYS["tunic"]
HELM, HELM_DK = KEYS["helmet"]

# name: (beard, tunic, helmet) as (main, shade) pairs; None keeps the base colours.
AVATARS = [
    ("ginger", "Ginger", None, None, None),
    ("umber", "Umber", ("wood", "wood_dk"), ("blue", "blue_dk"), ("sand", "wood")),
    ("ash", "Ash", ("pale", "rock_lt"), ("red", "red_dk"), None),
    ("coal", "Coal", ("rock", "rock_dk"), ("purple", "purple_dk"), ("yellow", "sand")),
    ("flax", "Flax", ("sand", "wood"), ("teal", "green_dk"), ("pale", "stone")),
    ("frost", "Frost", ("white", "pale"), ("wood", "wood_dk"), ("sky", "blue")),
]


def _mirror(points):
    return [(F - 1 - x, y) for x, y in points]


def figure(bob=0, la="down", ra="down", hx=0, eyes="open", mouth=None, mark=None, prop=None, lean=0, stir=0):
    f = Img(F, F)
    b, L = bob, lean

    # boots and tunic; the feet never move, so the sheet cannot drift
    f.rect(10, 28, 5, 3, "wood_dk"); f.rect(17, 28, 5, 3, "wood_dk")
    f.rect(10 + L, 17 + b, 12, 11 - b, TUNIC)
    f.rect(10 + L, 27, 12, 1, TUNIC_DK)
    f.rect(10 + L, 24, 12, 1, "wood_dk"); f.rect(15 + L, 24, 2, 1, "yellow")

    # head: helmet with horns, face, the beard over the chest
    hxx = L + hx
    horn = [(9, 7), (8, 7), (8, 6), (8, 5), (7, 5), (7, 4)]
    f.dots([(x + hxx, y + b) for x, y in horn + _mirror(horn)], "cream")
    f.rows(hxx, 4 + b, [(12, 8), (11, 10), (10, 12), (10, 12), (10, 12)], HELM)
    f.rect(11 + hxx, 6 + b, 2, 2, "white")
    f.rect(9 + hxx, 9 + b, 14, 1, HELM_DK)
    f.rect(10 + hxx, 10 + b, 12, 5, "skin")
    f.rows(hxx, 13 + b, [(10, 12), (10, 12), (10, 12), (10, 12), (10, 12), (11, 10), (11, 10), (12, 8), (12, 8), (14, 4)], BEARD)
    f.rect(12 + hxx, 13 + b, 8, 1, "skin")
    f.rect(15 + hxx, 12 + b, 2, 3, "skin_dk")
    f.dots([(x + hxx, y + b) for x, y in ((12, 18), (19, 18), (14, 20), (17, 20), (15, 22), (16, 22), (10, 17), (21, 17))], BEARD_DK)
    if mouth == "open":
        f.rect(15 + hxx, 16 + b, 2, 2, "ink")
    else:
        f.rect(14 + hxx, 16 + b, 4, 1, BEARD_DK)
    for ex in (12, 18):
        x = ex + hxx + hx
        if eyes == "open":
            f.rect(x, 11 + b, 2, 2, "ink"); f.set(x, 11 + b, "white")
        elif eyes == "closed":
            f.rect(x, 12 + b, 2, 1, "ink")
        elif eyes == "wide":
            f.rect(x, 10 + b, 2, 3, "ink"); f.set(x, 10 + b, "white")

    hand = {}
    for side, pose in (("l", la), ("r", ra)):
        x = (7 if side == "l" else 22) + L
        inward = 1 if side == "l" else -1
        if pose == "down":
            f.rect(x, 17 + b, 3, 6, TUNIC); f.rect(x, 23 + b, 3, 2, "skin")
        elif pose == "up":
            f.rect(x - inward, 9 + b, 3, 9, TUNIC); f.rect(x - inward, 7 + b, 3, 2, "skin")
            hand[side] = (x - inward, 7 + b)
        elif pose in ("fwd", "fwd2"):
            y = 18 if pose == "fwd" else 17
            f.rect(x + inward, y + b, 3, 3, TUNIC); f.rect(x + inward * 2 + stir, y + 3 + b, 3, 2, "skin")
            hand[side] = (x + inward * 2 + stir, y + 3 + b)
        elif pose == "face":
            f.rect(x, 16 + b, 3, 4, TUNIC); f.rect(x + inward * 2, 14 + b, 3, 3, "skin")
        elif pose == "out":
            f.rect(x + (-2 if side == "l" else 1), 17 + b, 4, 3, TUNIC)
            f.rect(x + (-4 if side == "l" else 5), 17 + b, 2, 3, "skin")
            hand[side] = (x + (-4 if side == "l" else 5), 17 + b)

    if prop == "tankard":
        f.rect(25, 12 + b, 4, 5, "wood"); f.rect(25, 12 + b, 4, 1, "white"); f.rect(25, 15 + b, 4, 1, "wood_dk")
    elif prop == "tankard_low":
        f.rect(25, 19 + b, 4, 5, "wood"); f.rect(25, 19 + b, 4, 1, "white"); f.rect(25, 22 + b, 4, 1, "wood_dk")
    elif prop == "book":
        f.rect(11, 19 + b, 10, 5, "red_dk"); f.rect(12, 20 + b, 8, 3, "cream"); f.rect(15, 19 + b, 2, 5, "red_dk")
    elif prop == "hammer_up":
        hx_, hy = hand["r"]
        f.rect(hx_ + 1, hy - 3, 1, 3, "wood"); f.rect(hx_ - 1, hy - 5, 5, 3, "pale"); f.rect(hx_ - 1, hy - 3, 5, 1, "rock")
    elif prop == "hammer_mid":
        hx_, hy = hand["r"]
        f.rect(hx_, hy - 4, 1, 4, "wood"); f.rect(hx_ - 3, hy - 7, 5, 3, "pale"); f.rect(hx_ - 3, hy - 5, 5, 1, "rock")
    elif prop == "hammer_down":
        hx_, hy = hand["r"]
        f.rect(hx_ + 3, hy, 2, 1, "wood"); f.rect(hx_ + 4, hy - 2, 3, 5, "pale"); f.rect(hx_ + 4, hy + 2, 3, 1, "rock")
    elif prop == "pin":
        hy = hand["l"][1]
        f.rect(8, hy + 1, 16, 2, "cream"); f.rect(6, hy + 1, 2, 1, "wood"); f.rect(24, hy + 1, 2, 1, "wood")
    elif prop == "spoon":
        hx_, hy = hand["r"]
        f.rect(hx_ + 1, hy - 3, 1, 8, "wood")

    f.outline()

    if mark and mark.startswith("dots"):
        for i in range(int(mark[4])):
            f.rect(23 + i * 3, 1, 2, 2, "white")
    elif mark == "!":
        f.rect(27, 1, 2, 6, "red"); f.rect(27, 8, 2, 2, "red")
    elif mark and mark.startswith("z"):
        for i in range(int(mark[1])):
            x, y = 24 + i * 2, 7 - i * 3
            f.rect(x, y, 3, 1, "white"); f.set(x + 1, y + 1, "white"); f.rect(x, y + 2, 3, 1, "white")
    elif mark == "spark":
        for x, y in ((2, 3), (28, 2), (3, 12), (28, 12)):
            f.rect(x, y, 2, 2, "yellow")
    elif mark == "strike":
        f.dots([(26, 17), (29, 16), (30, 19), (24, 15)], "yellow")
    return f


# The first eleven rows are the engine's contract; the rest are optional work poses a scene can ask for.
ANIMS = [
    ("idle_breathe", 3, True, [dict(), dict(bob=1), dict(bob=1), dict(eyes="closed")]),
    ("idle_sip", 5, False, [dict(ra="fwd", prop="tankard_low"), dict(ra="face", prop="tankard"), dict(ra="face", prop="tankard", eyes="closed"),
                            dict(ra="face", prop="tankard", eyes="closed"), dict(ra="face", prop="tankard"), dict(ra="fwd", prop="tankard_low")]),
    ("idle_stretch", 5, False, [dict(la="out", ra="out"), dict(la="up", ra="up"), dict(la="up", ra="up", eyes="closed", bob=1),
                                dict(la="up", ra="up", eyes="closed"), dict(la="out", ra="out"), dict()]),
    ("idle_read", 4, False, [dict(la="fwd", ra="fwd", prop="book")] * 2 + [dict(la="fwd", ra="fwd", prop="book", hx=1)] * 2 +
                            [dict(la="fwd", ra="fwd2", prop="book")] + [dict(la="fwd", ra="fwd", prop="book", hx=-1)] * 2 + [dict()]),
    ("idle_look", 4, False, [dict(hx=-1), dict(hx=-1), dict(), dict(hx=1), dict(hx=1), dict()]),
    ("think", 3, True, [dict(ra="face", hx=1, mark="dots1"), dict(ra="face", hx=1, mark="dots2"),
                        dict(ra="face", hx=1, mark="dots3"), dict(ra="face", hx=1, eyes="closed", mark="dots3")]),
    ("type", 8, True, [dict(la="fwd", ra="fwd2"), dict(la="fwd2", ra="fwd"), dict(la="fwd", ra="fwd2", bob=1), dict(la="fwd2", ra="fwd")]),
    ("talk", 5, True, [dict(ra="out", lean=1, mouth="open"), dict(ra="out", lean=1, bob=1), dict(la="out", lean=-1, mouth="open"), dict(la="out", lean=-1, bob=1)]),
    ("alert", 4, True, [dict(la="up", eyes="wide", mouth="open", mark="!"), dict(la="up", eyes="wide", mouth="open", bob=1)]),
    ("celebrate", 8, False, [dict(la="out", ra="out"), dict(la="up", ra="up", mark="spark", mouth="open"), dict(la="up", ra="up", bob=1),
                             dict(la="up", ra="up", mark="spark", mouth="open"), dict(la="out", ra="out", bob=1), dict(eyes="closed")]),
    ("sleep", 2, True, [dict(eyes="closed", bob=1, mark="z1"), dict(eyes="closed", bob=1, mark="z2"),
                        dict(eyes="closed", bob=2, mark="z3"), dict(eyes="closed", bob=2)]),
    ("hammer", 6, True, [dict(ra="up", prop="hammer_up"), dict(ra="out", prop="hammer_mid"),
                         dict(ra="fwd", prop="hammer_down", bob=1, mark="strike"), dict(ra="out", prop="hammer_mid")]),
    ("knead", 5, True, [dict(la="fwd", ra="fwd", prop="pin", bob=1), dict(la="fwd2", ra="fwd2", prop="pin"),
                        dict(la="fwd", ra="fwd", prop="pin", bob=1, eyes="closed"), dict(la="fwd2", ra="fwd2", prop="pin")]),
    ("stir", 5, True, [dict(ra="fwd", prop="spoon", stir=s, bob=b) for s, b in ((0, 0), (-1, 1), (-2, 0), (-1, 0))]),
]
REQUIRED = 11


def character():
    out = Img(F * COLS, F * len(ANIMS))
    for row, (_, _, _, frames) in enumerate(ANIMS):
        assert len(frames) <= COLS
        for col, kw in enumerate(frames):
            out.blit(figure(**kw), col * F, row * F)
    return out


# ---------- portrait ----------

P = 20
PORTRAIT_STATES = ["idle", "thinking", "working", "talking", "alert", "done", "sleeping"]


def portrait(state):
    f = Img(P, P)
    horn = [(3, 6), (2, 6), (2, 5), (1, 5), (1, 4), (1, 3), (2, 2)]
    f.dots(horn + [(P - 1 - x, y) for x, y in horn], "cream")
    f.rows(0, 1, [(6, 8), (5, 10), (4, 12), (4, 12), (4, 12), (4, 12)], HELM)
    f.rect(6, 3, 2, 3, "white")
    f.rect(3, 7, 14, 1, HELM_DK)
    f.rect(4, 8, 12, 5, "skin")
    f.rows(0, 11, [(4, 12), (4, 12), (3, 14), (3, 14), (3, 14), (3, 14), (4, 12), (5, 10), (7, 6)], BEARD)
    f.rect(6, 11, 8, 1, "skin"); f.rect(9, 12, 2, 1, "skin_dk")
    f.rect(9, 10, 2, 3, "skin_dk")
    f.dots([(4, 15), (15, 15), (6, 17), (13, 17), (9, 18), (10, 18), (3, 14), (16, 14)], BEARD_DK)

    eyes = {"idle": "open", "thinking": "up", "working": "squint", "talking": "open", "alert": "wide", "done": "happy", "sleeping": "closed"}[state]
    for x in (6, 12):
        if eyes == "open":
            f.rect(x, 9, 2, 2, "ink"); f.set(x, 9, "white")
        elif eyes == "up":
            f.rect(x, 8, 2, 2, "ink"); f.set(x + 1, 8, "white")
        elif eyes == "squint":
            f.rect(x, 10, 2, 1, "ink"); f.rect(x, 9, 2, 1, BEARD_DK)
        elif eyes == "wide":
            f.rect(x, 8, 2, 3, "ink"); f.set(x, 8, "white")
        elif eyes == "happy":
            f.dots([(x, 10), (x + 1, 9), (x + 2, 10)] if x == 6 else [(x - 1, 10), (x, 9), (x + 1, 10)], "ink")
        else:
            f.rect(x, 10, 2, 1, "ink")
    if state in ("talking", "alert"):
        f.rect(8, 14, 4, 2, "ink"); f.rect(9, 15, 2, 1, "red")
    elif state == "done":
        f.rect(7, 14, 6, 1, "white"); f.dots([(6, 13), (13, 13)], BEARD_DK)
    else:
        f.rect(8, 14, 4, 1, BEARD_DK)
    if state == "working":
        f.dots([(16, 9), (16, 10)], "sky")
    f.outline()
    return f


def portraits():
    return sheet([portrait(s) for s in PORTRAIT_STATES])


def avatar_swaps():
    """theme.json "avatars": hex-to-hex swaps of the key colours."""
    from .pixels import HEX
    out = []
    for ident, name, *parts in AVATARS:
        swap = {}
        for key, pair in zip(("beard", "tunic", "helmet"), parts):
            if pair:
                for src, dst in zip(KEYS[key], pair):
                    swap[HEX[src]] = HEX[dst]
        out.append({"id": ident, "name": name, "swap": swap})
    return out
