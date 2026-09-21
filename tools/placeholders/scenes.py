"""The chambers of the dwarf mine. Each painter fills an opaque `bg`, a transparent `fg` (what stands
in front of the dwarf) and returns the scene's ambient animations and manifest extras.

Zones every scene respects (docs/ART.md): the ladder column x 12..25, the tunnel mouths x < 10 and
x >= 182 on rows 62..91, the vitals wall x 32..62, the dwarf at x 84..115, the scene's own feature
at x 136..180. The hotspots hang either side of the dwarf, below the bubble: the task board at x 63..84 and
the calendar at x 118..134, rows 56..77; a scene moves one through its "hotspots" extra. The upper right stays calm: the speech bubble covers it.
"""
from .layout import W, H, BAR, FLOOR, BENCH_TOP, BENCH_X, BENCH_W, bl
from .pixels import Img, noise, sheet

# Things standing on the bench are authored against a bench top at row BASE, then moved to the real one.
BASE = 81
D = BENCH_TOP - BASE


def wall(base, line, style="blocks", moss=None):
    bg = Img(W, H, base)
    if style == "blocks":
        for y in range(BAR + 13, FLOOR, 14):
            bg.rect(0, y, W, 1, line)
        for row, y in enumerate(range(BAR, FLOOR, 14)):
            for x in range(12 if row % 2 else 0, W, 24):
                bg.rect(x, y, 1, 13, line)
    else:  # planks
        for x in range(4, W, 10):
            bg.rect(x, BAR, 1, FLOOR - BAR, line)
    if moss:
        bg.speckle(0, BAR, W, FLOOR - BAR, moss, 0.04, 21, only=base)
    bg.rect(0, FLOOR - 2, W, 2, line)       # skirting shadow
    bg.rect(0, FLOOR, W, H - FLOOR, "rock_dk")
    return bg


def bench(fg, kind="wood", x=BENCH_X, w=BENCH_W):
    top, body, dark = {"wood": ("wood_lt", "wood", "wood_dk"), "stone": ("pale", "stone", "rock_lt")}[kind]
    fg.rect(x - 1, BENCH_TOP, w + 2, 2, top)
    fg.rect(x, BENCH_TOP + 2, w, FLOOR - BENCH_TOP - 2, body)
    fg.rect(x, BENCH_TOP + 2, w, 1, dark)
    for i in range(x + 9, x + w - 2, 11):
        fg.rect(i, BENCH_TOP + 3, 1, FLOOR - BENCH_TOP - 3, dark)


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


def twinkle(n=4):
    out = []
    for k in range(n):
        f = Img(5, 5)
        if k == 1:
            f.set(2, 2, "white")
        elif k == 2:
            f.rect(2, 0, 1, 5, "white"); f.rect(0, 2, 5, 1, "white")
        elif k == 3:
            f.rect(2, 1, 1, 3, "yellow"); f.rect(1, 2, 3, 1, "yellow")
        out.append(f)
    return out


def bottle(img, x, base, colour, h=6):
    img.rect(x, base - h + 2, 3, h - 2, colour); img.set(x + 1, base - h, "pale"); img.set(x + 1, base - h + 1, "pale")
    img.set(x, base - h + 2, "white")


# ---------- the scenes ----------

