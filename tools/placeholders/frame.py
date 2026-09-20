"""The rock around a chamber, the connector pieces that open it, and the minimised orb.

Seams: stacked windows abut with no gap, so what crosses an edge is painted from the canvas row or
column alone (never from the piece) and the left/right pieces are mirror images. That makes the
bottom row of `ladder_bottom` equal the top row of `ladder_top`, and the outer column of
`tunnel_right` equal the outer column of `tunnel_left`, whatever the scene.
"""
from .layout import W, H, BAR, SIDE, FLOOR, LADDER_W, LADDER_BOTTOM_TOP, TUNNEL_TOP, TUNNEL_H, TUNNEL_W, ORB
from .pixels import Img, noise, sheet


def rock(img, x, y, w, h, seed=1):
    img.rect(x, y, w, h, "rock")
    for j in range(y, y + h):
        for i in range(x, x + w):
            n = noise(i // 2, j, seed)          # specks come in pairs: reads as chisel marks, not static
            if n < 0.07:
                img.set(i, j, "rock_dk")
            elif n > 0.95:
                img.set(i, j, "rock_lt")


def overlay():
    f = Img(W, H)
    rock(f, 0, 0, W, H)
    # the chamber opening, with a roughly hewn edge
    for y in range(BAR, FLOOR):
        jag_l = 1 if noise(0, y // 3, 7) < 0.35 else 0
        jag_r = 1 if noise(1, y // 3, 7) < 0.35 else 0
        for x in range(SIDE + jag_l, W - SIDE - jag_r):
            f.set(x, y, None)
        f.set(SIDE + jag_l - 1, y, "rock_dk"); f.set(W - SIDE - jag_r, y, "rock_dk")
    for x, y in ((SIDE, BAR), (SIDE + 1, BAR), (SIDE, BAR + 1), (SIDE, FLOOR - 1)):
        f.set(x, y, "rock"); f.set(W - 1 - x, y, "rock")
    # header lintel: calm and dark so the title reads
    f.rect(0, 0, W, BAR, "rock_dk"); f.rect(0, 0, W, 1, "rock"); f.rect(0, BAR - 1, W, 1, "ink")
    # floor slab, then strata down to the seam
    f.rect(0, FLOOR, W, 1, "stone"); f.rect(0, FLOOR + 1, W, 1, "rock_lt")
    for x in range(W):
        if noise(x // 5, 0, 3) < 0.5:
            f.set(x, FLOOR + 7, "rock_dk")
        if noise(x // 7, 1, 3) < 0.4:
            f.set(x, FLOOR + 13, "rock_dk")
    return f


def _ladder(y0, y1, shaft):
    """Rows y0..y1 of the ladder column; `shaft` is the range of canvas rows that are solid rock."""
    f = Img(LADDER_W, y1 - y0)
    for y in range(y0, y1):
        j = y - y0
        if y in shaft:
            f.rect(0, j, LADDER_W, 1, "ink"); f.set(0, j, "rock_dk"); f.set(LADDER_W - 1, j, "rock_dk")
        for x in (2, 10):
            f.set(x, j, "wood_lt"); f.set(x + 1, j, "wood")
        if y % 4 == 2:
            f.rect(4, j, 6, 1, "wood_lt")
        elif y % 4 == 3 and y not in shaft:
            f.rect(4, j, 6, 1, "wood_dk")
    return f


def ladder_top():
    return _ladder(0, FLOOR, range(0, BAR))


def ladder_bottom():
    return _ladder(LADDER_BOTTOM_TOP, H, range(FLOOR, H))


def sealed_top():
    f = Img(LADDER_W, BAR)
    f.rect(1, 2, 12, 7, "wood_dk"); f.rect(2, 3, 10, 5, "wood")
    f.rect(4, 2, 1, 7, "rock_lt"); f.rect(9, 2, 1, 7, "rock_lt")
    f.rect(6, 5, 2, 2, "stone")
    return f


def sealed_bottom():
    f = Img(LADDER_W, 3)
    f.rect(0, 0, LADDER_W, 3, "wood_dk"); f.rect(1, 0, 12, 2, "wood")
    f.rect(3, 0, 1, 3, "rock_lt"); f.rect(10, 0, 1, 3, "rock_lt"); f.rect(6, 0, 2, 1, "stone")
    return f


def _tunnel(open_):
    """The left-hand piece; the right-hand one is its mirror image."""
    f = Img(TUNNEL_W, TUNNEL_H)
    mouth_top, floor = 6, FLOOR - TUNNEL_TOP
    if open_:
        f.rect(0, mouth_top, 7, floor - mouth_top, "rock_dk")
        f.rect(0, mouth_top, 7, 3, "ink")
        f.rect(0, floor, TUNNEL_W, 1, "stone"); f.rect(0, floor + 1, TUNNEL_W, 1, "rock_lt")
        f.rect(0, floor - 1, 7, 1, "wood_dk")                     # cart rail
        f.dots([(1, floor - 2), (5, floor - 2)], "rock_lt")
        f.rect(3, mouth_top, 1, 2, "rock_lt"); f.rect(2, mouth_top + 2, 3, 3, "yellow"); f.set(3, mouth_top + 3, "white")
    else:
        rock(f, 0, mouth_top, 7, floor - mouth_top, seed=5)
        for i in range(7):                                        # two crossed planks
            f.rect(i, mouth_top + 3 + i * 2, 1, 3, "wood_lt"); f.rect(6 - i, mouth_top + 3 + i * 2, 1, 3, "wood")
    f.rect(6, mouth_top - 1, 3, floor - mouth_top + 1, "wood"); f.rect(6, mouth_top - 1, 1, floor - mouth_top + 1, "wood_lt")
    f.rect(8, mouth_top - 1, 1, floor - mouth_top + 1, "wood_dk")
    f.rect(0, 2, TUNNEL_W, 4, "wood"); f.rect(0, 2, TUNNEL_W, 1, "wood_lt"); f.rect(0, 5, TUNNEL_W, 1, "wood_dk")
    return f


def tunnel_left(open_=True):
    return _tunnel(open_)


def tunnel_right(open_=True):
    return _tunnel(open_).mirrored()


# ---------- orb ----------

def _annulus(img, r_in, r_out, colour, when=lambda x, y: True):
    c = ORB / 2
    for y in range(ORB):
        for x in range(ORB):
            d = ((x + 0.5 - c) ** 2 + (y + 0.5 - c) ** 2) ** 0.5
            if r_in < d <= r_out and when(x, y):
                img.set(x, y, colour)


def orb_back():
    f = Img(ORB, ORB)
    f.disc(ORB / 2, ORB / 2, 11.5, "rock_dk")
    f.speckle(0, 0, ORB, ORB, "rock", 0.08, 11, only="rock_dk")
    return f


def orb_ring():
    f = Img(ORB, ORB)
    _annulus(f, 9.5, 14, "ink")
    _annulus(f, 10.5, 13, "stone")
    _annulus(f, 10.5, 13, "rock_lt", lambda x, y: x + y > ORB + 3)
    _annulus(f, 10.5, 11.5, "rock", lambda x, y: x + y > ORB + 3)
    _annulus(f, 12, 13, "pale", lambda x, y: x + y < ORB - 8)
    for x, y in ((4, 4), (22, 4), (4, 22), (22, 22)):             # iron studs
        f.rect(x, y, 2, 2, "rock_dk")
    f.disc(ORB / 2, 24.5, 4, "ink")                               # gem socket
    return f


def orb_gem():
    """Light on purpose: the engine multiplies it by the state colour."""
    f = Img(6, 6)
    f.rows(0, 0, [(2, 2), (1, 4), (0, 6), (0, 6), (1, 4), (2, 2)], "white")
    f.dots([(3, 3), (4, 3), (3, 4), (2, 4), (4, 2)], "pale")
    return f


def orb_alert():
    f = Img(ORB, ORB)
    _annulus(f, 12, 14, "red")
    _annulus(f, 12, 14, "yellow", lambda x, y: (x // 3 + y // 3) % 2 == 0)
    return f


def orb_work():
    """A tiny pick swinging, four 10x10 frames."""
    shapes = [
        ([(3, 8), (4, 7), (4, 6), (5, 5), (5, 4)], [(3, 3), (4, 2), (5, 2), (6, 3), (7, 4), (7, 5)], []),
        ([(2, 8), (3, 7), (4, 6), (5, 5), (6, 4)], [(5, 2), (6, 2), (7, 3), (8, 4), (8, 5), (7, 6)], []),
        ([(2, 8), (3, 8), (4, 7), (5, 7), (6, 7)], [(7, 4), (7, 5), (8, 6), (8, 7), (8, 8), (7, 9)], [(9, 9), (5, 9), (9, 5)]),
        ([(2, 8), (3, 7), (4, 6), (5, 5), (6, 4)], [(5, 2), (6, 2), (7, 3), (8, 4), (8, 5), (7, 6)], []),
    ]
    frames = []
    for handle, head, sparks in shapes:
        f = Img(10, 10)
        f.dots(handle, "wood_lt"); f.dots(head, "pale")
        f.outline()
        f.dots(sparks, "yellow")
        frames.append(f)
    return sheet(frames)
