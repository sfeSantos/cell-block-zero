"""The dogs, 128 by 128 a frame, into assets/sprites.

Seen from the side, nose to the right, paws on the bottom edge of the cell,
in the same flat colours and dark outline as the guards. Five frames: two of
a run, one with the jaws open, one taking a hit, one down.

Written against a 64 wide grid, the size the cell used to be, and Cell scales
it into the real one. A half step places something one real pixel over; it
does not halve a box, which covers [x0, x1 + 1) in grid units either way. The
outline is S pixels thick so it survives being minified down a corridor. Same
arrangement as tools/guards.py.

    python3 tools/dogs.py assets/sprites
"""

import os
import sys

from PIL import Image, ImageDraw

CELL = 128
GRID = 64
S = CELL // GRID

FRAMES = ("walk1", "walk2", "bite", "pain", "dead")

COAT = (62, 50, 42)
COAT_LO = (42, 34, 29)
COAT_HI = (86, 70, 57)
TAN = (139, 104, 62)
TAN_LO = (104, 76, 45)
MOUTH = (96, 28, 32)
TONGUE = (170, 72, 76)
FANG = (238, 236, 226)
EYE = (226, 176, 48)
COLLAR = (104, 36, 30)
STUD = (188, 176, 110)
EDGE = (16, 15, 18, 255)


class Cell:
    """Grid units in, pixels out. Ranges are inclusive and scale half open,
    so a box keeps the width it was written with."""

    def __init__(self):
        self.im = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im, "RGBA")

    def box(self, x0, y0, x1, y1, c):
        self.d.rectangle([x0 * S, y0 * S, (x1 + 1) * S - 1, (y1 + 1) * S - 1], fill=c)

    def poly(self, pts, c):
        self.d.polygon([(x * S, y * S) for x, y in pts], fill=c)

    def ellipse(self, x0, y0, x1, y1, c):
        self.d.ellipse([x0 * S, y0 * S, (x1 + 1) * S - 1, (y1 + 1) * S - 1], fill=c)

    def outline(self, width=S):
        for _ in range(width):
            src = self.im.load()
            edge = []
            for y in range(CELL):
                for x in range(CELL):
                    if src[x, y][3] != 0:
                        continue
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < CELL and 0 <= ny < CELL and src[nx, ny][3] > 128:
                            edge.append((x, y))
                            break
            for x, y in edge:
                self.im.putpixel((x, y), EDGE)


def legs(c, front, back):
    """front and back say how far each pair is thrown forward."""
    c.box(40 + front, 44, 45 + front, 58, COAT_LO)
    c.box(14 + back, 44, 19 + back, 58, COAT_LO)
    c.box(40 + front, 56, 47 + front, 58, TAN_LO)
    c.box(14 + back, 56, 21 + back, 58, TAN_LO)
    c.box(44 - front, 44, 49 - front, 57, COAT)
    c.box(18 - back, 44, 23 - back, 57, COAT)
    c.box(44 - front, 55, 51 - front, 57, TAN)
    c.box(18 - back, 55, 25 - back, 57, TAN)

    # toes on the near paws, and the hock above each one
    for x0, x1 in ((44 - front, 51 - front), (18 - back, 25 - back)):
        for i in range(2):
            c.box(x0 + 3 + i * 2.5, 55, x0 + 3.5 + i * 2.5, 57, TAN_LO)

        c.box(x0, 49, x0 + 5, 49.5, COAT_HI)


def body(c, drop=0):
    y = 30 + drop

    # haunches, back and chest
    c.ellipse(10, y + 2, 32, y + 20, COAT)
    c.ellipse(34, y + 1, 54, y + 18, COAT)
    c.box(16, y + 2, 48, y + 18, COAT)
    c.box(16, y + 2, 48, y + 5, COAT_HI)
    c.box(16, y + 15, 48, y + 18, COAT_LO)
    c.box(34, y + 8, 50, y + 18, TAN_LO)

    # the ridge along his back, and the last two ribs showing through the
    # coat. Any more than two and he comes out striped.
    c.box(16, y + 2, 48, y + 2.5, (108, 90, 74))

    for i in range(2):
        c.box(27 + i * 5, y + 8, 27.5 + i * 5, y + 13, COAT_LO)

    # tail, out behind him
    c.poly([(10, y + 4), (2, y - 4), (6, y - 6), (14, y + 6)], COAT)