def workshop():
    bg, fg, top = wall("rock", "rock_dk"), Img(W, H), Img(W, H)
    # tools hanging on a rail
    bg.rect(66, 40, 22, 1, "wood_lt")
    bg.rect(69, 41, 1, 9, "wood"); bg.rect(66, 41, 7, 2, "stone"); bg.dots([(66, 43), (72, 43)], "stone")     # pick
    bg.rect(77, 41, 1, 8, "wood"); bg.rect(75, 48, 5, 3, "pale")                                             # mallet
    bg.rect(84, 41, 1, 4, "wood"); bg.rows(82, 45, [(1, 3), (0, 5), (0, 5), (1, 3)], "stone")                # shovel
    # the haulage gallery behind the wall, where the ore cart passes
    bg.rect(140, 60, 32, 20, "ink"); bg.rect(140, 72, 32, 8, "rock_dk")
    bg.rect(140, 79, 32, 1, "wood_dk"); bg.rect(140, 78, 32, 1, "stone")
    bg.rect(136, 57, 40, 3, "wood"); bg.rect(136, 57, 40, 1, "wood_lt")
    bg.rect(138, 60, 2, 20, "wood"); bg.rect(172, 60, 2, 20, "wood")
    bg.rect(148, 82, 12, 8, "wood"); bg.rect(148, 82, 12, 1, "wood_lt"); bg.rect(148, 85, 12, 1, "wood_dk")  # crate
    bg.rect(153, 82, 1, 8, "wood_dk")
    for x in (126, 174):                    # wall in front of the gallery ends, so the cart slides out of sight
        fg.blit(bg.crop(x, 62, 12, 18), x, 62)
    bench(fg)
    top.rect(112, 75, 9, 6, "rock_lt"); top.rect(111, 74, 11, 2, "stone"); top.rect(115, 71, 3, 3, "stone"); top.rect(113, 70, 7, 1, "pale")  # vise
    top.rect(84, 79, 6, 2, "sand"); top.rect(90, 80, 5, 1, "sand")
    cart = []
    for k in range(2):
        f = Img(12, 9)
        f.rows(0, 0, [(3, 6), (2, 8)], "stone" if k == 0 else "pale")           # ore
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
    bg, fg, top = wall("rock_dk", "ink"), Img(W, H), Img(W, H)
    bg.rect(150, BAR, 20, 34, "rock"); bg.rect(150, BAR, 1, 34, "rock_lt"); bg.rect(169, BAR, 1, 34, "ink")   # chimney
    bg.rect(140, 44, 40, 46, "rock_lt"); bg.rect(140, 44, 40, 2, "stone")
    for y in range(52, 90, 8):
        bg.rect(140, y, 40, 1, "rock")
    for row, y in enumerate(range(46, 90, 8)):
        for x in range(146 if row % 2 else 152, 180, 12):
            bg.rect(x, y, 1, 6, "rock")
    bg.rows(148, 64, [(4, 16), (2, 20), (1, 22)] + [(0, 24)] * 19, "ink")                                   # fire mouth
    bg.rows(150, 84, [(0, 20), (0, 20)], "red_dk")
    bg.speckle(128, 60, 12, 28, "red_dk", 0.10, 4, only="rock_dk")                                          # glow on the wall
    bench(fg, "stone")
    top.rows(110, 72, [(0, 24), (2, 22), (4, 18)], "pale"); top.rect(110, 72, 24, 1, "white")                   # anvil
    top.rect(118, 75, 10, 3, "stone"); top.rect(115, 78, 16, 3, "stone"); top.rect(115, 80, 16, 1, "rock_lt")
    top.rect(116, 71, 10, 1, "orange"); top.rect(122, 71, 4, 1, "yellow")
    fire = anim("fire", flames(20, 16, seed=2), 5, 150, 68)
    props = {"hourglass": {"position": bl(86, BENCH_TOP - 10, 10)}}
    fg.blit(top, 0, D)
    return bg, fg, [fire], {"animations": {"type": "hammer"}, "props": props}


def bakery():
    bg, fg, top = wall("wood", "wood_dk"), Img(W, H), Img(W, H)
    bg.rect(140, 47, 40, 2, "wood_lt"); bg.rect(140, 49, 40, 1, "wood_dk")                                   # bread shelf
    for x in (143, 155, 167):
        bg.rows(x, 42, [(1, 8), (0, 10), (0, 10), (0, 10), (0, 10)], "sand"); bg.dots([(x + 2, 43), (x + 5, 43), (x + 8, 44)], "wood_lt")
    bg.rows(138, 56, [(8, 28), (5, 34), (3, 38), (2, 40), (1, 42)] + [(0, 44)] * 29, "red_dk")               # brick oven
    for y in range(62, 90, 5):
        bg.rect(138, y, 44, 1, "wood_dk")
    bg.rows(150, 68, [(3, 14), (1, 18)] + [(0, 20)] * 16, "ink")
    bg.rect(150, 84, 20, 2, "orange"); bg.rect(148, 86, 24, 2, "stone")
    bg.rows(138, 54, [(8, 28), (6, 32)], "stone")
    bench(fg)
    top.rect(82, 80, 12, 1, "white"); top.rect(98, 80, 8, 1, "white")                                         # flour
    for x in (110, 119):
        top.rows(x, 76, [(1, 6), (0, 8), (0, 8), (0, 8), (0, 8)], "sand"); top.dots([(x + 2, 77), (x + 4, 77), (x + 6, 78)], "wood_lt")
    glow = anim("oven", flames(18, 8, seed=6), 4, 151, 77)
    steam = anim("steam", rising(8, 12, "white", seed=3), 3, 114, 63 + D, z=2.6)
    fg.blit(top, 0, D)
    return bg, fg, [glow, steam], {"animations": {"type": "knead"}}


