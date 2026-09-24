"""One deliberate floor plan per chamber.

The previous pass gave all eight chambers the same furniture in the same pixels and only changed the
right-hand feature, so the mine read as one template redressed eight times. Everything that CAN move
without a Swift change now moves per scene: where the vitals props hang, where the two hotspots hang,
where the dwarf stands, which side of the room his chamber's feature occupies, how long and how high
his bench is, how low the ceiling hangs, how deep the grit lies and where the wall lantern is nailed.

Nothing here is random. Each plan is a working layout: the bakery's proving rack stands beside its
oven so the baker can reach it, the treasury's dial is as far from the gold as the chamber allows,
the distiller works to one side of a still that needs the middle of the floor, the mushroom farmer
keeps his baskets by the door.

Coordinates are IMAGE coordinates - x from the left, rows from the TOP of the 192x108 canvas - and a
prop or hotspot is given by its TOP-LEFT corner. `make_placeholders` converts to the manifest's
bottom-left origin, and runs every plan through `tools/art/placement.py` first, which knows the
rules and moves anything that breaks one:

  ladder      x 12..25, every row: the shaft hangs there
  tunnels     x 0..9 and x 182..191, rows 62..91: the tunnel pieces cover them
  header      rows 0..10: the lintel
  bubble      a hotspot's HIT rectangle may not reach up into rows 0..54 at all, which leaves it
              about fifteen rows to live in; sideways it is free. Props may go high on the left,
              but x 76 rightwards, rows 11..55, is the 2x speech bubble's own box: calm rock only.
  overlap     no prop under another prop, and nothing behind the dwarf but the wall (a prop drawn
              in FRONT of him, z > 2, may of course overlap - that is what a bench is for)
"""
from collections import namedtuple

Plan = namedtuple("Plan", "feet bench ceil ground lamp mirrored ambient props spots kits")
Plan.__doc__ = """
feet      x the dwarf stands on; his feet are always on the floor at row 90
bench     (x, width, top row) of the plank bench he works at
ceil      (depth, sag) of the rock hanging under the lintel
ground    the top row of the trodden grit
lamp      (x, top row) of this chamber's 9x15 wall lantern
mirrored  True: the chamber's own feature is painted on the right and flipped to the LEFT.
          Tried and dropped - see the module note at the foot of this file
ambient   how much light this chamber has of its own, before its lamps
props     name -> (x, top row)
spots     hotspot id -> (x, top row)
kits      prop name -> what THIS chamber keeps in it (props.KITS / PAPER_KITS / JAR_KITS)
"""


def _plan(feet, bench, ceil, ground, lamp, props, spots, kits, mirrored=False, ambient=0.42):
    return Plan(feet, bench, ceil, ground, lamp, mirrored, ambient, props, spots, kits)


