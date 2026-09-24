"""Vital-sign props, dwarf style. One sheet per prop, states side by side; the engine decides what
each name means (docs/ART.md, "Props"). Scenes place them; the sizes here are the theme's.

Everything here is dressed as something that belongs a thousand feet underground: an ore rack rather
than a bookshelf, a shaft to the surface rather than a window, a carved stone dial rather than a
clock face. The state COUNTS and the hit sizes are the contract and never change.
"""
from .layout import BENCH_TOP, bl
from .pixels import Img, sheet

# What the ore rack fills up with, poorest first: the deeper the context fills, the better the haul.
ORE = ("rock_lt", "copper", "copper", "sand", "teal", "purple", "yellow", "pink", "sky", "green_lt", "white")


def window(f, i):
    """A DAYSTONE, not a window. There is no sky down here, so the prop that tells the time of day
    is a cluster of crystals growing out of the seam, which keeps the hours the way the surface
    does: white and cold at midday, amber at dusk, a dim blue ember at night. Three states, in the
    order the engine sends them (docs/ART.md, "Props").
    """
    core, face, edge, halo = (("white", "sky", "pale", "stone"),
                              ("cream", "yellow", "sand", "wood_lt"),
                              ("sky", "blue", "blue_dk", "rock_lt"))[i]
    # what it throws on the rock around it, dithered so it sits on the wall instead of on top of it
    for y in range(20):
        for x in range(26):
            d = ((x - 12) ** 2 + ((y - 13) * 1.35) ** 2) ** 0.5
            if d / 13.0 + ((x * 5 + y * 3) % 5) / 11.0 < 0.92:
                f.set(x, y, halo)
    gem = Img(26, 20)
    gem.rows(2, 13, [(2, 18), (1, 20), (0, 22), (0, 22), (0, 22), (1, 20)], "rock_dk")   # the socket
    gem.rows(2, 13, [(2, 18), (1, 6)], "rock_lt")
    for x, tip, w in ((5, 9, 3), (9, 3, 4), (14, 7, 3), (18, 10, 4)):                    # the crystals
        gem.rect(x, tip, w, 15 - tip, face)
        gem.rect(x, tip, 1, 15 - tip, edge)
        gem.rows(x, tip - 2, [(w // 2, 1), (0, w)], face)
        gem.set(x + w // 2, tip - 2, core)
        gem.rect(x + 1, tip + 1, 1, 13 - tip, core)
    gem.outline("ink")
    f.blit(gem, 0, 0)


def bookshelf(f, i):
    """An ore rack: timber shelves of picked stone, filling left to right, bottom shelf first.
    The chunks are all different shapes, so it still counts under the engine's red overload wash."""
    f.rect(0, 0, 30, 30, "wood"); f.rect(0, 0, 30, 1, "wood_lt"); f.rect(29, 0, 1, 30, "wood_dk")
    f.rect(2, 2, 26, 12, "rock"); f.rect(2, 16, 26, 12, "rock")         # the rock the rack is set into
    f.rect(2, 2, 26, 2, "rock_dk"); f.rect(2, 16, 26, 2, "rock_dk")
    f.speckle(2, 4, 26, 10, "rock_dk", 0.12, 33, only="rock")
    f.speckle(2, 18, 26, 10, "rock_dk", 0.12, 35, only="rock")
    f.rect(2, 13, 26, 2, "wood_lt"); f.rect(2, 27, 26, 2, "wood_lt")
    f.rect(2, 14, 26, 1, "wood_dk"); f.rect(2, 28, 26, 1, "wood_dk")
    for n in range(i):                       # the bottom shelf fills first, left to right
        shelf, slot = divmod(n, 5)
        h = 6 + (n % 3)
        x, base = 3 + slot * 5, 27 if shelf == 0 else 13
        ore = ORE[n % len(ORE)]
        f.rect(x, base - h, 5, h, "rock_lt")                            # the lump of stone
        f.rect(x, base - h, 1, h, "stone")
        f.rows(x + 1, base - h + 1, [(0, 3), (0, 3), (1, 2)] + [(0, 3)] * (h - 4), ore)
        f.set(x + 1, base - h + 1, "white")


def coinjar(f, i):
    """An iron-banded pot the take goes into."""
    f.rect(1, 1, 8, 11, "rock_lt"); f.rect(2, 2, 6, 9, "ink"); f.rect(2, 0, 6, 2, "stone")
    f.rect(1, 5, 8, 1, "rock_dk"); f.rect(1, 9, 8, 1, "rock_dk")
    f.rect(2, 11 - i, 6, i, "yellow")
    if i:
        f.rect(3, 11 - i, 2, 1, "white")
    if i > 2:
        f.rect(2, 10, 6, 1, "sand")


def papers(f, i):
    """Parchments, curling, held down with a pebble."""
    for n in range(i):
        f.rect(1 + (n % 2), 7 - n, 12, 1, "cream" if n % 2 == 0 else "sand")
    if i:
        f.rect(3 + (i % 2), 8 - i, 6, 1, "wood")
        f.rect(9, 7, 2, 1, "rock_lt")


def clock(f, i):
    """A dial chiselled into a slab of pale stone, with one copper hand."""
    f.disc(6.5, 6.5, 6.5, "rock_dk"); f.disc(6.5, 6.5, 5.5, "pale")
    f.disc(6.5, 6.5, 4.5, "stone")
    for x, y in ((6, 1), (11, 6), (6, 11), (1, 6)):
        f.set(x, y, "ink")
    dx, dy = ((0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1))[i]
    for k in range(1, 5 if dx == 0 or dy == 0 else 4):
        f.set(6 + dx * k, 6 + dy * k, "copper")
    f.set(6, 6, "ink")


def hourglass(f, i):
    """Brass-capped glass in a timber cradle."""
    f.rect(0, 0, 8, 1, "wood_lt"); f.rect(0, 9, 8, 1, "wood_lt")
    f.set(0, 1, "wood"); f.set(7, 1, "wood"); f.set(0, 8, "wood"); f.set(7, 8, "wood")
    f.rows(0, 1, [(1, 6), (1, 6), (2, 4), (3, 2), (3, 2), (2, 4), (1, 6), (1, 6)], "pale")
    top, bottom = ((3, 0), (2, 1), (1, 2), (0, 3))[i]   # sand runs from the top bulb to the bottom one
    bulb = ((3, 2), (2, 4), (2, 4))
    for k in range(top):
        f.rect(bulb[k][0], 4 - k, bulb[k][1], 1, "yellow")
    for k in range(bottom):
        f.rect(bulb[2 - k][0], 8 - k, bulb[2 - k][1], 1, "yellow")
    if 0 < i < 3:
        f.set(4, 5, "yellow")


# name, frame, states, default position (bottom-left, from the canvas bottom-left), z, painter
PROPS = [
    ("window", (26, 20), 3, bl(33, 18, 20), 0.5, window),
    ("bookshelf", (30, 30), 11, bl(32, 60, 30), 0.5, bookshelf),
    ("coinjar", (10, 12), 9, bl(35, 48, 12), 0.6, coinjar),
    ("clock", (13, 13), 8, bl(48, 47, 13), 0.6, clock),
    ("papers", (14, 8), 6, bl(69, BENCH_TOP - 8, 8), 2.5, papers),
    ("hourglass", (8, 10), 4, bl(123, BENCH_TOP - 10, 10), 2.5, hourglass),
]


def sheets():
    for name, (w, h), states, _, _, paint in PROPS:
        frames = []
        for i in range(states):
            frame = Img(w, h)
            paint(frame, i)
            frames.append(frame)
        yield name, sheet(frames)
