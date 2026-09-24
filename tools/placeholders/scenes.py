"""The chambers of the dwarf mine: eight pockets hewn out of one mountain, each with its own plan.

Every painter follows the same three beats (see mine.py):

    shell     the rock itself - ceiling, hewn wall, ore seams, floor, spoil, timber supports
    fittings  what the dwarves put in this chamber, in flat MATERIAL tones
    light     M.light(...) bakes the chamber's own lamps into all of that, and only THEN the
              flames, glints and glowing things that make the light are painted on top

So no chamber is told apart by the colour of its wall - the rock is the same everywhere. It is told
apart by its FLOOR PLAN (plans.py), by its contents, by the colour and place of its light, and by
what its work leaves on the stone: soot at the forge, flour at the oven, copper stain at the still,
moss in the mushroom farm.

Every painter takes its plan and asks it for everything that moves: where the dwarf stands, how long
and how high his bench is, how low the ceiling hangs, how deep the grit lies, where the lantern is
nailed and whether this chamber's feature is on the right or flipped over to the left. The one thing
no chamber may touch is the 2x speech bubble's box - x 76 rightwards, rows 11..55 - which stays calm
rock, and which is also exactly where an underground ceiling wants to be anyway.
"""
from . import mine as M
from .layout import W, H, BAR, FLOOR, bl
from .pixels import Img, noise, sheet

# Things standing on a bench are authored against a bench top at row BASE and then moved to the
# real one, so a chamber can raise or lower its bench without every jar on it needing new numbers.
BASE = 81


def d(p):
    """How far this chamber's bench top is from the one things on it are authored against."""
    return p.bench[2] - BASE


def fx(p, x, w=1):
    """The x something w wide really lands on, once the chamber's feature has been flipped."""
    return W - x - w if p.mirrored else x


def place(p, target, layer):
    """Drop this chamber's own feature into the rock, on whichever side the plan gives it."""
    target.blit(layer.mirrored() if p.mirrored else layer, 0, 0)


def lamps(p):
    """The two lights every chamber has: the wall lantern, and the daystone's weak cold pool."""
    lx, ly = p.lamp
    wx, wy = p.props["window"]
    return [M.lamp(lx + 4, ly + 9, 40, 0.52), M.lamp(wx + 13, wy + 10, 32, 0.30, warm=False)]


def shell(p, seed, style="hewn", teeth=(), veins=(), cracks=(), heaps=(), rail=True):
    """The rock every chamber is cut out of. The plan sets how the ceiling hangs and how deep the
    grit lies; only the seed and the dressing change the rest."""
    bg = Img(W, H, "ink")
    (M.hewn if style == "hewn" else M.raw)(bg, seed)
    M.ceiling(bg, seed, depth=p.ceil[0], sag=p.ceil[1], teeth=teeth)
    for x, y, length, ore in veins:
        M.vein(bg, x, y, length, ore, seed=seed + x)
    for x, y, length in cracks:
        M.crack(bg, x, y, length, seed=seed + y)
    M.ground(bg, seed, top=p.ground)
    if rail:
        M.rails(bg)
    for x, w, h in heaps:
        M.scree(bg, x, w, h, seed=seed + x)
    bg.rect(0, FLOOR, W, H - FLOOR, "rock_dk")     # under the floor; the frame covers it
    bg.rect(0, 0, W, BAR, "ink")                   # behind the header lintel
    return bg


def finish(p, bg, fg, sources, lamp_glass="yellow"):
    """Bake the chamber's light into the rock and the timber of both layers, then hang the wall
    lantern, which is a source and so must not be dimmed by its own light."""
    M.light(bg, sources, ambient=p.ambient)
    M.light(fg, sources, ambient=p.ambient)
    M.calm(bg)
    M.lantern(bg, p.lamp[0], p.lamp[1], chain=max(p.lamp[1] - BAR - 3, 0), glass=lamp_glass)


