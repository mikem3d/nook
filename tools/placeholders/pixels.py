"""Tiny stdlib-only pixel canvas. Every colour comes from PAL, so the 32-colour shared palette
rule (docs/ART.md) holds by construction: `save` refuses anything else.

Coordinates are image coordinates: x right, y down, origin top-left.
"""
import os
import struct
import zlib

T = (0, 0, 0, 0)


def _rgb(h):
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


# The shared palette of the dwarf mine theme. Order is the order written to theme.json.
#
# It is cut as RAMPS, because the mine is lit by a few small fires in a lot of dark and every
# surface has to be able to travel from "deep shadow" to "right next to the flame" (see mine.py):
#   cool rock  ink -> rock_dk -> rock -> rock_lt -> stone -> pale -> white
#   warm rock  ink -> warm_dk -> warm -> warm_lt -> sand  -> cream -> white   (rock under firelight)
#   timber     ink -> wood_dk -> wood -> wood_lt -> sand  -> cream -> white
# The two rock ramps share their ends, so a wall can cross from lamplight into the dark without
# leaving the palette. Everything else is an object colour: ore, flame, glass, cloth, skin.
HEX = {
    "ink": "14131c", "rock_dk": "242231", "rock": "393649", "rock_lt": "565165", "stone": "827c93",
    "pale": "b8b2c2", "white": "f4f1e6",
    "warm_dk": "342734", "warm": "55404a", "warm_lt": "86675f",
    "wood_dk": "3d2a1f", "wood": "6b4529", "wood_lt": "a8713f", "sand": "d9a766", "cream": "f0d9a0",
    "copper": "bf6a3c",
    "skin": "e8b088", "skin_dk": "b97a5c",
    "red_dk": "8a2b32", "red": "d0453c", "orange": "ee8a3a", "yellow": "f7cf4f",
    "green_dk": "2f5d43", "green": "4f9a5a", "green_lt": "9bd46a",
    "blue_dk": "2c3f78", "blue": "4a7ac8", "sky": "8fd0ee", "teal": "3fa6a0",
    "purple_dk": "4b2d6b", "purple": "8a52a8", "pink": "e58bb0",
}
assert len(HEX) <= 32, len(HEX)
PAL = {name: _rgb(h) for name, h in HEX.items()}
_ALLOWED = set(PAL.values())


def c(name):
    return PAL[name]


def noise(x, y, seed=0):
    """Deterministic 0..1 hash, so regenerated art is byte-identical."""
    n = (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
    n = (n ^ (n >> 13)) * 1274126177
    return ((n ^ (n >> 16)) & 0xFFFF) / 65536.0


class Img:
    def __init__(self, w, h, fill=None):
        self.w, self.h = w, h
        self.px = [[PAL[fill] if fill else T] * w for _ in range(h)]

    def set(self, x, y, colour):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = PAL[colour] if colour else T

    def get(self, x, y):
        return self.px[y][x] if 0 <= x < self.w and 0 <= y < self.h else T

    def rect(self, x, y, w, h, colour):
        for j in range(y, y + h):
            for i in range(x, x + w):
                self.set(i, j, colour)

    def dots(self, points, colour):
        for x, y in points:
            self.set(x, y, colour)

    def rows(self, x, y, spans, colour):
        """Stacked horizontal runs: spans[i] = (dx, width) for row y + i. Good for domes and heaps."""
        for j, (dx, w) in enumerate(spans):
            self.rect(x + dx, y + j, w, 1, colour)

    def disc(self, cx, cy, r, colour):
        """Filled circle around the point (cx, cy), which may sit between pixels (x.5)."""
        for j in range(self.h):
            for i in range(self.w):
                if (i + 0.5 - cx) ** 2 + (j + 0.5 - cy) ** 2 <= r * r:
                    self.set(i, j, colour)

    def blit(self, other, ox, oy):
        for j in range(other.h):
            for i in range(other.w):
                if other.px[j][i][3] and 0 <= ox + i < self.w and 0 <= oy + j < self.h:
                    self.px[oy + j][ox + i] = other.px[j][i]

    def crop(self, x, y, w, h):
        out = Img(w, h)
        out.px = [row[x:x + w] for row in self.px[y:y + h]]
        return out

    def mirrored(self):
        out = Img(self.w, self.h)
        out.px = [list(reversed(row)) for row in self.px]
        return out

    def outline(self, colour="ink"):
        """Hard 1 px outline around everything opaque (the character rule in docs/ART.md)."""
        edge = []
        for j in range(self.h):
            for i in range(self.w):
                if not self.px[j][i][3] and any(self.get(i + dx, j + dy)[3] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    edge.append((i, j))
        self.dots(edge, colour)

    def speckle(self, x, y, w, h, colour, chance, seed, only=None):
        """Scatter texture pixels; `only` limits it to pixels that currently have that colour."""
        for j in range(y, y + h):
            for i in range(x, x + w):
                if noise(i, j, seed) < chance and (only is None or self.get(i, j) == PAL[only]):
                    self.set(i, j, colour)

    def save(self, path):
        stray = {p for row in self.px for p in row if p[3]} - _ALLOWED
        assert not stray, f"{path}: colours outside the palette: {stray}"
        raw = b"".join(b"\x00" + bytes(v for p in row for v in p) for row in self.px)

        def chunk(tag, data):
            body = tag + data
            return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n")
            f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 6, 0, 0, 0)))
            f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
            f.write(chunk(b"IEND", b""))


def sheet(frames):
    """Frames side by side, left to right."""
    out = Img(sum(f.w for f in frames), max(f.h for f in frames))
    x = 0
    for f in frames:
        out.blit(f, x, 0)
        x += f.w
    return out