def head(c, open_jaws=False, drop=0, back=0):
    y = 26 + drop
    x = 46 - back

    c.ellipse(x - 8, y - 2, x + 10, y + 16, COAT)
    c.box(x - 2, y - 2, x + 10, y + 12, COAT)
    c.box(x - 2, y - 2, x + 10, y + 1, COAT_HI)

    # ears, flat back, with the inside of the near one showing
    c.poly([(x - 6, y - 1), (x - 1, y - 10), (x + 3, y - 1)], COAT)
    c.poly([(x - 4, y - 1.5), (x - 1, y - 7), (x + 1.5, y - 1.5)], (92, 62, 54))
    c.poly([(x + 2, y - 1), (x + 7, y - 9), (x + 10, y - 1)], COAT_LO)

    # the collar, round the throat and in front of the chest
    c.box(x - 7, y + 9, x - 4, y + 17, COLLAR)
    c.box(x - 7, y + 12, x - 4, y + 13.5, STUD)

    # a brow over the eye, so he looks at you rather than past you
    c.box(x + 5, y + 2.5, x + 9, y + 3.5, COAT_LO)
    c.box(x + 6, y + 4, x + 8, y + 6, EYE)
    c.box(x + 7, y + 4, x + 8, y + 5, (32, 28, 24))
    c.box(x + 6, y + 4, x + 6.5, y + 4.5, (250, 236, 180))

    if open_jaws:
        c.poly([(x + 8, y + 4), (x + 20, y - 1), (x + 20, y + 8), (x + 9, y + 10)], COAT)
        c.poly([(x + 9, y + 12), (x + 20, y + 20), (x + 20, y + 13), (x + 8, y + 11)], COAT_LO)
        c.poly([(x + 10, y + 9), (x + 19, y + 8), (x + 19, y + 14), (x + 10, y + 12)], MOUTH)
        c.poly([(x + 11, y + 10.5), (x + 18, y + 11), (x + 17, y + 13),
                (x + 11, y + 12)], TONGUE)
        c.poly([(x + 12, y + 7), (x + 15, y + 7), (x + 14, y + 12)], FANG)
        c.poly([(x + 16, y + 13), (x + 18, y + 13), (x + 17, y + 8)], FANG)
        c.poly([(x + 16, y + 7.5), (x + 18, y + 7.5), (x + 17.5, y + 10)], FANG)
        c.poly([(x + 12, y + 13), (x + 14, y + 13), (x + 13.5, y + 10.5)], FANG)
    else:
        c.box(x + 8, y + 6, x + 19, y + 12, COAT)
        c.box(x + 8, y + 6, x + 19, y + 8, COAT_HI)
        c.box(x + 17, y + 7, x + 19, y + 9, (26, 24, 24))
        c.box(x + 17.5, y + 7.5, x + 18, y + 8, (62, 58, 56))
        c.box(x + 9, y + 12, x + 18, y + 13, COAT_LO)
        c.box(x + 10, y + 11, x + 16, y + 11.5, (72, 58, 48))


def draw(frame):
    c = Cell()

    if frame == "dead":
        c.ellipse(6, 46, 58, 60, (74, 12, 13, 150))
        c.ellipse(14, 48, 40, 58, (122, 20, 20, 205))
        c.ellipse(12, 42, 44, 56, COAT)
        c.box(18, 42, 40, 56, COAT)
        c.box(18, 42, 40, 45, COAT_HI)
        c.box(20, 50, 40, 56, TAN_LO)
        c.poly([(12, 46), (2, 40), (5, 37), (16, 44)], COAT)
        # legs stuck out sideways
        c.box(20, 34, 25, 44, COAT_LO)
        c.box(32, 33, 37, 44, COAT_LO)
        c.box(18, 32, 27, 35, TAN_LO)
        c.box(30, 31, 39, 34, TAN_LO)
        # head flat on the floor
        c.ellipse(42, 44, 58, 58, COAT)
        c.poly([(46, 45), (50, 37), (53, 45)], COAT)
        c.box(54, 48, 62, 54, COAT)
        c.box(54, 48, 62, 50, COAT_HI)
        c.box(50, 48, 53, 50, (26, 24, 24))

        # the eye shut, and his tongue out on the floor
        c.box(46, 48, 49, 48.5, COAT_LO)
        c.poly([(56, 54), (62, 54), (61, 57), (56, 56.5)], TONGUE)
        c.outline()

        return c.im

    if frame == "walk1":
        legs(c, 4, -4)
        body(c, 0)
        head(c, False, 0, 0)
    elif frame == "walk2":
        legs(c, -4, 4)
        body(c, 1)
        head(c, False, 1, 1)
    elif frame == "bite":
        legs(c, 4, -6)
        body(c, -2)
        head(c, True, -4, 8)
    else:
        legs(c, 0, 2)
        body(c, 2)
        head(c, False, 3, 4)

    c.outline()

    if frame == "pain":
        red = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        d = ImageDraw.Draw(red)
        d.rectangle([12 * S, 28 * S, 58 * S, 58 * S], fill=(214, 36, 32, 70))
        out = Image.alpha_composite(c.im, Image.composite(
            red, Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0)),
            c.im.split()[3]))
        dd = ImageDraw.Draw(out)
        for x, y in ((20, 30), (28, 26), (36, 31), (44, 24)):
            dd.rectangle([x * S, y * S, (x + 2) * S, (y + 2) * S], fill=(176, 24, 24, 255))

        return out

    return c.im


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/sprites"
    os.makedirs(out, exist_ok=True)
    for frame in FRAMES:
        draw(frame).save("%s/dg.%s.png" % (out, frame))

    print("%d files written to %s" % (len(FRAMES), out))
