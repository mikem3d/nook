"""The fixed geometry every theme shares (docs/ART.md, "Chamber geometry"). Image coordinates:
y counts down from the top of the 192x108 canvas. `bl` converts to the manifest's bottom-left origin.
"""
W, H = 192, 108
BAR = 11            # header lintel
SIDE = 6            # rock at the left and right
FLOOR = 90          # first row of the floor; the character's feet stand on it

# Connectors. Any scene meets any other scene, so these never vary.
LADDER_X, LADDER_W = 12, 14          # shaft columns 12..25 on the top and bottom edges
LADDER_BOTTOM_TOP = 80               # the ladder pokes 10 px above the floor of the upper chamber
TUNNEL_TOP, TUNNEL_H, TUNNEL_W = 62, 30, 10   # mouth rows 62..91 on the left and right edges

FEET = (100, H - FLOOR)              # bottom-centre of the character frame, from the bottom-left
BENCH_TOP = 84                       # the bench hides the lowest 6 px of the character
BENCH_X, BENCH_W = 66, 68

ORB = 28
PORTRAIT = 20


def bl(x, y_top, h):
    """Bottom-left manifest position of something h tall whose top row is y_top."""
    return [x, H - y_top - h]