PLANS = {
    # The haulage gallery, where the rock leaves the mountain. A long low bench under a shallow
    # ceiling, the road and the gallery mouth on the right, and the tally board hung at the
    # loader's elbow. The lantern is nailed high by the ladder, which is where a hauler wants it.
    "workshop": _plan(
        feet=100, bench=(56, 76, 84), ceil=(6, 8), ground=82, lamp=(28, 40),
        props={"window": (32, 14), "clock": (44, 38), "coinjar": (62, 40), "bookshelf": (30, 56),
               "papers": (110, 76), "hourglass": (124, 74)},
        spots={"tasks": (63, 56), "calendar": (114, 54)},
        kits={"bookshelf": "ore", "papers": "tallies", "coinjar": "coins"}),

    # A hot room with rock pressing down on it: the heaviest ceiling of the eight, a stone bench
    # instead of a plank one, and an almanac hung low by the door rather than up on the wall, where
    # the smoke would have taken it years ago. The smith stands between his fire and his anvil, so
    # he works at the RIGHT-hand end of his bench with the rack of finished bars behind him.
    "forge": _plan(
        feet=96, bench=(64, 64, 83), ceil=(12, 3), ground=86, lamp=(28, 46), ambient=0.38,
        props={"window": (30, 14), "clock": (30, 40), "coinjar": (46, 40), "bookshelf": (110, 58),
               "papers": (84, 76), "hourglass": (100, 74)},
        spots={"tasks": (60, 54), "calendar": (28, 68)},
        kits={"bookshelf": "ingots", "papers": "orders", "coinjar": "coins"}),

    # The oven is built into the right-hand rock and the rack of proving jars stands beside it,
    # within arm's reach of the peel. The baker therefore works FAR LEFT at the longest, lowest
    # bench in the mine, and his lantern hangs out over the middle of the floor rather than by the
    # ladder. His almanac is down at knee height by the door, which is where he checks the day.
    "bakery": _plan(
        feet=76, bench=(38, 74, 86), ceil=(8, 5), ground=84, lamp=(100, 34),
        props={"window": (28, 52), "clock": (30, 30), "coinjar": (48, 32), "bookshelf": (116, 56),
               "papers": (46, 78), "hourglass": (96, 76)},
        spots={"tasks": (88, 54), "calendar": (28, 72)},
        kits={"bookshelf": "jars", "papers": "recipes", "coinjar": "coins"}),

    # The still needs the MIDDLE of the floor and headroom over it, so this chamber has the highest
    # ceiling and its feature is dead centre with the distiller working to the left of it. The
    # casks are racked far right, away from the firebox; the floor is wet and built up.
    "distillery": _plan(
        feet=62, bench=(32, 62, 86), ceil=(4, 6), ground=80, lamp=(170, 52),
        props={"window": (30, 14), "clock": (60, 30), "coinjar": (30, 44), "bookshelf": (150, 56),
               "papers": (36, 78), "hourglass": (76, 76)},
        spots={"tasks": (28, 56), "calendar": (118, 58)},
        kits={"bookshelf": "casks", "papers": "notes", "coinjar": "copper"}),

    # The alchemist keeps his shelves of bottles at the far right and his cores racked where he can
    # reach them, and he stands left of both. His daystone is not on the wall at all: it is a
    # cluster grown low out of the seam, which is what gives this chamber its cold light from
    # underneath. Short high bench, shallow ceiling, almost no grit - a swept room.
    "lab": _plan(
        feet=104, bench=(74, 64, 81), ceil=(5, 4), ground=87, lamp=(58, 46),
        props={"window": (28, 14), "clock": (30, 40), "coinjar": (46, 40), "bookshelf": (28, 56),
               "papers": (86, 73), "hourglass": (104, 71)},
        spots={"tasks": (60, 56), "calendar": (116, 56)},
        kits={"bookshelf": "cores", "papers": "notes", "coinjar": "silver"}),

    # A vault. The gold is the only lamp worth the name, so the dial is chiselled as far from it as
    # the chamber allows - a dwarf checking the hour should not have to stand in the light of the
    # hoard to do it. The counting bench is short and stands high; the floor is swept flagstone.
    "treasury": _plan(
        feet=84, bench=(58, 58, 85), ceil=(9, 4), ground=87, lamp=(30, 52),
        props={"window": (30, 14), "clock": (30, 34), "coinjar": (46, 36), "bookshelf": (96, 56),
               "papers": (60, 77), "hourglass": (74, 75)},
        spots={"tasks": (53, 56), "calendar": (28, 68)},
        kits={"bookshelf": "gems", "papers": "ledgers", "coinjar": "coins"}),

    # A wet cavern nobody squared off: the most jagged ceiling of the eight and a floor that has
    # silted right up. The beds run the whole width rather than sitting in one corner, so there is
    # no "feature wall" here at all, and the caps light the place themselves - this is the
    # brightest chamber in the mine, and the only one lit from below.
    "mushrooms": _plan(
        feet=104, bench=(70, 62, 85), ceil=(4, 10), ground=78, lamp=(30, 58), ambient=0.60,
        props={"window": (30, 16), "clock": (60, 28), "coinjar": (62, 44), "bookshelf": (30, 56),
               "papers": (74, 77), "hourglass": (128, 75)},
        spots={"tasks": (62, 56), "calendar": (124, 58)},
        kits={"bookshelf": "baskets", "papers": "notes", "coinjar": "copper"}),

    # The lowest ceiling of the eight: bunks cut into the right-hand rock, and a dwarf sleeping
    # under rock wants it close. The kit rack is at the foot of the bunks where he can reach it
    # half asleep, the candle is the only warm light, and the almanac hangs where you look when you
    # wake. He stands well left, off the rug.
    "quarters": _plan(
        feet=70, bench=(48, 54, 82), ceil=(12, 3), ground=85, lamp=(26, 60),
        props={"window": (30, 14), "clock": (58, 26), "coinjar": (44, 40), "bookshelf": (86, 56),
               "papers": (62, 74), "hourglass": (78, 72)},
        spots={"tasks": (28, 56), "calendar": (118, 62)},
        kits={"bookshelf": "kit", "papers": "notes", "coinjar": "coins"}),
}

# Mirroring, tried and dropped.
#
# The forge was built with `mirrored=True`: its fire cut into the LEFT wall, the smith standing
# between the fire and his anvil, everything else pushed over to the right. It was the most
# striking single image of the eight, and it was the worst chamber in the set, for a reason that
# only shows up once you look at all eight together.
#
# A chamber may put nothing in the 2x speech bubble's box - x 76 rightwards, rows 11..55. When the
# feature is on the RIGHT, the feature's own quiet mass (an oven dome, a chimney breast, a wall of
# shelves) is what fills that box, and the vitals props take the free upper left. Flip the feature
# over and both of those go: the upper right becomes bare grey wall with nothing allowed in it, and
# every prop, both hotspots and the dwarf are crushed into the 34 rows underneath. The room reads
# bottom-heavy with a dead quarter, and the hotspots end up hanging on the feature itself.
#
# So the variety comes from the other axes instead, and one of them does the same job honestly:
# the distillery's still stands DEAD CENTRE with the distiller working to the left of it, and the
# mushroom farm has no feature wall at all - its beds run the whole width of the floor. The feature
# is not always on the right; it is just never on the left, where the room cannot afford it.