def bench(p, fg, kind="wood"):
    """A plank bench on stone trestles: rough, and clearly a thing dwarves built. Its length, its
    height and what it is made of are this chamber's own."""
    top, body, dark = {"wood": ("wood_lt", "wood", "wood_dk"), "stone": ("stone", "rock_lt", "rock_dk")}[kind]
    x, w, y = p.bench
    fg.rect(x - 1, y, w + 2, 2, top)
    fg.rect(x, y + 2, w, FLOOR - y - 2, body)
    fg.rect(x, y + 2, w, 1, dark)
    for i in range(x + 9, x + w - 2, 11):
        fg.rect(i, y + 3, 1, FLOOR - y - 3, dark)
    for i in (x + 3, x + w - 6):                   # trestle legs, planted on the floor
        fg.rect(i, y + 2, 3, FLOOR - y - 2, dark)


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

def workshop(p):
    """The haulage gallery: where the rock leaves the mountain. Bare rock, heavy timbering, a
    shallow ceiling over a long low bench, and a cart running out into the road."""
    bg = shell(p, 11, "raw", teeth=((8, 20, 7, 3), (63, 19, 5, 3), (172, 20, 9, 4)),
               veins=((70, 24, 30, "copper"),), cracks=((110, 22, 26),), heaps=((6, 22, 7), (176, 16, 6)))
    fg, top = Img(W, H), Img(W, H)
    M.beam(bg, 24, 6, 136)
    M.timbers(bg, 126, 27, 4, FLOOR - 4)
    # The road out: a timbered bore, not a dark doorway. The roof and the rail converge on a point
    # off the right-hand edge and the far end is lit, so the chamber reads as having somewhere else.
    feat = Img(W, H)
    x0, x1 = 134, 178

    def roof(x):
        return 56 + (x - x0) // 7

    def road(x):
        return 88 - (x - x0) // 9
    feat.rect(130, 50, 54, 6, "wood"); feat.rect(130, 50, 54, 1, "wood_lt"); feat.rect(130, 55, 54, 1, "wood_dk")
    for x in range(x0, x1):
        feat.rect(x, roof(x), 1, road(x) - roof(x) + 1, "ink")
        feat.set(x, roof(x) - 1, "rock_dk")
    feat.rows(x1 - 6, roof(x1) + 1, [(0, 6)] * (road(x1) - roof(x1) - 1), "warm_dk")   # the next lamp, a long way off
    feat.rows(x1 - 4, roof(x1) + 2, [(0, 4)] * max(road(x1) - roof(x1) - 3, 1), "warm")
    feat.rect(x1 - 3, roof(x1) + 4, 2, 2, "warm_lt")
    for x, tone in ((146, "wood"), (158, "wood_dk"), (168, "rock_dk")):                # the sets, receding
        feat.rect(x, roof(x), 1, road(x) - roof(x) + 1, tone)
        feat.rect(x - 1, roof(x), 3, 1, tone)
    for x in range(x0, x1):                                                           # the rail, converging
        feat.set(x, road(x), "wood_dk")
        feat.set(x, road(x) - 1, "rock_lt" if x % 2 else "stone")
    feat.rect(130, 56, 4, 34, "wood"); feat.rect(130, 56, 1, 34, "wood_lt")            # the near posts
    feat.rect(178, 56, 4, 34, "wood"); feat.rect(181, 56, 1, 34, "wood_dk")
    place(p, bg, feat)
    bg.rect(78, 84, 5, 6, "wood"); bg.rows(76, 78, [(2, 5), (0, 9), (3, 3), (3, 3), (3, 3)], "stone")  # a pick leaning
    bench(p, fg)
    finish(p, bg, fg, lamps(p) + [M.lamp(fx(p, 150), 68, 40, 0.5)])
    M.lantern(bg, fx(p, 142, 9), 56, chain=3)
    top.rect(112, 75, 9, 6, "rock_lt"); top.rect(111, 74, 11, 2, "stone"); top.rect(115, 71, 3, 3, "stone"); top.rect(113, 70, 7, 1, "pale")
    top.rect(88, 79, 6, 2, "sand"); top.rect(94, 80, 5, 1, "sand")
    cart = []
    for k in range(2):
        f = Img(12, 9)
        f.rows(0, 0, [(3, 6), (2, 8)], "copper" if k == 0 else "sand")
        f.rect(0, 2, 12, 4, "wood"); f.rect(0, 2, 12, 1, "wood_lt"); f.rect(1, 6, 10, 1, "wood_dk")
        f.rect(3, 2, 1, 4, "rock_lt"); f.rect(8, 2, 1, 4, "rock_lt")
        for wx in (1, 8):
            f.rect(wx, 6, 3, 3, "rock_lt"); f.set(wx + 1, 7, "ink" if k == 0 else "stone")
        cart.append(f)
    path = {"to": bl(fx(p, 164, 12), 80, 9), "seconds": 6, "every": 18}
    fg.blit(top, 0, d(p))
    return bg, fg, [anim("cart", cart, 4, fx(p, 130, 12), 80, z=0.4, path=path)], {}


