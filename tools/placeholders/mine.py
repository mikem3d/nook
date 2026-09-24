"""The shared look of the mine: living rock, the light that carves it out of the dark, and the
fittings the dwarves bolt into it.

Every chamber is a pocket hewn out of the SAME rock, so the rock tones never change from scene to
scene. A chamber is told apart by what is in it, by the COLOUR of its light, and by a little surface
dressing (soot, flour, moss, copper stain). That is why a painter here works in two passes:

    1. build the wall, the ceiling, the floor and the furniture in flat MATERIAL tones
    2. call `light()` with that chamber's own light sources

`light()` walks every rock and timber pixel, works out how much light reaches it, and slides it up
or down its ramp: bright and warm beside the fire, cool and mid around the working area, ink in the
ceiling and the corners. Only then does the painter draw the sources themselves, so the flame stays
hot while the rock around it falls away into the dark.
"""
from .layout import W, H, BAR, SIDE, FLOOR
from .pixels import PAL, noise

# The ramps light() slides along. Cool rock is the default; rock inside a warm pool of light
# borrows WARM, which shares its two ends with ROCK so the crossover never shows a seam.
ROCK = ("ink", "rock_dk", "rock", "rock_lt", "stone", "pale", "white")
WARM = ("ink", "warm_dk", "warm", "warm_lt", "sand", "cream", "white")
WOOD = ("ink", "wood_dk", "wood", "wood_lt", "sand", "cream", "white")
TOP = len(ROCK) - 1

# Which flat tones light() is allowed to move, and where on their ramp they start. Everything else
# (flame, ore, glass, cloth) is an object colour and is left exactly as painted.
_ROCK_IN = {PAL[n]: i for i, n in enumerate(ROCK[:6])}
_WOOD_IN = {PAL["wood_dk"]: 1, PAL["wood"]: 2, PAL["wood_lt"]: 3}

# A 4x4 ordered dither, so the steps between ramp levels break up into pixels instead of showing
# as contour rings around every lamp.
_BAYER = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))


def lamp(x, y, radius, strength=1.0, warm=True):
    """One light source, placed in image coordinates. `warm` fires push rock onto the WARM ramp."""
    return (x, y, radius, strength, warm)


def _vignette(x, y):
    """Underground, the far corners of a chamber simply never get any light."""
    dx = min(x - SIDE, (W - SIDE - 1) - x)
    dy = min(y - BAR, (FLOOR + 2) - y)
    return 0.26 + 0.74 * min(max(dx, 0) / 30.0, max(dy, 0) / 26.0, 1.0)


def _reach(x, y, sources, ambient):
    """Total light at a pixel, and how much of it is warm. Pools are wider than they are tall,
    which is what light spilling along a wall and a floor actually looks like."""
    total, warm = ambient * _vignette(x, y), 0.0
    for sx, sy, radius, strength, is_warm in sources:
        d = ((x - sx) ** 2 + ((y - sy) * 1.3) ** 2) ** 0.5
        if d < radius:
            v = strength * (1.0 - d / radius) ** 2.0
            total += v
            if is_warm:
                warm += v
    return total, warm


def light(img, sources, ambient=0.42, top=BAR, bottom=H):
    """Bake the chamber's lighting into the flat art. Call it once, after the materials are down
    and before the flames, ore glints and glowing things that MAKE the light are painted."""
    for y in range(top, bottom):
        for x in range(W):
            px = img.px[y][x]
            step, ramp = _ROCK_IN.get(px), ROCK
            if step is None:
                step, ramp = _WOOD_IN.get(px), WOOD
                if step is None:
                    continue
            total, warm = _reach(x, y, sources, ambient)
            total += (_BAYER[y % 4][x % 4] / 16.0 - 0.47) * 0.15
            if ramp is ROCK and warm > 0.30:
                ramp = WARM
            level = step + max(-2, min(2, int(round((total - 0.56) * 3.0))))
            img.px[y][x] = PAL[ramp[min(max(level, 0), TOP)]]


