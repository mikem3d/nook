"""The chambers of the dwarf mine: eight pockets hewn out of one mountain.

Every painter follows the same three beats (see mine.py):

    shell     the rock itself - ceiling, hewn wall, ore seams, floor, spoil, timber supports
    fittings  what the dwarves put in this chamber, in flat MATERIAL tones
    light     M.light(...) bakes the chamber's own lamps into all of that, and only THEN the
              flames, glints and glowing things that make the light are painted on top

So no chamber is told apart by the colour of its wall - the rock is the same everywhere. It is told
apart by its contents, by the colour and place of its light, and by what its work leaves on the
stone: soot at the forge, flour at the oven, copper stain at the still, moss in the mushroom farm.

Zones every scene respects (docs/ART.md): the ladder column x 12..25, the tunnel mouths x < 10 and
x >= 182 on rows 62..91, the vitals wall x 32..62, the dwarf at x 84..115, the scene's own feature at
x 136..180. The hotspots hang either side of the dwarf, rows 54..75; a scene moves one through its
"hotspots" extra. Rows 11..55 stay calm and dark: the speech bubble sits right on them, which is
exactly where an underground ceiling wants to be anyway.
"""
from . import mine as M
from .layout import W, H, BAR, FLOOR, BENCH_TOP, BENCH_X, BENCH_W, bl
from .pixels import Img, noise, sheet

# Things standing on the bench are authored against a bench top at row BASE, then moved to the real one.
BASE = 81
D = BENCH_TOP - BASE

# The wall lantern every chamber hangs in the dead strip between the ladder shaft and the vitals
# wall. It is the one light that is the same everywhere, and it is what keeps the dashboard props
# and the dwarf's left side readable however dark the rest of the chamber goes.
LAMP_X, LAMP_Y = 26, 56
LAMP = M.lamp(LAMP_X + 2, LAMP_Y + 3, 36, 0.48)
# The daystone prop is a living light, so it puts a weak cool pool on the vitals wall.
SHAFT = M.lamp(46, 32, 34, 0.32, warm=False)


def shell(seed, style="hewn", teeth=(), veins=(), cracks=(), heaps=(), rail=True, ground=FLOOR - 7):
    """The rock every chamber is cut out of. Only the seed and the dressing change."""
    bg = Img(W, H, "ink")
    (M.hewn if style == "hewn" else M.raw)(bg, seed)
    M.ceiling(bg, seed, teeth=teeth)
    for x, y, length, ore in veins:
        M.vein(bg, x, y, length, ore, seed=seed + x)
    for x, y, length in cracks:
        M.crack(bg, x, y, length, seed=seed + y)
    M.ground(bg, seed, top=ground)
    if rail:
        M.rails(bg)
    for x, w, h in heaps:
        M.scree(bg, x, w, h, seed=seed + x)
    bg.rect(0, FLOOR, W, H - FLOOR, "rock_dk")     # under the floor; the frame covers it
    bg.rect(0, 0, W, BAR, "ink")                   # behind the header lintel
    return bg


def finish(bg, fg, sources, lamp_glass="yellow"):
    """Bake the chamber's light into the rock and the timber of both layers, then hang the wall
    lantern, which is a source and so must not be dimmed by its own light."""
    M.light(bg, sources)
    M.light(fg, sources)
    M.calm(bg)
    M.lantern(bg, LAMP_X, LAMP_Y, chain=LAMP_Y - BAR - 4, glass=lamp_glass)


def bench(fg, kind="wood", x=BENCH_X, w=BENCH_W):
    """A plank bench on stone trestles: rough, and clearly a thing dwarves built."""
    top, body, dark = {"wood": ("wood_lt", "wood", "wood_dk"), "stone": ("stone", "rock_lt", "rock_dk")}[kind]
    fg.rect(x - 1, BENCH_TOP, w + 2, 2, top)
    fg.rect(x, BENCH_TOP + 2, w, FLOOR - BENCH_TOP - 2, body)
    fg.rect(x, BENCH_TOP + 2, w, 1, dark)
    for i in range(x + 9, x + w - 2, 11):
        fg.rect(i, BENCH_TOP + 3, 1, FLOOR - BENCH_TOP - 3, dark)
    for i in (x + 3, x + w - 6):                   # trestle legs, planted on the floor
        fg.rect(i, BENCH_TOP + 2, 3, FLOOR - BENCH_TOP - 2, dark)