def forge(p):
    """The hottest room in the mountain, and the only one whose feature is on the LEFT: the smith
    stands between his fire and his anvil, so the fire mouth is cut into the left-hand rock and he
    works to the right of it. A century of smoke has blacked the lowest ceiling of the eight."""
    bg = shell(p, 21, "hewn", teeth=((100, 19, 5, 2), (150, 21, 8, 4)),
               veins=((78, 30, 20, "copper"),), heaps=((176, 18, 6),))
    fg, top = Img(W, H), Img(W, H)
    M.beam(bg, 25, 60, 186)
    # The fire is a low open HEARTH under a hooded chimney breast, never an arched mouth: the
    # bakery already owns the arch, and a smith works over his fire rather than into it.
    feat = Img(W, H)
    fitted(feat, 132, 62, 52, FLOOR - 62, 6)                                     # the hearth is BUILT
    feat.rect(136, 74, 44, 16, "ink")                                            # the fire bed
    feat.rect(134, 72, 48, 2, "rock_dk"); feat.rect(134, 72, 48, 1, "stone")
    feat.rows(130, 30, [(0, 56), (1, 54), (2, 52)], "rock_lt")                   # the hood over it
    feat.rows(132, 33, [(3, 50), (6, 44), (9, 38), (12, 32), (15, 26)], "rock_dk")
    feat.rect(146, 38, 22, 24, "rock_dk"); feat.rect(146, 38, 1, 24, "rock_lt")  # the chimney breast
    feat.rect(184, 62, 2, FLOOR - 62, "rock_dk")
    M.soot(feat, 128, 46, 58, 30, 43, chance=0.26)
    place(p, bg, feat)
    M.soot(bg, 0, BAR, W, 24, 41, chance=0.32)                                   # smoke across the whole roof
    bg.rect(150, 78, 10, 12, "rock_dk"); bg.rows(148, 74, [(2, 10), (0, 14), (1, 12), (1, 12)], "rock_lt")  # slack tub
    bench(p, fg, "stone")
    finish(p, bg, fg, lamps(p) + [M.lamp(fx(p, 158), 80, 90, 1.0)], lamp_glass="orange")
    M.glow(bg, fx(p, 158), 80, 16, "sand", "wood_lt")
    bg.rows(fx(p, 140, 40), 86, [(0, 40), (0, 40)], "red")
    top.rows(108, 74, [(0, 18), (2, 14), (4, 10)], "stone")                                        # anvil
    top.rect(108, 74, 18, 1, "pale"); top.set(125, 74, "white")
    top.rect(112, 77, 6, 2, "rock_lt"); top.rect(110, 79, 12, 2, "rock_lt"); top.rect(110, 80, 12, 1, "rock_dk")
    top.rect(112, 73, 8, 1, "orange"); top.rect(115, 73, 3, 1, "yellow")                           # hot iron on it
    fire = anim("fire", flames(40, 14, seed=2), 5, fx(p, 138, 40), 74)
    fg.blit(top, 0, d(p))
    return bg, fg, [fire], {"animations": {"type": "hammer"}}


