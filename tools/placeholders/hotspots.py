"""Hotspots: the props that are buttons (docs/ART.md, "Hotspots"). A sheet has one column per level
and two rows: idle on top, hover below. Every frame keeps a 1 px transparent margin so the hover
outline fits inside it. `news` is a small overlay the engine shows when something changed.
"""
from .layout import bl
from .pixels import Img

# Where each of the five parchments hangs on the cork, inside the 22x22 frame.
SLOTS = ((3, 4), (9, 3), (15, 4), (5, 12), (12, 11))


def board(f, level):
    """A notice board; `level` parchments are pinned to it."""
    f.rect(1, 1, 20, 20, "wood"); f.rect(1, 1, 20, 1, "wood_lt"); f.rect(1, 20, 20, 1, "wood_dk")
    f.rect(3, 3, 16, 16, "sand")
    f.dots([(4, 17), (9, 10), (16, 16), (17, 9), (6, 9)], "wood_lt")            # cork grain
    for x, y in SLOTS[:level]:
        f.rect(x, y, 5, 6, "white"); f.rect(x, y + 5, 5, 1, "pale")
        f.rect(x + 1, y + 2, 3, 1, "stone"); f.rect(x + 1, y + 4, 2, 1, "stone")
        f.set(x + 2, y, "red")


def seal(f, _):
    """The wax seal: something on the board changed since it was last read."""
    f.disc(2.5, 2.5, 2.5, "red_dk"); f.disc(2.5, 2.5, 1.6, "red"); f.set(2, 1, "pink")


def almanac(f, _):
    """A wall calendar: a red binding with two rings and a page the engine writes today's date on."""
    f.rect(1, 3, 15, 14, "white"); f.rect(1, 16, 15, 1, "pale"); f.rect(15, 3, 1, 14, "pale")
    f.rect(1, 3, 15, 4, "red"); f.rect(1, 6, 15, 1, "red_dk")
    for x in (4, 11):
        f.rect(x, 1, 2, 4, "stone"); f.set(x, 1, "pale")


def ribbon(f, _):
    """A bookmark ribbon hanging off the page: something is scheduled today."""
    f.rect(0, 0, 3, 5, "yellow"); f.set(1, 4, None); f.rect(0, 0, 3, 1, "sand")


GLYPHS = ("111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
          "111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111")


def digits():
    """0 to 9, 3x5 each, side by side."""
    out = Img(30, 5)
    for n, bits in enumerate(GLYPHS):
        for i, bit in enumerate(bits):
            if bit == "1":
                out.set(n * 3 + i % 3, i // 3, "ink")
    return out


def grid(size, levels, paint):
    w, h = size
    out = Img(w * levels, h * 2)
    for level in range(levels):
        for row in range(2):
            frame = Img(w, h)
            paint(frame, level)
            if row:
                frame.outline("yellow")
            out.blit(frame, level * w, row * h)
    return out


def overlay(size, paint):
    f = Img(*size)
    paint(f, 0)
    return f


# id, tooltip, frame, levels, painter, hit [x, y, w, h] inside the frame from its bottom-left,
# default position, z, news (painter, size, place in the frame), digits place in the frame
HOTSPOTS = [
    ("tasks", "Task board", (22, 22), 6, board, [1, 1, 20, 20], bl(63, 56, 22), 0.6, (seal, (5, 5), [16, 16]), None),
    ("calendar", "Calendar", (17, 18), 1, almanac, [1, 1, 15, 16], bl(118, 57, 18), 0.6, (ribbon, (3, 5), [12, 0]), [5, 3]),
]