_ANY_ROCK = {}
for _ramp in (ROCK, WARM):
    for _i, _n in enumerate(_ramp):
        _ANY_ROCK[PAL[_n]] = _i


def _quantise(img, y0, y1, tones):
    """Redraw a band of rock in 2x2 blocks of one tone each, chosen from `tones` by how light the
    block already is. Timber is left alone, so a ceiling beam still reads across it."""
    for y in range(y0, y1, 2):
        for x in range(0, W, 2):
            cells = [(i, j) for j in range(y, min(y + 2, y1)) for i in range(x, min(x + 2, W))]
            steps = [_ANY_ROCK.get(img.px[j][i]) for i, j in cells]
            known = [s for s in steps if s is not None]
            if not known:
                continue
            tone = tones[min(int(round(sum(known) / len(known))), len(tones) - 1)]
            for (i, j), step in zip(cells, steps):
                if step is not None:
                    img.px[j][i] = PAL[tone]


def calm(img, y0=BAR, y1=26, soft=36):
    """Quieten the band the speech bubble sits on: two tones of dark right under the lintel, then a
    coarser version of the real rock fading back into the wall.

    This is a constraint (docs/ART.md: nothing may compete with the bubble) that happens to be the
    right art call as well - that band is the ceiling, and a ceiling underground is simply dark.
    """
    _quantise(img, y0, y1, ("ink", "rock_dk"))
    _quantise(img, y1, soft, ("ink", "rock_dk", "rock", "rock_lt", "stone"))


# ---------- living rock ----------

def hewn(bg, seed=1, y0=BAR, y1=FLOOR):
    """A wall dwarves cut with picks: irregular faces of every size, split by wandering chisel
    lines, not a course of identical bricks with mortar between them."""
    bg.rect(0, y0, W, y1 - y0, "rock")
    faces, y, band = [], y0, 0
    while y < y1:
        h = min(9 + int(noise(band, 0, seed) * 8), y1 - y)
        x = -int(noise(band, 1, seed) * 20)
        while x < W:
            w = 11 + int(noise(band, x, seed + 3) * 15)
            n = noise(x, band, seed + 5)
            faces.append((x, y, w, h, "rock_lt" if n > 0.74 else "rock_dk" if n < 0.28 else "rock"))
            x += w
        y += h
        band += 1
    for x, y, w, h, tone in faces:
        bg.rect(x, y, w, h, tone)
    for x, y, w, h, tone in faces:
        if noise(x, y, seed + 7) < 0.18:        # some faces merge into their neighbour
            continue
        split = "ink" if tone == "rock_dk" else "rock_dk"
        for j in range(h):                      # the vertical split wanders by a pixel
            bg.set(x + (1 if noise(x, y + j, seed + 9) < 0.3 else 0), y + j, split)
        for i in range(w):                      # so does the horizontal one, and it catches light
            jy = y + (1 if noise(x + i, y, seed + 11) < 0.28 else 0)
            bg.set(x + i, jy, split)
            if noise(x + i, y, seed + 13) < 0.45:
                bg.set(x + i, jy + 1, "rock_lt" if tone != "rock_lt" else "stone")
    chisel(bg, seed, y0, y1)