def bakery(p):
    """A stone oven built into a pocket of the rock, with the proving rack beside it so the baker
    can reach it with the peel - which puts him far left at the longest, lowest bench in the mine.
    Flour has settled on everything near the oven; the rock underneath is the same as everywhere."""
    bg = shell(p, 31, "hewn", teeth=((36, 19, 5, 3), (118, 20, 6, 3), (168, 19, 5, 2)),
               veins=((22, 34, 22, "sand"),), heaps=((178, 14, 5),))
    fg, top = Img(W, H), Img(W, H)
    M.beam(bg, 26, 60, 186)
    M.timbers(bg, 110, 29, 4, FLOOR - 4)
    feat = Img(W, H)
    fitted(feat, 130, 56, 52, FLOOR - 60, 5)
    feat.rows(132, 60, [(9, 30), (6, 36), (4, 40), (2, 44), (1, 46)] + [(0, 48)] * 27, "rock_lt")  # the oven dome
    feat.rows(132, 60, [(9, 30), (6, 36), (4, 3), (2, 3), (1, 3)], "stone")
    for y in range(66, 88, 5):
        feat.rect(132, y, 48, 1, "rock_dk")
    feat.rows(146, 70, [(4, 16), (2, 20), (1, 22)] + [(0, 24)] * 14, "ink")                       # oven mouth
    feat.rect(144, 86, 30, 3, "rock_dk"); feat.rect(144, 86, 30, 1, "stone")
    feat.rect(134, 50, 48, 2, "wood_lt"); feat.rect(134, 52, 48, 1, "wood_dk")                    # bread shelf
    for x in (138, 150, 162, 174):
        feat.rows(x, 45, [(1, 6), (0, 8), (0, 8), (0, 8), (0, 8)], "sand")
        feat.dots([(x + 2, 46), (x + 4, 46), (x + 6, 47)], "wood_lt")
    M.soot(feat, 126, 44, 56, 24, 51, tone="cream", chance=0.18)
    place(p, bg, feat)
    bg.rect(114, 76, 14, 14, "wood"); bg.rect(114, 76, 14, 1, "wood_lt"); bg.rect(114, 80, 14, 1, "wood_dk")  # flour barrel
    bench(p, fg)
    finish(p, bg, fg, lamps(p) + [M.lamp(fx(p, 156), 80, 76, 0.95)])
    M.glow(bg, fx(p, 156), 79, 13, "sand", "wood_lt")
    M.soot(bg, 120, 78, 62, 12, 53, tone="cream", chance=0.22)
    top.rect(44, 80, 12, 1, "white"); top.rect(60, 80, 8, 1, "white")                             # flour on the bench
    for x in (88, 97):
        top.rows(x, 76, [(1, 6), (0, 8), (0, 8), (0, 8), (0, 8)], "sand")
        top.dots([(x + 2, 77), (x + 4, 77), (x + 6, 78)], "wood_lt")
    glow = anim("oven", flames(22, 10, seed=6), 4, fx(p, 148, 22), 80)
    steam = anim("steam", rising(8, 12, "white", seed=3), 3, 92, 63 + d(p), z=2.6)
    fg.blit(top, 0, d(p))
    return bg, fg, [glow, steam], {"animations": {"type": "knead"}}