def anim(name, frames, fps, x, y_top, z=0.5, path=None):
    """An ambient entry: frames side by side, placed by its top-left in image coordinates."""
    f = frames[0]
    entry = {"name": name, "frame": [f.w, f.h], "frames": len(frames), "fps": fps, "position": bl(x, y_top, f.h), "z": z}
    if path:
        entry["path"] = path
    return entry, sheet(frames)


def flames(w, h, n=4, seed=0):
    out = []
    for k in range(n):
        f = Img(w, h)
        for x in range(w):
            edge = min(x, w - 1 - x)
            tall = min(h, 2 + edge * 2 + int(noise(x, k, seed) * (h * 0.55)))
            f.rect(x, h - tall, 1, tall, "red")
            f.rect(x, h - max(tall * 2 // 3, 1), 1, max(tall * 2 // 3, 1), "orange")
            if edge > 1:
                f.rect(x, h - max(tall // 3, 1), 1, max(tall // 3, 1), "yellow")
        out.append(f)
    return out


def rising(w, h, colour, n=4, seed=0, count=3):
    """Bubbles, steam or Zs drifting up and looping."""
    out = []
    for k in range(n):
        f = Img(w, h)
        for p in range(count):
            y = (h - 2 - (k * h // n) - p * (h // count)) % h
            x = int(noise(p, 0, seed) * (w - 2)) + (1 if (k + p) % 2 else 0)
            f.rect(x, y, 2 if p % 2 == 0 else 1, 2 if p % 2 == 0 else 1, colour)
        out.append(f)
    return out


def twinkle(n=4, colour="white"):
    out = []
    for k in range(n):
        f = Img(5, 5)
        if k == 1:
            f.set(2, 2, colour)
        elif k == 2:
            f.rect(2, 0, 1, 5, colour); f.rect(0, 2, 5, 1, colour)
        elif k == 3:
            f.rect(2, 1, 1, 3, "yellow"); f.rect(1, 2, 3, 1, "yellow")
        out.append(f)
    return out


def bottle(img, x, base, colour, h=6):
    img.rect(x, base - h + 2, 3, h - 2, colour); img.set(x + 1, base - h, "pale"); img.set(x + 1, base - h + 1, "pale")
    img.set(x, base - h + 2, "white")


def fitted(bg, x, y, w, h, course=5):
    """Squared, fitted stone: where the dwarves have BUILT, as a deliberate contrast to the raw
    rock around it. Used sparingly, it is what makes the rest read as hewn rather than as masonry."""
    bg.rect(x, y, w, h, "rock_lt")
    for j in range(y, y + h, course):
        bg.rect(x, j, w, 1, "rock_dk")
        for i in range(x + (course if (j - y) // course % 2 else 0), x + w, course * 2):
            bg.rect(i, j, 1, course, "rock_dk")
    bg.rect(x, y, w, 1, "stone")
    bg.rect(x, y + h - 1, w, 1, "rock_dk")


# ---------- the chambers ----------

def workshop():
    """The haulage gallery: where the rock leaves the mountain. Bare rock, heavy timbering, a cart."""
    bg = shell(11, "raw", teeth=((8, 20, 7, 3), (63, 19, 5, 3), (172, 20, 9, 4)),
               veins=((70, 24, 30, "copper"),), cracks=((110, 22, 26),), heaps=((6, 22, 7), (176, 16, 6)))
    fg, top = Img(W, H), Img(W, H)
    M.beam(bg, 24, 6, 186)
    M.timbers(bg, 64, 27, 4, FLOOR - 4)
    M.timbers(bg, 130, 27, 4, FLOOR - 4)
    bg.rect(68, 40, 22, 1, "wood_lt")                                                              # tool rail
    bg.rect(71, 41, 1, 9, "wood"); bg.rect(68, 41, 7, 2, "stone"); bg.dots([(68, 43), (74, 43)], "stone")
    bg.rect(79, 41, 1, 8, "wood"); bg.rect(77, 48, 5, 3, "pale")
    bg.rect(86, 41, 1, 4, "wood"); bg.rows(84, 45, [(1, 3), (0, 5), (0, 5), (1, 3)], "stone")
    bg.rect(140, 60, 32, 20, "ink"); bg.rect(140, 72, 32, 8, "rock_dk")                            # the gallery beyond
    bg.rect(140, 79, 32, 1, "wood_dk"); bg.rect(140, 78, 32, 1, "rock_lt")
    bg.rect(136, 57, 40, 3, "wood"); bg.rect(136, 57, 40, 1, "wood_lt")
    bg.rect(138, 60, 2, 20, "wood"); bg.rect(172, 60, 2, 20, "wood")
    bg.rect(148, 82, 12, 8, "wood"); bg.rect(148, 82, 12, 1, "wood_lt"); bg.rect(148, 85, 12, 1, "wood_dk")
    bg.rect(153, 82, 1, 8, "wood_dk")
    bg.rect(36, 82, 5, 8, "wood"); bg.rows(34, 76, [(2, 5), (0, 9), (3, 3), (3, 3), (3, 3), (3, 3)], "stone")  # a pick leaning
    for x in (126, 174):                         # wall in front of the gallery ends: the cart slides out of sight
        fg.blit(bg.crop(x, 62, 12, 18), x, 62)
    bench(fg)
    finish(bg, fg, [LAMP, SHAFT, M.lamp(156, 70, 42, 0.5)])
    M.lantern(bg, 153, 60, chain=4)
    M.glow(bg, 156, 67, 8, "warm_lt", "warm")
    top.rect(112, 75, 9, 6, "rock_lt"); top.rect(111, 74, 11, 2, "stone"); top.rect(115, 71, 3, 3, "stone"); top.rect(113, 70, 7, 1, "pale")
    top.rect(84, 79, 6, 2, "sand"); top.rect(90, 80, 5, 1, "sand")
    cart = []
    for k in range(2):
        f = Img(12, 9)
        f.rows(0, 0, [(3, 6), (2, 8)], "copper" if k == 0 else "sand")
        f.rect(0, 2, 12, 4, "wood"); f.rect(0, 2, 12, 1, "wood_lt"); f.rect(1, 6, 10, 1, "wood_dk")
        f.rect(3, 2, 1, 4, "rock_lt"); f.rect(8, 2, 1, 4, "rock_lt")
        for wx in (1, 8):
            f.rect(wx, 6, 3, 3, "rock_lt"); f.set(wx + 1, 7, "ink" if k == 0 else "stone")
        cart.append(f)
    path = {"to": bl(174, 69, 9), "seconds": 6, "every": 18}
    fg.blit(top, 0, D)
    # The calendar hangs on the wall piece that hides the cart, so it has to be drawn in front of it.
    return bg, fg, [anim("cart", cart, 4, 126, 69, z=0.4, path=path)], {"hotspots": {"calendar": {"z": 2.2}}}


def forge():
    """The hottest room in the mountain: a fire mouth cut into the rock throws everything else into
    silhouette, and a century of smoke has blacked the ceiling."""
    bg = shell(21, "hewn", teeth=((16, 20, 6, 3), (100, 19, 5, 2), (150, 21, 8, 4)),
               veins=((78, 26, 22, "copper"),), heaps=((6, 20, 6),))
    fg, top = Img(W, H), Img(W, H)
    M.beam(bg, 25, 6, 132)
    M.timbers(bg, 128, 28, 4, FLOOR - 4)
    fitted(bg, 138, 40, 44, FLOOR - 44, 6)                                                         # the forge is BUILT
    bg.rect(152, BAR + 8, 16, 32, "rock_lt"); bg.rect(152, BAR + 8, 1, 32, "stone"); bg.rect(167, BAR + 8, 1, 32, "rock_dk")
    bg.rows(146, 62, [(6, 16), (3, 22), (1, 26)] + [(0, 28)] * 22, "ink")                          # fire mouth
    bg.rect(140, 84, 42, 2, "rock_dk")
    bg.rect(60, 78, 10, 12, "rock_dk"); bg.rows(58, 74, [(2, 10), (0, 14), (1, 12), (1, 12)], "rock_lt")  # slack tub
    M.soot(bg, 0, BAR, W, 26, 41, chance=0.30)
    M.soot(bg, 120, 56, 62, 34, 43, chance=0.22)
    bench(fg, "stone")
    finish(bg, fg, [LAMP, SHAFT, M.lamp(160, 76, 96, 1.05)], lamp_glass="orange")
    M.glow(bg, 160, 76, 13, "sand", "wood_lt")
    bg.rows(150, 84, [(0, 20), (0, 20)], "red")
    top.rows(110, 72, [(0, 24), (2, 22), (4, 18)], "pale"); top.rect(110, 72, 24, 1, "white")       # anvil
    top.rect(118, 75, 10, 3, "stone"); top.rect(115, 78, 16, 3, "stone"); top.rect(115, 80, 16, 1, "rock_lt")
    top.rect(116, 71, 10, 1, "orange"); top.rect(122, 71, 4, 1, "yellow")
    fire = anim("fire", flames(24, 18, seed=2), 5, 148, 66)
    props = {"hourglass": {"position": bl(86, BENCH_TOP - 10, 10)}}
    fg.blit(top, 0, D)
    return bg, fg, [fire], {"animations": {"type": "hammer"}, "props": props}


def bakery():
    """A stone oven built into a pocket of the rock. Flour has settled on everything near it, which
    is the only thing that makes this chamber pale - the rock underneath is the same as everywhere."""
    bg = shell(31, "hewn", teeth=((30, 19, 5, 3), (118, 20, 6, 3), (168, 19, 5, 2)),
               veins=((22, 30, 26, "sand"),), heaps=((178, 14, 5),))
    fg, top = Img(W, H), Img(W, H)
    M.beam(bg, 26, 60, 186)
    M.timbers(bg, 62, 29, 4, FLOOR - 4)
    fitted(bg, 134, 50, 48, FLOOR - 54, 5)
    bg.rows(136, 54, [(9, 26), (6, 32), (4, 36), (2, 40), (1, 42)] + [(0, 44)] * 31, "rock_lt")     # the oven dome
    bg.rows(136, 54, [(9, 26), (6, 32), (4, 3), (2, 3), (1, 3)], "stone")
    for y in range(62, 88, 5):
        bg.rect(136, y, 44, 1, "rock_dk")
    bg.rows(148, 66, [(4, 16), (2, 20), (1, 22)] + [(0, 24)] * 18, "ink")                           # oven mouth
    bg.rect(146, 86, 28, 3, "rock_dk"); bg.rect(146, 86, 28, 1, "stone")
    bg.rect(138, 44, 44, 2, "wood_lt"); bg.rect(138, 46, 44, 1, "wood_dk")                          # bread shelf
    for x in (142, 154, 166):
        bg.rows(x, 39, [(1, 8), (0, 10), (0, 10), (0, 10), (0, 10)], "sand"); bg.dots([(x + 2, 40), (x + 5, 40), (x + 8, 41)], "wood_lt")
    bg.rect(64, 74, 14, 16, "wood"); bg.rect(64, 74, 14, 1, "wood_lt"); bg.rect(64, 78, 14, 1, "wood_dk")  # flour sack barrel
    M.soot(bg, 120, 40, 62, 22, 51, tone="cream", chance=0.18)
    bench(fg)
    finish(bg, fg, [LAMP, SHAFT, M.lamp(158, 80, 72, 0.9)])
    M.glow(bg, 158, 79, 11, "sand", "wood_lt")
    M.soot(bg, 130, 78, 56, 12, 53, tone="cream", chance=0.22)
    top.rect(82, 80, 12, 1, "white"); top.rect(98, 80, 8, 1, "white")                                # flour on the bench
    for x in (110, 119):
        top.rows(x, 76, [(1, 6), (0, 8), (0, 8), (0, 8), (0, 8)], "sand"); top.dots([(x + 2, 77), (x + 4, 77), (x + 6, 78)], "wood_lt")
    glow = anim("oven", flames(20, 9, seed=6), 4, 150, 77)
    steam = anim("steam", rising(8, 12, "white", seed=3), 3, 114, 63 + D, z=2.6)
    fg.blit(top, 0, D)
    return bg, fg, [glow, steam], {"animations": {"type": "knead"}}


def distillery():
    """Copper, condensation and a firebox. The rock behind the still is stained green-blue where the
    vapour runs down it."""
    bg = shell(41, "hewn", teeth=((40, 20, 6, 3), (90, 19, 4, 2), (160, 21, 7, 3)),
               veins=((126, 36, 30, "copper"), (30, 28, 20, "copper")), cracks=((74, 30, 24),), heaps=((6, 18, 6),))
    fg, top = Img(W, H), Img(W, H)
    M.beam(bg, 25, 6, 138)
    M.timbers(bg, 60, 28, 4, FLOOR - 4)
    M.timbers(bg, 132, 28, 4, FLOOR - 4)
    pot = [(9, 8), (6, 14), (4, 18), (2, 22), (1, 24)] + [(0, 26)] * 16 + [(1, 24), (2, 22)]
    bg.rows(140, 60, pot, "copper")
    bg.rows(140, 60, [(9, 3), (6, 4), (4, 4), (2, 4), (1, 4)] + [(0, 4)] * 16, "orange")
    bg.rows(158, 66, [(0, 7)] + [(1, 7)] * 14, "red_dk")
    bg.rect(140, 72, 26, 1, "red_dk")
    bg.rect(150, 46, 6, 14, "copper"); bg.rect(150, 46, 2, 14, "orange")                            # neck
    bg.rect(150, 44, 28, 3, "copper"); bg.rect(150, 44, 28, 1, "orange"); bg.rect(175, 47, 3, 22, "copper")
    bg.rect(142, 83, 22, 7, "ink"); bg.rect(145, 86, 16, 3, "orange"); bg.rect(148, 87, 10, 2, "yellow")
    bg.disc(150.5, 70.5, 4.5, "ink"); bg.disc(150.5, 70.5, 3.5, "teal")
    bg.rows(169, 72, [(1, 10)] + [(0, 12)] * 16 + [(1, 10)], "wood"); bg.rect(169, 76, 12, 1, "rock_lt"); bg.rect(169, 85, 12, 1, "rock_lt")
    bg.rect(171, 72, 8, 1, "wood_lt")
    bench(fg)
    finish(bg, fg, [LAMP, SHAFT, M.lamp(152, 84, 58, 0.85), M.lamp(150, 62, 30, 0.35)])
    M.soot(bg, 168, 48, 18, 40, 61, tone="teal", chance=0.22)                                       # verdigris run
    M.soot(bg, 136, 48, 10, 34, 63, tone="teal", chance=0.14)
    M.glow(bg, 152, 86, 9, "sand", "wood_lt")
    bottle(top, 112, BASE, "green", 8); bottle(top, 117, BASE, "sky", 6); bottle(top, 84, BASE, "green", 7)
    bubbles = anim("bubbles", rising(5, 6, "white", seed=5, count=2), 4, 148, 68)
    drip_frames = []
    for k in range(4):
        f = Img(2, 4)
        f.rect(0, k, 2, 1 if k < 3 else 0, "sky")
        drip_frames.append(f)
    drip = anim("drip", drip_frames, 4, 176, 68)
    fg.blit(top, 0, D)
    return bg, fg, [bubbles, drip], {"animations": {"type": "stir"}}


def lab():
    """The one chamber lit COLD: a cluster of glowing crystals left growing in the seam, and the
    alchemist's flask. Same rock, entirely different mood."""
    bg = shell(51, "hewn", teeth=((22, 20, 6, 3), (76, 19, 5, 2), (140, 20, 6, 3)),
               veins=((104, 23, 30, "purple"),), cracks=((44, 26, 22),), heaps=((6, 20, 7), (176, 14, 5)))
    fg, top = Img(W, H), Img(W, H)
    M.beam(bg, 24, 6, 134)
    M.timbers(bg, 130, 27, 4, FLOOR - 4)
    bg.rect(138, 50, 44, 40, "wood_dk")                                                             # bottle shelves
    colours = ("purple", "green_lt", "red", "sky", "yellow", "pink", "teal")
    for s, y in enumerate((62, 75, 88)):
        bg.rect(138, y, 44, 2, "wood"); bg.rect(138, y, 44, 1, "wood_lt")
        for n, x in enumerate(range(141, 178, 6)):
            bottle(bg, x, y, colours[(n + s * 3) % 7], 5 + (n + s) % 4)
    bench(fg, "stone")
    finish(bg, fg, [LAMP, SHAFT, M.lamp(70, 62, 40, 0.55, warm=False), M.lamp(160, 70, 46, 0.45, warm=False)],
           lamp_glass="sky")
    for x, y, h in ((66, 56, 7), (72, 58, 5), (69, 61, 9), (76, 62, 4)):                            # crystals in the seam
        bg.rows(x, y, [(1, 1), (0, 3), (0, 3)] + [(1, 1)] * (h - 3), "teal")
        bg.rect(x + 1, y, 1, h - 2, "sky"); bg.set(x + 1, y + 1, "white")
    M.glow(bg, 71, 62, 9, "teal", "green_dk")
    top.rows(112, 68, [(4, 3), (4, 3), (4, 3), (3, 5), (2, 7), (1, 9), (0, 11), (0, 11), (0, 11), (0, 11), (0, 11), (1, 9), (2, 7)], "sky")
    top.rows(112, 74, [(2, 7), (1, 9), (1, 9), (1, 9), (2, 7), (3, 5)], "green_lt"); top.rect(114, 74, 7, 1, "white")
    top.rect(82, 78, 9, 3, "red_dk"); top.rect(83, 79, 7, 1, "cream")
    fizz = anim("fizz", rising(7, 10, "green_lt", seed=8), 4, 114, 57 + D, z=2.6)
    fg.blit(top, 0, D)
    return bg, fg, [fizz], {"animations": {"type": "stir"}}


def treasury():
    """A sealed vault chamber: fitted stone walls where the dwarves squared the rock off, and a heap
    of gold that is itself the only lamp in the room."""
    bg = shell(61, "hewn", teeth=((14, 19, 5, 2), (58, 20, 5, 3)),
               veins=((36, 24, 28, "sand"),), heaps=((6, 16, 5),), rail=False)
    fg, top = Img(W, H), Img(W, H)
    fitted(bg, 130, BAR + 8, 56, FLOOR - BAR - 8, 6)
    M.beam(bg, 24, 6, 132)
    M.timbers(bg, 126, 27, 4, FLOOR - 4)
    bg.rect(60, 70, 3, FLOOR - 74, "rock_lt"); bg.rect(60, 66, 3, 4, "stone")                       # a lamp bracket
    heap = [(18, 6), (15, 12), (12, 18), (10, 23), (8, 27), (6, 31), (5, 34), (4, 36), (3, 38), (2, 40), (1, 42), (1, 42)] + [(0, 44)] * 14
    bench(fg)
    finish(bg, fg, [LAMP, SHAFT, M.lamp(158, 78, 78, 0.85)])
    bg.rows(137, 64, heap, "yellow")
    for y in range(66, 90, 3):
        for x in range(138, 181, 4):
            if bg.get(x + (y % 2) * 2, y) == bg.get(155, 80):
                bg.set(x + (y % 2) * 2, y, "sand"); bg.set(x + 1 + (y % 2) * 2, y, "sand")
    bg.dots([(150, 74), (166, 79), (158, 69)], "red"); bg.dots([(145, 82), (172, 84)], "teal"); bg.dots([(162, 75), (152, 86)], "pink")
    bg.rect(140, 76, 16, 12, "wood"); bg.rect(140, 76, 16, 4, "wood_lt"); bg.rect(140, 80, 16, 1, "wood_dk")
    bg.rect(147, 79, 2, 3, "yellow"); bg.rect(140, 76, 1, 12, "rock_lt"); bg.rect(155, 76, 1, 12, "rock_lt")
    M.glow(bg, 158, 72, 11, "sand", "wood_lt")
    for x, h in ((110, 6), (114, 4), (118, 7), (84, 3)):                                            # coin stacks
        top.rect(x, BASE - h, 3, h, "yellow")
        for y in range(BASE - h + 1, BASE, 2):
            top.rect(x, y, 3, 1, "sand")
    a = anim("glint_a", twinkle(), 3, 160, 66)
    b = anim("glint_b", twinkle()[2:] + twinkle()[:2], 2, 146, 70)
    fg.blit(top, 0, D)
    return bg, fg, [a, b], {}


def mushrooms():
    """A wet cavern nobody squared off. Water runs down the rock, moss follows it, and the caps do
    the lighting - cold, green, and coming from low down."""
    bg = shell(71, "raw", teeth=((24, 21, 9, 3), (68, 22, 11, 3), (124, 20, 8, 3), (166, 22, 10, 4)),
               cracks=((52, 24, 34), (146, 24, 26)), heaps=((6, 24, 8), (170, 20, 7)), rail=False)
    fg, top = Img(W, H), Img(W, H)
    M.soot(bg, 0, 34, W, 22, 81, tone="green_dk", chance=0.09)
    M.soot(bg, 120, 58, 66, 32, 83, tone="green_dk", chance=0.10)
    M.soot(bg, 40, 74, 50, 16, 85, tone="green_dk", chance=0.08)
    bg.rect(134, 84, 50, 6, "wood_dk"); bg.speckle(134, 84, 50, 6, "wood", 0.2, 9)                  # the bed
    bg.rect(58, 84, 26, 6, "wood_dk"); bg.speckle(58, 84, 26, 6, "wood", 0.2, 19)
    bench(fg)
    finish(bg, fg, [LAMP, SHAFT, M.lamp(166, 74, 52, 0.6, warm=False), M.lamp(70, 82, 30, 0.35, warm=False)],
           lamp_glass="green_lt")
    bg.rect(152, 68, 6, 16, "cream"); bg.rect(156, 68, 2, 16, "pale")                                # toadstool
    bg.rows(143, 56, [(7, 10), (4, 16), (2, 20), (1, 22), (0, 24), (0, 24), (0, 24), (1, 22)], "red")
    bg.rect(148, 58, 3, 2, "white"); bg.rect(157, 57, 2, 2, "white"); bg.rect(162, 61, 3, 2, "white"); bg.rect(145, 62, 2, 1, "white")
    bg.rect(170, 76, 3, 8, "pale")                                                                  # glowcaps
    bg.rows(165, 70, [(3, 7), (1, 11), (0, 13), (0, 13)], "teal"); bg.dots([(168, 71), (173, 72), (170, 73)], "green_lt")
    bg.rect(139, 80, 2, 4, "pale"); bg.rows(137, 77, [(1, 4), (0, 6), (0, 6)], "pink")
    bg.rect(180, 81, 1, 3, "pale"); bg.rows(178, 79, [(1, 3), (0, 5)], "purple")
    for x, y in ((64, 80), (70, 78), (76, 81)):
        bg.rect(x + 1, y, 1, FLOOR - y - 1, "pale"); bg.rows(x, y - 2, [(1, 1), (0, 3)], "teal")
    M.glow(bg, 168, 74, 9, "teal", "green_dk")
    M.glow(bg, 70, 80, 7, "teal", "green_dk")
    top.rect(108, 77, 22, 4, "wood_dk"); top.rect(108, 77, 22, 1, "wood")
    for x, cap in ((110, "pink"), (116, "teal"), (123, "red")):
        top.rect(x + 1, 74, 1, 3, "pale"); top.rect(x, 73, 3, 1, cap); top.set(x + 1, 72, cap)
    spores = anim("spores", rising(14, 12, "green_lt", seed=12), 2, 164, 57)
    drop = Img(2, 3); drop.rect(0, 0, 2, 3, "sky"); drop.set(0, 0, None)
    path = {"to": bl(131, FLOOR - 3, 3), "seconds": 1.2, "every": 5}
    drip = anim("drip", [drop], 1, 131, BAR, path=path)
    fg.blit(top, 0, D)
    # Left of the falling drip, so the drop never passes behind the calendar.
    return bg, fg, [spores, drip], {"hotspots": {"calendar": {"position": bl(114, 57, 18)}}}


def quarters():
    """Bunks cut straight into the rock wall, a rug over the grit, and one candle. The darkest
    chamber of the eight, on purpose."""
    bg = shell(81, "hewn", teeth=((48, 20, 5, 2), (110, 19, 5, 3), (176, 20, 6, 3)),
               veins=((92, 25, 24, "copper"),), heaps=((6, 18, 5),), rail=False)
    fg, top = Img(W, H), Img(W, H)
    M.beam(bg, 25, 6, 186)
    M.timbers(bg, 134, 29, 4, FLOOR - 4)
    for y0, blanket in ((54, "red"), (76, "blue")):                                                  # bunks cut into the rock
        bg.rect(138, y0 - 3, 46, 12, "ink")
        bg.rect(141, y0, 37, 3, "cream"); bg.rect(141, y0 + 3, 37, 4, blanket); bg.rect(138, y0 + 7, 43, 2, "wood_lt")
        bg.rect(142, y0 - 2, 8, 3, "white")
    bg.rows(154, 50, [(3, 14), (1, 18), (0, 20), (0, 20)], "red"); bg.rect(149, 51, 5, 3, "skin"); bg.rect(148, 50, 3, 2, "stone")
    bg.rect(138, 40, 3, 50, "wood_lt"); bg.rect(178, 40, 3, 50, "wood_lt"); bg.rect(138, 40, 1, 50, "sand")
    bg.rect(60, FLOOR - 3, 84, 3, "red_dk"); bg.rect(62, FLOOR - 3, 80, 1, "sand")                   # rug
    bg.rect(66, 76, 10, 14, "wood"); bg.rect(66, 76, 10, 1, "wood_lt"); bg.rect(66, 80, 10, 1, "wood_dk")  # a chest
    bench(fg)
    finish(bg, fg, [LAMP, SHAFT, M.lamp(114, 80, 34, 0.55), M.lamp(160, 62, 26, 0.3)])
    M.glow(bg, 114, 81, 7, "sand", "wood_lt")
    top.rect(114, 75, 2, 6, "cream"); top.rect(112, 80, 6, 1, "stone")                                # candle
    top.rect(84, 78, 9, 3, "blue_dk"); top.rect(85, 79, 7, 1, "cream")
    flame = []
    for k in range(3):
        f = Img(4, 5)
        f.rows(0, 0, [(1 + (k == 1), 1), (1, 2), (0 if k != 2 else 1, 3), (1, 2)], "orange"); f.set(1 + (k == 2), 3, "yellow"); f.rect(1, 4, 2, 1, "yellow")
        flame.append(f)
    zs = []
    for k in range(4):
        f = Img(9, 10)
        for i in range(min(k + 1, 3)):
            x, y = i * 3, 7 - i * 3
            f.rect(x, y, 3, 1, "white"); f.set(x + 1, y + 1, "white"); f.rect(x, y + 2, 3, 1, "white")
        zs.append(f if k < 3 else Img(9, 10))
    fg.blit(top, 0, D)
    return bg, fg, [anim("candle", flame, 4, 113, 70 + D, z=2.6), anim("snore", zs, 1, 150, 38)], {}


# id, display name, painter. Order is the round-robin order for new agents.
SCENES = [
    ("workshop", "Workshop", workshop),
    ("forge", "Forge", forge),
    ("bakery", "Bakery", bakery),
    ("distillery", "Distillery", distillery),
    ("lab", "Alchemy Lab", lab),
    ("treasury", "Treasury", treasury),
    ("mushrooms", "Mushroom Farm", mushrooms),
    ("quarters", "Sleeping Quarters", quarters),
]
