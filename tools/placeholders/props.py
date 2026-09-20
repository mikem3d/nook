"""Vital-sign props, dwarf style. One sheet per prop, states side by side; the engine decides what
each name means (docs/ART.md, "Props"). Scenes place them; the sizes here are the theme's.
"""
from .layout import BENCH_TOP, bl
from .pixels import Img, sheet

BOOKS = ("red", "blue", "yellow", "purple", "teal")


def window(f, i):
    """A skylight cut through the rock: day, dusk, night."""
    arch = [(6, 14), (4, 18), (2, 22), (1, 24)] + [(0, 26)] * 16
    f.rows(0, 0, arch, "stone")
    sky = ("sky", "orange", "blue_dk")[i]
    f.rows(2, 2, [(6, 10), (4, 14), (2, 18), (1, 20)] + [(0, 22)] * 13, sky)
    if i == 0:
        f.rect(16, 5, 4, 4, "yellow"); f.rect(4, 9, 8, 2, "white"); f.rect(6, 8, 4, 1, "white")
    elif i == 1:
        f.rect(2, 13, 22, 4, "red"); f.rect(14, 10, 6, 4, "yellow"); f.rect(2, 15, 22, 2, "red_dk")
    else:
        f.rect(15, 5, 4, 4, "white"); f.rect(17, 5, 2, 3, "blue_dk")
        f.dots([(5, 6), (9, 12), (12, 4), (20, 13), (6, 14)], "white")
    f.rect(8, 2, 1, 15, "ink"); f.rect(17, 2, 1, 15, "ink")
    f.rect(0, 17, 26, 1, "pale"); f.rect(0, 18, 26, 2, "rock_lt")


def bookshelf(f, i):
    f.rect(0, 0, 30, 30, "wood"); f.rect(0, 0, 30, 1, "wood_lt")
    f.rect(2, 2, 26, 12, "wood_dk"); f.rect(2, 16, 26, 12, "wood_dk")
    for n in range(i):                       # the bottom shelf fills first, left to right
        shelf, slot = divmod(n, 5)
        h = 10 - (n % 3)
        x, base = 3 + slot * 5, 28 if shelf == 0 else 14
        f.rect(x, base - h, 4, h, BOOKS[(n * 2) % 5]); f.rect(x, base - h + 2, 4, 1, "cream")


def coinjar(f, i):
    f.rect(1, 1, 8, 11, "pale"); f.rect(2, 2, 6, 9, "rock_dk"); f.rect(2, 0, 6, 2, "wood_lt")
    f.rect(2, 11 - i, 6, i, "yellow")
    if i:
        f.rect(3, 11 - i, 2, 1, "white")
    if i > 2:
        f.rect(2, 10, 6, 1, "sand")


def papers(f, i):
    for n in range(i):
        f.rect(1 + (n % 2), 7 - n, 12, 1, "white" if n % 2 == 0 else "pale")
    if i:
        f.rect(3 + (i % 2), 8 - i, 6, 1, "stone")


def clock(f, i):
    f.disc(6.5, 6.5, 6.5, "wood_dk"); f.disc(6.5, 6.5, 5.5, "white")
    dx, dy = ((0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1))[i]
    for k in range(1, 5 if dx == 0 or dy == 0 else 4):
        f.set(6 + dx * k, 6 + dy * k, "red")
    f.set(6, 6, "ink")


def hourglass(f, i):
    f.rect(0, 0, 8, 1, "wood_lt"); f.rect(0, 9, 8, 1, "wood_lt")
    f.rows(0, 1, [(1, 6), (1, 6), (2, 4), (3, 2), (3, 2), (2, 4), (1, 6), (1, 6)], "sky")
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