def distillery():
    bg, fg, top = wall("wood_dk", "ink", "planks"), Img(W, H), Img(W, H)
    pot = [(9, 8), (6, 14), (4, 18), (2, 22), (1, 24)] + [(0, 26)] * 16 + [(1, 24), (2, 22)]
    bg.rows(140, 60, pot, "orange")
    bg.rows(140, 60, [(9, 3), (6, 4), (4, 4), (2, 4), (1, 4)] + [(0, 4)] * 16, "yellow")
    bg.rows(158, 66, [(0, 7)] + [(1, 7)] * 14, "red_dk")
    bg.rect(140, 72, 26, 1, "red_dk")
    bg.rect(150, 46, 6, 14, "orange"); bg.rect(150, 46, 2, 14, "yellow")                                     # neck
    bg.rect(150, 44, 28, 3, "orange"); bg.rect(150, 44, 28, 1, "yellow"); bg.rect(175, 47, 3, 22, "orange")   # swan neck
    bg.rect(142, 83, 22, 7, "ink"); bg.rect(145, 86, 16, 3, "orange"); bg.rect(148, 87, 10, 2, "yellow")     # firebox
    bg.disc(150.5, 70.5, 4.5, "ink"); bg.disc(150.5, 70.5, 3.5, "teal")
    bg.rows(169, 72, [(1, 10)] + [(0, 12)] * 16 + [(1, 10)], "wood"); bg.rect(169, 76, 12, 1, "rock_lt"); bg.rect(169, 85, 12, 1, "rock_lt")
    bg.rect(171, 72, 8, 1, "wood_lt")
    bench(fg)
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
    bg, fg, top = wall("purple_dk", "ink"), Img(W, H), Img(W, H)
    bg.rect(138, 50, 44, 40, "wood_dk")
    colours = ("purple", "green_lt", "red", "sky", "yellow", "pink", "teal")
    for s, y in enumerate((62, 75, 88)):
        bg.rect(138, y, 44, 2, "wood"); bg.rect(138, y, 44, 1, "wood_lt")
        for n, x in enumerate(range(141, 178, 6)):
            bottle(bg, x, y, colours[(n + s * 3) % 7], 5 + (n + s) % 4)
    bench(fg, "stone")
    top.rows(112, 68, [(4, 3), (4, 3), (4, 3), (3, 5), (2, 7), (1, 9), (0, 11), (0, 11), (0, 11), (0, 11), (0, 11), (1, 9), (2, 7)], "sky")
    top.rows(112, 74, [(2, 7), (1, 9), (1, 9), (1, 9), (2, 7), (3, 5)], "green_lt"); top.rect(114, 74, 7, 1, "white")
    top.rect(82, 78, 9, 3, "red_dk"); top.rect(83, 79, 7, 1, "cream")
    fizz = anim("fizz", rising(7, 10, "green_lt", seed=8), 4, 114, 57 + D, z=2.6)
    fg.blit(top, 0, D)
    return bg, fg, [fizz], {"animations": {"type": "stir"}}


def treasury():
    bg, fg, top = wall("blue_dk", "ink"), Img(W, H), Img(W, H)
    heap = [(18, 6), (15, 12), (12, 18), (10, 23), (8, 27), (6, 31), (5, 34), (4, 36), (3, 38), (2, 40), (1, 42), (1, 42)] + [(0, 44)] * 14
    bg.rows(137, 64, heap, "yellow")
    for y in range(66, 90, 3):
        for x in range(138, 181, 4):
            if bg.get(x + (y % 2) * 2, y) == bg.get(155, 80):
                bg.set(x + (y % 2) * 2, y, "sand"); bg.set(x + 1 + (y % 2) * 2, y, "sand")
    bg.dots([(150, 74), (166, 79), (158, 69)], "red"); bg.dots([(145, 82), (172, 84)], "teal"); bg.dots([(162, 75), (152, 86)], "pink")
    bg.rect(140, 76, 16, 12, "wood"); bg.rect(140, 76, 16, 4, "wood_lt"); bg.rect(140, 80, 16, 1, "wood_dk")    # chest
    bg.rect(147, 79, 2, 3, "yellow"); bg.rect(140, 76, 1, 12, "rock_lt"); bg.rect(155, 76, 1, 12, "rock_lt")
    bench(fg)
    for x, h in ((110, 6), (114, 4), (118, 7), (84, 3)):                                                      # coin stacks
        top.rect(x, BASE - h, 3, h, "yellow")
        for y in range(BASE - h + 1, BASE, 2):
            top.rect(x, y, 3, 1, "sand")
    a = anim("glint_a", twinkle(), 3, 160, 66)
    b = anim("glint_b", twinkle()[2:] + twinkle()[:2], 2, 146, 70)
    fg.blit(top, 0, D)
    return bg, fg, [a, b], {}


