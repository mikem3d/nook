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


def _ore(f, x, base, h, n):
    """A lump of picked stone with the ore showing in its broken face."""
    ore = ORE[n % len(ORE)]
    f.rect(x, base - h, 5, h, "rock_lt")
    f.rect(x, base - h, 1, h, "stone")
    f.rows(x + 1, base - h + 1, [(0, 3), (0, 3), (1, 2)] + [(0, 3)] * (h - 4), ore)
    f.set(x + 1, base - h + 1, "white")


def _ingots(f, x, base, h, n):
    """Cast bars, stacked flat: the forge's rack holds metal, not rock."""
    for k in range(base - h, base, 2):
        f.rect(x, k, 5, 2, "copper" if (k + n) % 4 else "sand")
        f.rect(x, k, 5, 1, "sand" if (k + n) % 4 else "cream")
        f.set(x + 4, k + 1, "wood_dk")


def _jars(f, x, base, h, n):
    """Proving jars: pale glass, a cloth cap tied over the neck."""
    f.rows(x, base - h, [(1, 3), (0, 5)], "pale")
    f.rect(x, base - h + 2, 5, h - 2, "pale")
    f.rect(x + 1, base - h + 3, 3, h - 4, ("cream", "sand", "wood_lt")[n % 3])
    f.rows(x, base - h, [(1, 3)], ("red", "sky", "green_lt")[n % 3])
    f.set(x, base - h + 3, "white")


def _casks(f, x, base, h, n):
    """Little casks on their sides, hooped."""
    f.rows(x, base - h, [(1, 3)] + [(0, 5)] * (h - 2) + [(1, 3)], "wood")
    f.rect(x, base - h + 2, 5, 1, "sand"); f.rect(x, base - 3, 5, 1, "sand")
    f.rect(x + 1, base - h + 1, 1, h - 2, "wood_lt")
    f.set(x + 3, base - h + 4, "copper" if n % 2 else "wood_dk")


def _cores(f, x, base, h, n):
    """Grown cores in an iron cradle: the lab's rack is a light of its own."""
    colour = ("purple", "sky", "teal", "green_lt", "pink")[n % 5]
    f.rect(x, base - 2, 5, 2, "rock_dk"); f.rect(x, base - 2, 5, 1, "rock_lt")
    f.rows(x + 1, base - h, [(1, 1), (0, 3)] + [(0, 3)] * (h - 4), colour)
    f.rect(x + 2, base - h + 1, 1, h - 3, "white")
    f.set(x + 1, base - 3, "ink")


def _gems(f, x, base, h, n):
    """Graded stones on a felt pad: the treasury's rack is a jeweller's tray."""
    colour = ("teal", "pink", "yellow", "sky", "red", "green_lt")[n % 6]
    f.rect(x, base - 2, 5, 2, "red_dk")
    f.rows(x + 1, base - min(h, 7), [(1, 1), (0, 3), (0, 3), (1, 1)], colour)
    f.set(x + 2, base - min(h, 7), "white")


def _baskets(f, x, base, h, n):
    """Picking baskets, woven, with the crop showing over the rim."""
    f.rows(x, base - h + 2, [(0, 5)] * (h - 2), "wood_lt")
    for k in range(base - h + 3, base, 2):
        f.rect(x, k, 5, 1, "wood")
    f.rect(x, base - h + 2, 5, 1, "sand")
    f.rows(x + 1, base - h, [(1, 1), (0, 3)], ("cream", "pink", "teal")[n % 3])


def _kit(f, x, base, h, n):
    """Rolled bedding and a pair of boots: the bunkroom's rack holds a dwarf's own gear."""
    colour = ("red_dk", "blue_dk", "green_dk")[n % 3]
    f.rect(x, base - h, 5, h - 3, colour)
    f.rect(x, base - h, 1, h - 3, "rock_lt")
    f.rect(x, base - h + 2, 5, 1, "sand")
    f.rect(x, base - 3, 5, 3, "wood_dk"); f.rect(x, base - 3, 5, 1, "wood")


# What a chamber keeps in its rack. Same rack, same eleven states, its own contents.
KITS = {"ore": _ore, "ingots": _ingots, "jars": _jars, "casks": _casks,
        "cores": _cores, "gems": _gems, "baskets": _baskets, "kit": _kit}