def distillery(p):
    """Copper, condensation and a firebox. The still needs the middle of the floor and all the
    headroom in the mountain, so it stands DEAD CENTRE under the highest ceiling of the eight and
    the distiller works to the left of it. The rock behind it is stained where the vapour runs."""
    bg = shell(p, 41, "hewn", teeth=((40, 15, 8, 3), (90, 14, 6, 2), (110, 16, 7, 3)),
               veins=((152, 56, 26, "copper"), (30, 24, 20, "copper")), cracks=((74, 26, 28),), heaps=((6, 18, 6),))
    fg, top = Img(W, H), Img(W, H)
    M.beam(bg, 21, 6, 146)
    M.timbers(bg, 140, 44, 4, FLOOR - 4)
    feat = Img(W, H)
    pot = [(9, 8), (6, 14), (4, 18), (2, 22), (1, 24)] + [(0, 26)] * 16 + [(1, 24), (2, 22)]
    feat.rows(92, 58, pot, "copper")
    feat.rows(92, 58, [(9, 3), (6, 4), (4, 4), (2, 4), (1, 4)] + [(0, 4)] * 16, "orange")
    feat.rows(110, 64, [(0, 7)] + [(1, 7)] * 14, "red_dk")
    feat.rect(92, 70, 26, 1, "red_dk")
    feat.rect(102, 40, 6, 18, "copper"); feat.rect(102, 40, 2, 18, "orange")                      # neck
    feat.rect(102, 38, 30, 3, "copper"); feat.rect(102, 38, 30, 1, "orange"); feat.rect(129, 41, 3, 28, "copper")
    feat.rect(94, 83, 22, 7, "ink"); feat.rect(97, 86, 16, 3, "orange"); feat.rect(100, 87, 10, 2, "yellow")
    feat.disc(102.5, 68.5, 4.5, "ink"); feat.disc(102.5, 68.5, 3.5, "teal")
    feat.rows(122, 72, [(1, 10)] + [(0, 12)] * 16 + [(1, 10)], "wood")
    feat.rect(122, 76, 12, 1, "rock_lt"); feat.rect(122, 85, 12, 1, "rock_lt"); feat.rect(124, 72, 8, 1, "wood_lt")
    place(p, bg, feat)
    bench(p, fg)
    finish(p, bg, fg, lamps(p) + [M.lamp(fx(p, 104), 84, 60, 0.9), M.lamp(fx(p, 102), 60, 32, 0.4)])
    M.soot(bg, fx(p, 120, 20), 42, 20, 42, 61, tone="teal", chance=0.22)                          # verdigris run
    M.soot(bg, fx(p, 88, 12), 44, 12, 34, 63, tone="teal", chance=0.14)
    M.glow(bg, fx(p, 104), 86, 10, "sand", "wood_lt")
    bottle(top, 40, BASE, "green", 8); bottle(top, 45, BASE, "sky", 6); bottle(top, 84, BASE, "green", 7)
    bubbles = anim("bubbles", rising(5, 6, "white", seed=5, count=2), 4, fx(p, 100, 5), 66)
    drip_frames = []
    for k in range(4):
        f = Img(2, 4)
        f.rect(0, k, 2, 1 if k < 3 else 0, "sky")
        drip_frames.append(f)
    drip = anim("drip", drip_frames, 4, fx(p, 130, 2), 66)
    fg.blit(top, 0, d(p))
    return bg, fg, [bubbles, drip], {"animations": {"type": "stir"}}