def mushrooms():
    bg, fg, top = wall("rock_dk", "ink", moss="green_dk"), Img(W, H), Img(W, H)
    bg.rect(136, 84, 46, 6, "wood_dk"); bg.speckle(136, 84, 46, 6, "wood", 0.2, 9)
    bg.rect(152, 68, 6, 16, "cream"); bg.rect(156, 68, 2, 16, "pale")                                         # toadstool
    bg.rows(143, 56, [(7, 10), (4, 16), (2, 20), (1, 22), (0, 24), (0, 24), (0, 24), (1, 22)], "red")
    bg.rect(148, 58, 3, 2, "white"); bg.rect(157, 57, 2, 2, "white"); bg.rect(162, 61, 3, 2, "white"); bg.rect(145, 62, 2, 1, "white")
    bg.rect(170, 76, 3, 8, "pale")                                                                            # glowcap
    bg.rows(165, 70, [(3, 7), (1, 11), (0, 13), (0, 13)], "teal"); bg.dots([(168, 71), (173, 72), (170, 73)], "green_lt")
    bg.rect(139, 80, 2, 4, "pale"); bg.rows(137, 77, [(1, 4), (0, 6), (0, 6)], "pink")
    bg.rect(180, 81, 1, 3, "pale"); bg.rows(178, 79, [(1, 3), (0, 5)], "purple")
    bench(fg)
    top.rect(108, 77, 22, 4, "wood_dk"); top.rect(108, 77, 22, 1, "wood")
    for x, cap in ((110, "pink"), (116, "teal"), (123, "red")):
        top.rect(x + 1, 74, 1, 3, "pale"); top.rect(x, 73, 3, 1, cap); top.set(x + 1, 72, cap)
    spores = anim("spores", rising(14, 12, "green_lt", seed=12), 2, 164, 57)
    drop = Img(2, 3); drop.rect(0, 0, 2, 3, "sky"); drop.set(0, 0, None)
    path = {"to": bl(131, FLOOR - 3, 3), "seconds": 1.2, "every": 5}
    drip = anim("drip", [drop], 1, 131, BAR, path=path)
    fg.blit(top, 0, D)
    # Left of the falling drip, so the drop never passes behind the calendar.
    return bg, fg, [spores, drip], {"hotspots": {"calendar": {"position": bl(112, 57, 18)}}}


def quarters():
    bg, fg, top = wall("wood_dk", "wood", "planks"), Img(W, H), Img(W, H)
    for y0, blanket in ((54, "red"), (76, "blue")):                                                           # bunks
        bg.rect(141, y0, 37, 3, "cream"); bg.rect(141, y0 + 3, 37, 4, blanket); bg.rect(138, y0 + 7, 43, 2, "wood_lt")
        bg.rect(142, y0 - 2, 8, 3, "white")
    bg.rows(154, 50, [(3, 14), (1, 18), (0, 20), (0, 20)], "red"); bg.rect(149, 51, 5, 3, "skin"); bg.rect(148, 50, 3, 2, "stone")   # someone asleep
    bg.rect(138, 40, 3, 50, "wood_lt"); bg.rect(178, 40, 3, 50, "wood_lt"); bg.rect(138, 40, 1, 50, "sand")
    bg.rect(60, FLOOR - 2, 84, 2, "red_dk"); bg.rect(62, FLOOR - 2, 80, 1, "sand")                            # rug
    bench(fg)
    top.rect(114, 75, 2, 6, "cream"); top.rect(112, 80, 6, 1, "stone")                                          # candle
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
