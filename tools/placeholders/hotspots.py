"""Hotspots: the props that are buttons (docs/ART.md, "Hotspots"). A sheet has one column per level
and two rows: idle on top, hover below. Every frame keeps a 1 px transparent margin so the hover
outline fits inside it. `news` is a small overlay the engine shows when something changed.
"""
from .layout import bl
from .pixels import Img

# Where each of the five parchments hangs on the cork, inside the 22x22 frame.
SLOTS = ((3, 4), (9, 3), (15, 4), (5, 12), (12, 11))


def board(f, level):
    """Rough planks nailed to the rock, with `level` parchments pinned to them."""
    f.rect(1, 1, 20, 20, "wood_dk")
    for y in range(2, 20, 6):                                                  # boards, with the gap between them
        f.rect(2, y, 18, 5, "wood")
        f.rect(2, y, 18, 1, "wood_lt")
        f.rect(2, y + 4, 18, 1, "wood_dk")
    f.rect(1, 1, 20, 1, "wood_lt"); f.rect(1, 20, 20, 1, "ink")
    f.dots([(3, 3), (18, 3), (3, 15), (18, 15), (3, 9), (18, 9)], "rock_lt")   # iron nails
    for x, y in SLOTS[:level]:
        f.rect(x, y, 5, 6, "cream"); f.rect(x, y + 5, 5, 1, "sand")
        f.rect(x + 1, y + 2, 3, 1, "wood"); f.rect(x + 1, y + 4, 2, 1, "wood")
        f.set(x + 2, y, "red")


def seal(f, _):
    """The wax seal: something on the board changed since it was last read."""
    f.disc(2.5, 2.5, 2.5, "red_dk"); f.disc(2.5, 2.5, 1.6, "red"); f.set(2, 1, "pink")


def almanac(f, _):
    """A stone almanac: a pale limestone tablet hung on two iron pins, its head band carved and
    stained red, and a face the engine chisels today's date into (so the digits stay dark on pale)."""
    f.rect(1, 3, 15, 14, "pale"); f.rect(1, 16, 15, 1, "rock_lt"); f.rect(15, 3, 1, 14, "stone")
    f.rect(1, 3, 15, 1, "white")
    f.rect(1, 3, 15, 4, "red_dk"); f.rect(1, 6, 15, 1, "ink"); f.rect(2, 4, 13, 1, "red")
    f.dots([(3, 14), (12, 9), (6, 11)], "stone")                               # chisel wear
    for x in (4, 11):
        f.rect(x, 1, 2, 4, "rock_lt"); f.set(x, 1, "stone")


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
    ("tasks", "Task board", (22, 22), 6, board, [1, 1, 20, 20], bl(63, 54, 22), 0.6, (seal, (5, 5), [16, 16]), None),
    ("calendar", "Calendar", (17, 18), 1, almanac, [1, 1, 15, 16], bl(118, 57, 18), 0.6, (ribbon, (3, 5), [12, 0]), [5, 3]),
]
