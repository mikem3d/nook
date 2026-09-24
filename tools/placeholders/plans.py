"""One deliberate floor plan per chamber.

The previous pass gave all eight chambers the same furniture in the same pixels and only changed the
right-hand feature, so the mine read as one template redressed eight times. Everything that CAN move
without a Swift change now moves per scene: where the vitals props hang, where the two hotspots hang,
where the dwarf stands, which side his chamber's feature occupies, how long and how high his bench is,
how low the ceiling hangs and how deep the grit lies.

Nothing here is random. Each plan is a working layout: the bakery's rack stands beside its oven so the
baker can reach it, the treasury's dial is as far from the gold as the chamber allows, the forge's pot
sits on the fire's own stone ledge, the mushroom farmer keeps his baskets by the door.

Coordinates are IMAGE coordinates - x from the left, rows from the TOP of the 192x108 canvas - and a
prop or hotspot is given by its TOP-LEFT corner. `make_placeholders` converts to the manifest's
bottom-left origin. The rules every plan holds to (checked by `tools/art/placement.py`):

  ladder      x 12..25, every row: wall only, the shaft hangs there
  tunnels     x 0..9 and x 182..191, rows 62..91: wall only, the tunnel pieces cover them
  header      rows 0..10: the lintel
  bubble      rows 11..55 from x 76 rightwards: the speech bubble sits there at 2x, so nothing but
              calm rock. Left of x 76 a prop may go high; the 1x bubble can still reach it, which is
              the compromise the vitals wall has always made.
  hotspots    their HIT rectangles must clear the header, the ladder, the tunnels, rows 0..54 from the
              bottom, the dwarf and every prop (Tests/NookTests/HotspotTests)
  overlap     no prop under another prop, and nothing behind the dwarf but the wall
"""
from collections import namedtuple

Plan = namedtuple("Plan", "feet bench ceil ground lamp mirrored ambient props spots kits")
Plan.__doc__ = """
feet      x the dwarf stands on; his feet are always on the floor at row 90
bench     (x, width, top row) of the plank bench he works at
ceil      (depth, sag) of the rock hanging under the lintel
ground    the top row of the trodden grit
lamp      (x, top row) of this chamber's wall lantern
mirrored  True: the chamber's own feature is on the LEFT and the dwarf works right of centre
ambient   how much light this chamber has of its own, before its lamps
props     name -> (x, top row)
spots     hotspot id -> (x, top row)
kits      prop name -> what THIS chamber keeps in it
"""


def _plan(feet, bench, ceil, ground, lamp, props, spots, kits, mirrored=False, ambient=0.42):
    return Plan(feet, bench, ceil, ground, lamp, mirrored, ambient, props, spots, kits)


