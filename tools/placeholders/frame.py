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
            if n < 0.09:
                img.set(i, j, "rock_dk")
            elif n > 0.94:
                img.set(i, j, "rock_lt")


def overlay():
    """The mountain the chamber is cut out of. The sides are raw rock with a jagged edge; the block
    under the floor is bedded strata with a seam running through it, so a stack of windows reads as
    one cliff face cut open rather than as a column of picture frames.
    """
    f = Img(W, H)
    rock(f, 0, 0, W, H)
    # Strata under the floor: irregular bands, a copper seam, and loose scree resting on the lip.
    y, band = FLOOR + 4, 0
    while y < H:
        for x in range(W):
            yy = y + (1 if noise(x // 6, band, 3) < 0.45 else 0) + (1 if noise(x // 11, band, 13) < 0.3 else 0)
            f.set(x, yy, "rock_dk")
            if noise(x // 4, band, 5) < 0.3:
                f.set(x, yy + 1, "ink")
        y += 4 + int(noise(band, 8, 17) * 4)            # the bands are not evenly bedded
        band += 1
    for x in range(W):                          # one thin ore seam, pinched out in places
        if noise(x // 7, 2, 21) < 0.45:
            continue
        y = FLOOR + 9 + int(noise(x // 9, 2, 9) * 3)
        f.set(x, y, "copper" if noise(x // 4, 3, 9) < 0.25 else "wood_dk")
        f.set(x, y - 1, "ink")
    for k in range(26):                         # scree caught on the ledges
        x, y = int(noise(k, 4, 9) * (W - 3)), FLOOR + 2 + int(noise(k, 5, 9) * (H - FLOOR - 5))
        f.rect(x, y, 2, 1, "rock_lt")
    # The chamber opening, with a roughly hewn edge and the dark the rock throws just inside it.
    for y in range(BAR, FLOOR):
        jag_l = int(noise(0, y // 3, 7) * 2.6)
        jag_r = int(noise(1, y // 3, 7) * 2.6)
        for x in range(SIDE + jag_l, W - SIDE - jag_r):
            f.set(x, y, None)
        f.set(SIDE + jag_l - 1, y, "ink"); f.set(W - SIDE - jag_r, y, "ink")
        f.set(SIDE + jag_l - 2, y, "rock_dk"); f.set(W - SIDE - jag_r + 1, y, "rock_dk")
    for x, y in ((SIDE, BAR), (SIDE + 1, BAR), (SIDE, BAR + 1), (SIDE, FLOOR - 1)):
        f.set(x, y, "rock_dk"); f.set(W - 1 - x, y, "rock_dk")
    # Header lintel: calm and dark so the title reads, with a cut stone lip under it.
    f.rect(0, 0, W, BAR, "rock_dk"); f.rect(0, 0, W, 1, "rock"); f.rect(0, BAR - 1, W, 1, "ink")
    f.speckle(0, 1, W, BAR - 2, "ink", 0.10, 15, only="rock_dk")
    # The floor: a cut lip, the shadow it casts, and the grit that has collected on it.
    f.rect(0, FLOOR, W, 1, "stone"); f.rect(0, FLOOR + 1, W, 1, "rock_lt"); f.rect(0, FLOOR + 2, W, 1, "rock")
    for x in range(W):
        if noise(x // 3, 6, 11) < 0.32:
            f.set(x, FLOOR, "pale")
        if noise(x // 2, 7, 11) < 0.25:
            f.set(x, FLOOR + 1, "stone")
    return f


def _ladder(y0, y1, shaft):
    """Rows y0..y1 of the ladder column; `shaft` is the range of canvas rows that are solid rock.

    The shaft is cut THROUGH rock, so its walls are chiselled and uneven. Rows 0 and H-1 are the
    seam rows two stacked windows meet on, so their texture is keyed on x alone: whatever the two
    neighbours are, those rows match pixel for pixel (docs/ART.md, seam rule 2).
    """
    f = Img(LADDER_W, y1 - y0)
    for y in range(y0, y1):
        j, seam = y - y0, y in (0, H - 1)
        if y in shaft:
            f.rect(0, j, LADDER_W, 1, "ink")
            for side in (0, 1):
                bite = 0 if seam else int(noise(side, y, 19) * 2.2)
                for k in range(bite + 1):
                    x = k if side == 0 else LADDER_W - 1 - k
                    f.set(x, j, "rock_dk" if k == 0 else "rock")
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
    """The left-hand piece; the right-hand one is its mirror image, which is what makes the two
    outer columns match at a seam (docs/ART.md, seam rule 3).

    A tunnel is cut through rock, not framed into a wall: rough stone all round the timbering, the
    bore falling away into black, a rail and a lamp hung just inside.
    """
    f = Img(TUNNEL_W, TUNNEL_H)
    mouth_top, floor = 6, FLOOR - TUNNEL_TOP
    rock(f, 0, 0, TUNNEL_W, TUNNEL_H, seed=23)
    if open_:
        # A bore, not a doorway: the roof and the floor converge on a vanishing point off the left
        # edge, three timber sets recede into it, and the far end is lit by the next chamber.
        def roof(i):
            return mouth_top + 1 + (6 - i) // 2
        def road(i):
            return floor - 1 - (6 - i) // 3
        for i in range(7):
            f.rect(i, roof(i), 1, road(i) - roof(i) + 1, "ink")
            f.set(i, roof(i) - 1, "rock_dk")
        f.rows(0, roof(0) + 1, [(0, 3)] * (road(0) - roof(0) - 1), "warm_dk")   # daylight of the next lamp
        f.rows(0, roof(0) + 2, [(0, 2)] * max(road(0) - roof(0) - 3, 1), "warm")
        f.set(0, roof(0) + 3, "warm_lt"); f.set(1, roof(0) + 3, "warm_lt")
        for i, tone in ((5, "wood"), (3, "wood_dk"), (1, "rock_dk")):           # the sets, receding
            f.rect(i, roof(i), 1, road(i) - roof(i) + 1, tone)
            f.set(i, roof(i), "wood_lt" if tone == "wood" else tone)
            f.set(i + 1, roof(i), tone)
        for i in range(7):                                                      # the rail, converging
            f.set(i, road(i), "wood_dk")
            f.set(i, road(i) - 1, "rock_lt" if i % 2 else "stone")
        f.rect(0, floor, TUNNEL_W, 1, "stone"); f.rect(0, floor + 1, TUNNEL_W, 1, "rock_lt")
        f.rect(4, floor - 9, 2, 2, "orange"); f.set(4, floor - 10, "rock_lt"); f.set(5, floor - 9, "yellow")
    else:
        rock(f, 0, mouth_top, 7, floor - mouth_top, seed=5)
        for i in range(7):                                        # two crossed planks
            f.rect(i, mouth_top + 3 + i * 2, 1, 3, "wood_lt"); f.rect(6 - i, mouth_top + 3 + i * 2, 1, 3, "wood")
    f.rect(6, mouth_top - 1, 3, floor - mouth_top + 1, "wood"); f.rect(6, mouth_top - 1, 1, floor - mouth_top + 1, "wood_lt")
    f.rect(8, mouth_top - 1, 1, floor - mouth_top + 1, "wood_dk")
    f.rect(0, 2, TUNNEL_W, 4, "wood"); f.rect(0, 2, TUNNEL_W, 1, "wood_lt"); f.rect(0, 5, TUNNEL_W, 1, "wood_dk")
    f.rect(0, floor + 2, TUNNEL_W, TUNNEL_H - floor - 2, "rock_dk")
    f.rect(0, 0, TUNNEL_W, 2, "rock_dk")
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