def lab(p):
    """The one chamber lit COLD: a cluster of crystals left growing in the seam, shelves of bottles
    at the far right and the alchemist's flask on a high, short, swept bench. Same rock, entirely
    different mood - and the only chamber with almost no grit on its floor."""
    bg = shell(p, 51, "hewn", teeth=((22, 16, 6, 3), (76, 15, 5, 2), (140, 16, 6, 3)),
               veins=((104, 20, 34, "purple"),), cracks=((66, 22, 26),), heaps=((176, 12, 4),), rail=False)
    fg, top = Img(W, H), Img(W, H)
    M.beam(bg, 20, 6, 152)
    M.timbers(bg, 136, 23, 4, FLOOR - 4)
    feat = Img(W, H)
    feat.rect(144, 50, 40, 40, "wood_dk")                                                         # bottle shelves
    colours = ("purple", "green_lt", "red", "sky", "yellow", "pink", "teal")
    for s, y in enumerate((62, 75, 88)):
        feat.rect(144, y, 40, 2, "wood"); feat.rect(144, y, 40, 1, "wood_lt")
        for n, x in enumerate(range(147, 182, 6)):
            bottle(feat, x, y, colours[(n + s * 3) % 7], 5 + (n + s) % 4)
    place(p, bg, feat)
    bench(p, fg, "stone")
    finish(p, bg, fg, lamps(p) + [M.lamp(66, 66, 42, 0.6, warm=False), M.lamp(fx(p, 162), 70, 46, 0.5, warm=False)],
           lamp_glass="sky")
    for x, y, h in ((62, 60, 7), (68, 62, 5), (65, 65, 9), (72, 66, 4)):                          # crystals in the seam
        bg.rows(x, y, [(1, 1), (0, 3), (0, 3)] + [(1, 1)] * (h - 3), "teal")
        bg.rect(x + 1, y, 1, h - 2, "sky"); bg.set(x + 1, y + 1, "white")
    M.glow(bg, 67, 66, 10, "teal", "green_dk")
    top.rows(80, 68, [(4, 3), (4, 3), (4, 3), (3, 5), (2, 7), (1, 9), (0, 11), (0, 11), (0, 11), (0, 11), (0, 11), (1, 9), (2, 7)], "sky")
    top.rows(80, 74, [(2, 7), (1, 9), (1, 9), (1, 9), (2, 7), (3, 5)], "green_lt"); top.rect(82, 74, 7, 1, "white")
    top.rect(118, 78, 9, 3, "red_dk"); top.rect(119, 79, 7, 1, "cream")
    fizz = anim("fizz", rising(7, 10, "green_lt", seed=8), 4, 82, 57 + d(p), z=2.6)
    fg.blit(top, 0, d(p))
    return bg, fg, [fizz], {"animations": {"type": "stir"}}


def treasury(p):
    """A sealed vault: fitted stone where the dwarves squared the rock off, a swept flagstone floor
    and a heap of gold that is itself the only lamp in the room. The counting bench is the shortest
    and the highest in the mine, and the dial is chiselled as far from the hoard as the rock allows."""
    bg = shell(p, 61, "hewn", teeth=((14, 19, 5, 2), (58, 20, 5, 3)),
               veins=((36, 24, 28, "sand"),), heaps=((6, 16, 5),), rail=False)
    fg, top = Img(W, H), Img(W, H)
    M.beam(bg, 24, 6, 126)
    M.timbers(bg, 120, 27, 4, FLOOR - 4)
    feat = Img(W, H)
    fitted(feat, 124, BAR + 8, 62, FLOOR - BAR - 8, 6)
    feat.rect(128, 64, 3, FLOOR - 68, "rock_lt"); feat.rect(128, 60, 3, 4, "stone")                # a lamp bracket
    place(p, bg, feat)
    bench(p, fg)
    finish(p, bg, fg, lamps(p) + [M.lamp(fx(p, 152), 78, 82, 0.9)])
    heap = [(18, 6), (15, 12), (12, 18), (10, 23), (8, 27), (6, 31), (5, 34), (4, 36), (3, 38), (2, 40), (1, 42), (1, 42)] + [(0, 44)] * 14
    gold = Img(W, H)
    gold.rows(131, 64, heap, "yellow")
    for y in range(66, 90, 3):
        for x in range(132, 175, 4):
            if gold.get(x + (y % 2) * 2, y)[3]:
                gold.set(x + (y % 2) * 2, y, "sand"); gold.set(x + 1 + (y % 2) * 2, y, "sand")
    gold.dots([(144, 74), (160, 79), (152, 69)], "red"); gold.dots([(139, 82), (166, 84)], "teal")
    gold.dots([(156, 75), (146, 86)], "pink")
    gold.rect(134, 76, 16, 12, "wood"); gold.rect(134, 76, 16, 4, "wood_lt"); gold.rect(134, 80, 16, 1, "wood_dk")
    gold.rect(141, 79, 2, 3, "yellow"); gold.rect(134, 76, 1, 12, "rock_lt"); gold.rect(149, 76, 1, 12, "rock_lt")
    place(p, bg, gold)
    M.glow(bg, fx(p, 152), 72, 12, "sand", "wood_lt")
    for x, h in ((68, 6), (72, 4), (76, 7), (100, 3)):                                            # coin stacks
        top.rect(x, BASE - h, 3, h, "yellow")
        for y in range(BASE - h + 1, BASE, 2):
            top.rect(x, y, 3, 1, "sand")
    a = anim("glint_a", twinkle(), 3, fx(p, 154, 5), 66)
    b = anim("glint_b", twinkle()[2:] + twinkle()[:2], 2, fx(p, 140, 5), 70)
    fg.blit(top, 0, d(p))
    return bg, fg, [a, b], {}