def raw(bg, seed=2, y0=BAR, y1=FLOOR):
    """A wall nobody bothered to square off: bare rock face in diagonal strata."""
    bg.rect(0, y0, W, y1 - y0, "rock")
    for y in range(y0, y1):
        for x in range(W):
            n = noise((x + y * 2) // 3, y // 2, seed)
            if n < 0.18:
                bg.set(x, y, "rock_dk")
            elif n > 0.86:
                bg.set(x, y, "rock_lt")
    for k in range(7):                          # strata: long dark bands running down and across
        y = y0 + int(noise(k, 3, seed) * (y1 - y0 - 4))
        for x in range(W):
            bg.set(x, y + (x + k * 5) // 26, "rock_dk")
    chisel(bg, seed + 1, y0, y1)


def chisel(bg, seed, y0=BAR, y1=FLOOR):
    """Pick marks: short horizontal dashes, never single pixels, so it reads as tooling at 2x
    rather than as static."""
    for y in range(y0, y1):
        for x in range(0, W, 2):
            n = noise(x // 2, y, seed + 17)
            if n < 0.035:
                bg.rect(x, y, 2, 1, "rock_dk")
            elif n > 0.978:
                bg.rect(x, y, 2, 1, "rock_lt")


def crack(bg, x, y, length, seed=0, drift=1):
    """A fissure running down the rock, with the lit lip the light catches on one side."""
    for j in range(length):
        x += (1 if noise(x, y + j, seed) > 0.62 else 0) - (1 if noise(x, y + j, seed + 1) < 0.24 else 0)
        x = max(0, min(W - 2, x))
        bg.set(x, y + j, "ink")
        if j % 3 != 2:
            bg.set(x + drift, y + j, "rock_lt")


def vein(bg, x, y, length, ore="copper", seed=0, thick=2):
    """An ore seam threading the wall: the metal, a dark bed under it, a glint on top."""
    for j in range(length):
        x += (1 if noise(x, y + j, seed + 2) > 0.58 else 0) - (1 if noise(x, y + j, seed + 3) < 0.3 else 0)
        x = max(1, min(W - thick - 1, x))
        bg.rect(x, y + j, thick, 1, ore)
        bg.set(x - 1, y + j, "rock_dk")
        if noise(x, y + j, seed + 4) < 0.3:
            bg.set(x + thick - 1, y + j, "yellow" if ore in ("copper", "sand") else "white")


def ceiling(bg, seed=3, depth=7, sag=6, teeth=()):
    """Rock overhead: a dark band hanging under the lintel with a jagged lower edge, and
    stalactites where the painter asks for them. This is what kills the blank top band, and it can
    stay dark and calm because the speech bubble sits right on top of it."""
    for x in range(W):
        h = depth + int(noise(x // 3, 0, seed) * sag)
        bg.rect(x, BAR, 1, h, "rock_dk")
        bg.set(x, BAR + h - 1, "ink")
        if noise(x // 2, 1, seed + 5) < 0.18:
            bg.set(x, BAR + h, "ink")
    for x, y, length, w in teeth:
        for j in range(length):
            t = max(1, w - (j * w) // max(length, 1))
            bg.rect(x + (w - t) // 2, y + j, t, 1, "rock_dk" if j % 4 else "rock")
        bg.set(x + w // 2, y + length, "rock_lt")     # the wet tip catches whatever light there is


def scree(bg, x, w, height, seed=0, tone="rock_dk"):
    """Spoil piled against the foot of a wall: a heap plus the stones that rolled off it."""
    for i in range(w):
        t = i / max(w - 1, 1)
        h = int(height * (1.0 - abs(t * 2 - 1) ** 1.6) * (0.75 + 0.5 * noise(x + i, 0, seed)))
        if h > 0:
            bg.rect(x + i, FLOOR - h, 1, h, tone)
            bg.set(x + i, FLOOR - h, "rock" if noise(x + i, 1, seed) < 0.5 else "rock_lt")
    for k in range(5):
        px = x + int(noise(k, 2, seed) * w)
        bg.rect(px, FLOOR - 2 - int(noise(k, 3, seed) * 2), 2, 2, "rock")


def ground(bg, seed=0, top=FLOOR - 7):
    """The chamber's own floor: trodden grit with loose stones, and the dark line where it meets
    the wall. Without this the only floor in the picture is the frame's two-pixel lip."""
    bg.rect(0, top, W, FLOOR - top, "rock_dk")
    bg.rect(0, top, W, 1, "ink")
    for y in range(top + 1, FLOOR):
        for x in range(W):
            n = noise(x, y, seed + 23)
            if n > 0.88:
                bg.set(x, y, "rock")
            elif n < 0.06:
                bg.set(x, y, "ink")
    for k in range(10):                          # loose stones catching the light
        x = int(noise(k, 7, seed) * (W - 4))
        y = top + 2 + int(noise(k, 8, seed) * (FLOOR - top - 4))
        bg.rect(x, y, 2 + (k % 2), 1, "rock_lt")


def rails(bg, y=None):
    """Cart rails running the width of the chamber, lined up with the rail in the tunnel pieces."""
    y = FLOOR - 3 if y is None else y
    for x in range(0, W, 6):
        bg.rect(x, y + 1, 4, 1, "wood_dk")       # sleepers
    bg.rect(0, y, W, 1, "rock_lt")
    bg.rect(0, y + 2, W, 1, "stone")


def timbers(bg, x, top, w=4, bottom=FLOOR, lintel=0):
    """A support post, and optionally the lintel it carries. Posts and beams are what stop a
    chamber reading as one flat wall with a hole in it."""
    bg.rect(x, top, w, bottom - top, "wood")
    bg.rect(x, top, 1, bottom - top, "wood_lt")
    bg.rect(x + w - 1, top, 1, bottom - top, "wood_dk")
    for y in range(top + 5, bottom - 2, 9):      # iron bands
        bg.rect(x - 1, y, w + 2, 1, "rock_lt")
    if lintel:
        bg.rect(x - 2, top - 4, lintel, 4, "wood")
        bg.rect(x - 2, top - 4, lintel, 1, "wood_lt")
        bg.rect(x - 2, top - 1, lintel, 1, "wood_dk")


def beam(bg, y, x0=0, x1=W, thick=3):
    """A ceiling beam spanning the chamber, with the shadow it throws on the rock behind it."""
    bg.rect(x0, y, x1 - x0, thick, "wood")
    bg.rect(x0, y, x1 - x0, 1, "wood_lt")
    bg.rect(x0, y + thick - 1, x1 - x0, 1, "wood_dk")
    bg.rect(x0, y + thick, x1 - x0, 1, "rock_dk")
    for x in range(x0 + 6, x1 - 4, 21):
        bg.rect(x, y, 2, thick, "wood_dk")       # pegs


def lantern(img, x, y, chain=0, glass="yellow"):
    """A hanging lantern: chain, iron hood, glazed panes. Paint it AFTER light(): it is a source,
    so nothing may dim it."""
    for j in range(chain):
        img.set(x + 3, y - chain + j, "rock_dk" if j % 2 else "rock_lt")
    img.rows(x + 1, y, [(2, 1), (1, 3), (0, 5)], "rock_lt")           # the hood
    img.rect(x, y + 3, 7, 1, "stone")
    img.rect(x, y + 4, 7, 6, "ink")                                   # the cage
    img.rect(x + 1, y + 4, 5, 6, glass)
    img.rect(x + 3, y + 4, 1, 6, "ink"); img.rect(x + 1, y + 6, 5, 1, "ink")
    img.set(x + 2, y + 5, "white"); img.set(x + 5, y + 8, "white")
    img.rect(x, y + 10, 7, 1, "rock_lt"); img.rect(x + 2, y + 11, 3, 1, "rock_dk")


def soot(bg, x, y, w, h, seed, tone="ink", chance=0.16):
    """Surface dressing: what this chamber's work leaves on the rock. Soot, flour, copper stain,
    moss and spores are how the eight chambers tell themselves apart WITHOUT repainting the rock."""
    for j in range(y, y + h):
        for i in range(x, x + w):
            if noise(i, j, seed) < chance * (1.0 - (j - y) / (h * 1.6)):
                bg.set(i, j, tone)


def glow(img, cx, cy, radius, inner="orange", outer="red_dk"):
    """The visible halo around a source, painted on top of the baked light so the source itself
    never gets dimmed by it."""
    for y in range(max(BAR, int(cy - radius)), min(FLOOR, int(cy + radius) + 1)):
        for x in range(max(0, int(cx - radius)), min(W, int(cx + radius) + 1)):
            d = ((x - cx) ** 2 + ((y - cy) * 1.2) ** 2) ** 0.5
            if d > radius or img.px[y][x][3] == 0:
                continue
            t = d / radius + (_BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.34
            if t < 0.5:
                img.set(x, y, inner)
            elif t < 0.95:
                img.set(x, y, outer)