PLANS = {
    # The haulage gallery. The rock leaves the mountain through the right-hand gallery, so the ore
    # rack stands on the floor by the cart road and the dwarf works just left of the cart's path.
    "workshop": _plan(
        feet=96, bench=(58, 72, 84), ceil=(6, 7), ground=82, lamp=(28, 48),
        props={"window": (36, 15), "bookshelf": (30, 57), "coinjar": (64, 44), "clock": (46, 40),
               "papers": (78, 76), "hourglass": (118, 74)},
        spots={"tasks": (62, 58), "calendar": (118, 56)},
        kits={"bookshelf": "ore", "papers": "tallies", "coinjar": "coins"}),

    # MIRRORED. The fire is cut into the LEFT wall and the smith works right of it, because a smith
    # stands between his fire and his anvil. The pot sits on the forge's own stone ledge, where the
    # takings are dropped in on the way past; the dial is chiselled into the chimney breast.
    "forge": _plan(
        feet=124, bench=(94, 74, 83), ceil=(10, 4), ground=85, lamp=(168, 46), mirrored=True,
        props={"window": (30, 16), "clock": (56, 30), "coinjar": (66, 60), "bookshelf": (152, 57),
               "papers": (112, 75), "hourglass": (138, 73)},
        spots={"tasks": (84, 58), "calendar": (134, 54)},
        kits={"bookshelf": "ingots", "papers": "orders", "coinjar": "coins"}),

    # The oven is built into the right-hand rock and the rack of proving jars stands beside it, within
    # arm's reach of the peel. The baker therefore works LEFT of centre, at a long low bench.
    "bakery": _plan(
        feet=82, bench=(46, 74, 85), ceil=(7, 6), ground=83, lamp=(62, 56),
        props={"window": (48, 14), "clock": (28, 40), "coinjar": (28, 56), "bookshelf": (116, 56),
               "papers": (46, 77), "hourglass": (64, 75)},
        spots={"tasks": (94, 58), "calendar": (28, 70)},
        kits={"bookshelf": "jars", "papers": "recipes", "coinjar": "coins"}),

    # The still needs headroom, so this chamber's ceiling is high and its floor is wet and built up.
    # The casks are racked away from the firebox on the left wall; the almanac hangs where the
    # distiller can see it while he watches the run.
    "distillery": _plan(
        feet=104, bench=(70, 70, 86), ceil=(8, 5), ground=80, lamp=(30, 64),
        props={"window": (36, 16), "bookshelf": (32, 58), "coinjar": (64, 44), "clock": (62, 26),
               "papers": (110, 78), "hourglass": (86, 76)},
        spots={"tasks": (118, 56), "calendar": (64, 66)},
        kits={"bookshelf": "casks", "papers": "notes", "coinjar": "copper"}),

    # MIRRORED. The bottle shelves take the LEFT wall and the alchemist works right of them. His
    # daystone is not on the wall at all: it is a cluster grown low behind the bench, which is what
    # gives this chamber its cold light from underneath.
    "lab": _plan(
        feet=118, bench=(88, 76, 84), ceil=(5, 8), ground=84, lamp=(172, 50), mirrored=True,
        props={"window": (82, 60), "clock": (62, 26), "bookshelf": (146, 56), "coinjar": (134, 74),
               "papers": (110, 76), "hourglass": (124, 74)},
        spots={"tasks": (84, 58), "calendar": (128, 56)},
        kits={"bookshelf": "cores", "papers": "notes", "coinjar": "silver"}),

    # A vault. The gold is the only lamp, so the dial is hung as far from it as the chamber allows -
    # a dwarf checking the hour should not have to stand in the light of the hoard to do it. The rack
    # of graded gems is the chamber's working surface, between the counting bench and the heap.
    "treasury": _plan(
        feet=92, bench=(56, 72, 86), ceil=(9, 5), ground=86, lamp=(34, 44),
        props={"window": (30, 60), "clock": (30, 32), "coinjar": (136, 74), "bookshelf": (104, 56),
               "papers": (100, 78), "hourglass": (118, 76)},
        spots={"tasks": (60, 58), "calendar": (134, 56)},
        kits={"bookshelf": "gems", "papers": "ledgers", "coinjar": "coins"}),

    # A wet cavern nobody squared off: the highest, most jagged ceiling of the eight and a floor that
    # has silted up. The picking baskets stand by the door on the left; the beds are on the right and
    # light themselves.
    "mushrooms": _plan(
        feet=88, bench=(52, 74, 85), ceil=(4, 9), ground=80, lamp=(36, 62), ambient=0.58,
        props={"window": (32, 18), "bookshelf": (30, 56), "coinjar": (62, 44), "clock": (62, 28),
               "papers": (66, 77), "hourglass": (90, 75)},
        spots={"tasks": (100, 58), "calendar": (124, 58)},
        kits={"bookshelf": "baskets", "papers": "notes", "coinjar": "copper"}),

    # MIRRORED, and the lowest ceiling of the eight: bunks are cut into the LEFT wall and a dwarf
    # sleeping under rock wants it close. The almanac hangs at the foot of the bunks, where you look
    # when you wake; the kit rack is by the door on the right.
    "quarters": _plan(
        feet=126, bench=(98, 70, 82), ceil=(11, 3), ground=86, lamp=(170, 52), mirrored=True,
        props={"window": (28, 14), "clock": (138, 60), "coinjar": (138, 76), "bookshelf": (152, 56),
               "papers": (120, 74), "hourglass": (110, 72)},
        spots={"tasks": (88, 58), "calendar": (60, 60)},
        kits={"bookshelf": "kit", "papers": "notes", "coinjar": "coins"}),
}