def mushrooms(p):
    """A wet cavern nobody squared off, and the only chamber with no feature wall: the beds run the
    whole width of the floor and the caps do the lighting from LOW DOWN. Cold, green, and the
    brightest room in the mine - what light there is is everywhere, not in one corner."""
    bg = shell(p, 71, "raw", teeth=((24, 21, 9, 3), (68, 22, 11, 3), (124, 20, 8, 3), (166, 22, 10, 4)),
               cracks=((52, 24, 34), (146, 24, 26)), heaps=((6, 24, 8), (170, 20, 7)), rail=False)
    fg, top = Img(W, H), Img(W, H)
    M.soot(bg, 0, 34, W, 22, 81, tone="green_dk", chance=0.09)
    M.soot(bg, 110, 56, 76, 34, 83, tone="green_dk", chance=0.10)
    M.soot(bg, 28, 70, 64, 20, 85, tone="green_dk", chance=0.08)
    for x, w in ((28, 30), (138, 46)):                                      # the beds, at both ends
        bg.rect(x, 84, w, 6, "wood_dk"); bg.speckle(x, 84, w, 6, "wood", 0.2, 9 + x)
    bench(p, fg)
    finish(p, bg, fg, lamps(p) + [M.lamp(160, 74, 60, 0.8, warm=False), M.lamp(120, 82, 46, 0.6, warm=False),
                                  M.lamp(44, 84, 40, 0.5, warm=False), M.lamp(178, 84, 34, 0.45, warm=False)],
           lamp_glass="green_lt")
    bg.rect(152, 68, 6, 16, "cream"); bg.rect(156, 68, 2, 16, "pale")                              # toadstool
    bg.rows(143, 56, [(7, 10), (4, 16), (2, 20), (1, 22), (0, 24), (0, 24), (0, 24), (1, 22)], "red")
    bg.rect(148, 58, 3, 2, "white"); bg.rect(157, 57, 2, 2, "white"); bg.rect(162, 61, 3, 2, "white"); bg.rect(145, 62, 2, 1, "white")
    bg.rect(172, 76, 3, 8, "pale")                                                                 # glowcaps
    bg.rows(167, 70, [(3, 7), (1, 11), (0, 13), (0, 13)], "teal"); bg.dots([(170, 71), (175, 72), (172, 73)], "green_lt")
    bg.rect(139, 80, 2, 4, "pale"); bg.rows(137, 77, [(1, 4), (0, 6), (0, 6)], "pink")
    bg.rect(180, 81, 1, 3, "pale"); bg.rows(178, 79, [(1, 3), (0, 5)], "purple")
    for x, y in ((34, 82), (42, 80), (50, 83), (114, 80), (122, 78), (130, 82)):
        bg.rect(x + 1, y, 1, FLOOR - y - 1, "pale"); bg.rows(x, y - 2, [(1, 1), (0, 3)], "teal")
    for cx, cy, r in ((170, 74, 7), (44, 83, 5), (122, 81, 6), (179, 85, 4)):
        M.glow(bg, cx, cy, r, "green_dk", "rock_dk")
    top.rect(76, 77, 22, 4, "wood_dk"); top.rect(76, 77, 22, 1, "wood")
    for x, cap in ((78, "pink"), (84, "teal"), (91, "red")):
        top.rect(x + 1, 74, 1, 3, "pale"); top.rect(x, 73, 3, 1, cap); top.set(x + 1, 72, cap)
    spores = anim("spores", rising(14, 12, "green_lt", seed=12), 2, 152, 57)
    drop = Img(2, 3); drop.rect(0, 0, 2, 3, "sky"); drop.set(0, 0, None)
    path = {"to": bl(60, FLOOR - 3, 3), "seconds": 1.2, "every": 5}
    drip = anim("drip", [drop], 1, 60, BAR, path=path)
    fg.blit(top, 0, d(p))
    return bg, fg, [spores, drip], {}