# What a chamber's parchments and its pot are: a colour and a name, nothing structural.
PAPER_KITS = {"tallies": ("cream", "sand"), "orders": ("sand", "wood_lt"), "recipes": ("cream", "white"),
              "notes": ("pale", "cream"), "ledgers": ("sand", "cream")}
JAR_KITS = {"coins": "yellow", "copper": "copper", "silver": "pale"}


def bookshelf(f, i, kit="ore"):
    """An ore rack: timber shelves of picked stone, filling left to right, bottom shelf first.
    The chunks are all different shapes, so it still counts under the engine's red overload wash.
    A chamber dresses the same rack with whatever it actually stacks (`kit`)."""
    f.rect(0, 0, 30, 30, "wood"); f.rect(0, 0, 30, 1, "wood_lt"); f.rect(29, 0, 1, 30, "wood_dk")
    # A boarded back, not a hole in the rock: an empty shelf has to read as an empty SHELF at 1x,
    # and a dark cavity behind it just reads as a picture frame with nothing in it.
    f.rect(2, 2, 26, 12, "wood_dk"); f.rect(2, 16, 26, 12, "wood_dk")
    for y in (2, 6, 10, 16, 20, 24):
        f.rect(2, y, 26, 3, "wood"); f.rect(2, y, 26, 1, "wood_dk")
    f.speckle(2, 3, 26, 11, "wood_dk", 0.10, 33, only="wood")
    f.speckle(2, 17, 26, 11, "wood_dk", 0.10, 35, only="wood")
    f.rect(2, 13, 26, 2, "wood_lt"); f.rect(2, 27, 26, 2, "wood_lt")   # the shelf boards, lit on top
    f.rect(2, 14, 26, 1, "wood_dk"); f.rect(2, 28, 26, 1, "wood_dk")
    f.rect(1, 1, 1, 28, "wood_lt"); f.rect(1, 1, 28, 1, "wood_lt")     # the uprights, catching light
    f.dots([(3, 15), (26, 15), (3, 29), (26, 29)], "rock_lt")          # iron brackets
    paint = KITS.get(kit, _ore)
    for n in range(i):                       # the bottom shelf fills first, left to right
        shelf, slot = divmod(n, 5)
        h = 6 + (n % 3)
        paint(f, 3 + slot * 5, 27 if shelf == 0 else 13, h, n)


def coinjar(f, i, kit="coins"):
    """An iron-banded pot the take goes into, filled with whatever this chamber is paid in."""
    metal = JAR_KITS.get(kit, "yellow")
    f.rect(1, 1, 8, 11, "rock_lt"); f.rect(2, 2, 6, 9, "ink"); f.rect(2, 0, 6, 2, "stone")
    f.rect(1, 5, 8, 1, "rock_dk"); f.rect(1, 9, 8, 1, "rock_dk")
    f.rect(2, 11 - i, 6, i, metal)
    if i:
        f.rect(3, 11 - i, 2, 1, "white")
    if i > 2:
        f.rect(2, 10, 6, 1, "sand" if metal != "pale" else "stone")


def papers(f, i, kit="tallies"):
    """Parchments, curling, held down with a pebble. Each chamber writes on its own stock."""
    light, dark = PAPER_KITS.get(kit, ("cream", "sand"))
    for n in range(i):
        f.rect(1 + (n % 2), 7 - n, 12, 1, light if n % 2 == 0 else dark)
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


# Which props a chamber may dress, and what it may dress them as.
DRESSED = {"bookshelf": KITS, "papers": PAPER_KITS, "coinjar": JAR_KITS}


def one(name, kit=None):
    """The sheet for a prop, optionally filled with one chamber's own kit."""
    for prop, (w, h), states, _, _, paint in PROPS:
        if prop != name:
            continue
        frames = []
        for i in range(states):
            frame = Img(w, h)
            paint(frame, i, kit) if kit else paint(frame, i)
            frames.append(frame)
        return sheet(frames)
    raise KeyError(name)


def sheets():
    for name, _, _, _, _, _ in PROPS:
        yield name, one(name)