def quarters(p):
    """Bunks cut straight into the rock, a rug over the grit and one candle: the darkest chamber of
    the eight, on purpose, and the one with the rock hanging lowest over your head. The sleeper is
    on the right, so the dwarf who is still up works well left of him, off the rug."""
    bg = shell(p, 81, "hewn", teeth=((48, 20, 5, 2), (110, 19, 5, 3)),
               veins=((92, 25, 24, "copper"),), heaps=((6, 18, 5),), rail=False)
    fg, top = Img(W, H), Img(W, H)
    M.beam(bg, 27, 6, 186)
    M.timbers(bg, 124, 31, 4, FLOOR - 4)
    feat = Img(W, H)
    for y0, blanket in ((54, "red"), (76, "blue")):                                                # bunks cut into the rock
        feat.rect(134, y0 - 3, 50, 12, "ink")
        feat.rect(137, y0, 41, 3, "cream"); feat.rect(137, y0 + 3, 41, 4, blanket)
        feat.rect(134, y0 + 7, 47, 2, "wood_lt")
        feat.rect(138, y0 - 2, 8, 3, "white")
    feat.rows(152, 50, [(3, 14), (1, 18), (0, 20), (0, 20)], "red")
    feat.rect(147, 51, 5, 3, "skin"); feat.rect(146, 50, 3, 2, "stone")
    feat.rect(134, 40, 3, 50, "wood_lt"); feat.rect(181, 40, 3, 50, "wood_lt"); feat.rect(134, 40, 1, 50, "sand")
    place(p, bg, feat)
    bg.rect(40, FLOOR - 3, 96, 3, "red_dk"); bg.rect(42, FLOOR - 3, 92, 1, "sand")                 # rug
    bg.rect(112, 76, 10, 14, "wood"); bg.rect(112, 76, 10, 1, "wood_lt"); bg.rect(112, 80, 10, 1, "wood_dk")  # a chest
    bench(p, fg)
    finish(p, bg, fg, lamps(p) + [M.lamp(84, 80, 36, 0.6), M.lamp(fx(p, 158), 62, 26, 0.3)])
    M.glow(bg, 84, 81, 8, "sand", "wood_lt")
    top.rect(84, 75, 2, 6, "cream"); top.rect(82, 80, 6, 1, "stone")                                # candle
    top.rect(58, 78, 9, 3, "blue_dk"); top.rect(59, 79, 7, 1, "cream")
    flame = []
    for k in range(3):
        f = Img(4, 5)
        f.rows(0, 0, [(1 + (k == 1), 1), (1, 2), (0 if k != 2 else 1, 3), (1, 2)], "orange")
        f.set(1 + (k == 2), 3, "yellow"); f.rect(1, 4, 2, 1, "yellow")
        flame.append(f)
    zs = []
    for k in range(4):
        f = Img(9, 10)
        for i in range(min(k + 1, 3)):
            x, y = i * 3, 7 - i * 3
            f.rect(x, y, 3, 1, "white"); f.set(x + 1, y + 1, "white"); f.rect(x, y + 2, 3, 1, "white")
        zs.append(f if k < 3 else Img(9, 10))
    fg.blit(top, 0, d(p))
    return bg, fg, [anim("candle", flame, 4, 83, 70 + d(p), z=2.6), anim("snore", zs, 1, fx(p, 148, 9), 38)], {}


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
