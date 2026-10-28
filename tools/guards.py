"""The guard art, one 128 by 128 file per frame, written into assets/sprites.

The cell is one tile wide and one tile tall: feet on the bottom edge, head
near the top, the figure filling about two thirds of the width so two of them
can stand side by side in a doorway without overlapping. Flat colours, two
tone shading and a dark line around everything, so a guard still reads against
a dark corridor twenty tiles away.

Everything below is written against a 64 wide grid, which is what the cell
used to be, and Cell scales it into the real one, so a coordinate here is a
sixty fourth of a tile whatever CELL grows to. A box covers the half open
range [x0, x1 + 1) in grid units, which means a fractional end extends it
rather than halving it: box(10, y, 10.5, y) is three pixels wide at S = 2,
not one. Half steps are for placing things, 31.5 and 32 being different
columns. The outline is S pixels thick, not one, or it disappears when the
figure is minified down a corridor.

    python3 tools/guards.py assets/sprites
"""

import math
import os
import sys

from PIL import Image, ImageDraw

CELL = 128
GRID = 64
S = CELL // GRID

FEET = 60
HEAD_Y = 14

# Each rank keeps its colours in every frame, because that is how the player
# tells them apart before they are close enough to shoot at.
TIERS = {
    "g1": dict(
        name="Guard",
        skin=(205, 158, 122), skin_lo=(168, 124, 92),
        cloth=(69, 87, 138), cloth_lo=(47, 60, 99), cloth_hi=(96, 117, 173),
        trouser=(51, 56, 77), trouser_lo=(35, 39, 56),
        boot=(31, 31, 36), hat=(46, 56, 92), hat_hi=(72, 86, 130),
        gun=(56, 56, 60), gun_hi=(96, 97, 104),
        vest=None, visor=None, bulk=1.0,
    ),
    "g2": dict(
        name="Sergeant",
        skin=(189, 143, 107), skin_lo=(152, 111, 80),
        cloth=(87, 89, 59), cloth_lo=(62, 64, 41), cloth_hi=(116, 118, 80),
        trouser=(66, 66, 48), trouser_lo=(46, 46, 33),
        boot=(36, 33, 28), hat=(77, 79, 56), hat_hi=(104, 106, 76),
        gun=(46, 46, 51), gun_hi=(86, 87, 94),
        vest=(56, 59, 43), visor=None, bulk=1.1,
    ),
    "g3": dict(
        name="Riot captain",
        skin=(179, 133, 102), skin_lo=(140, 101, 76),
        cloth=(38, 41, 48), cloth_lo=(26, 28, 33), cloth_hi=(58, 62, 72),
        trouser=(28, 30, 36), trouser_lo=(20, 21, 26),
        boot=(20, 20, 23), hat=(26, 28, 33), hat_hi=(48, 51, 59),
        gun=(36, 36, 40), gun_hi=(74, 75, 82),
        vest=(48, 51, 61), visor=(217, 51, 46), bulk=1.25,
    ),
}

# The prisoners. Same build as a guard so they read as people at a glance,
# in cell clothes, bare headed and with nothing but their hands.
TIERS["con"] = dict(
    name="Prisoner",
    skin=(179, 143, 117), skin_lo=(142, 110, 88),
    cloth=(143, 140, 133), cloth_lo=(110, 108, 103), cloth_hi=(176, 173, 166),
    trouser=(102, 102, 107), trouser_lo=(76, 76, 80),
    boot=(46, 43, 40), hat=None, hat_hi=None,
    gun=None, gun_hi=None,
    vest=None, visor=None, bulk=0.95, stripes=True, hair=(62, 50, 42),
)

CON_FRAMES = ("idle", "walk1", "walk2", "hit", "pain", "die1", "dead")

BLOOD = (142, 24, 24)
BLOOD_HI = (196, 44, 40)

FRAMES = ("idle", "walk1", "walk2", "walk3", "walk4", "aim", "fire", "pain",
          "die1", "die2", "die3", "dead", "sleep")


def lighten(c, f=1.3):
    return tuple(min(255, int(v * f)) for v in c)


def darken(c, f=0.65):
    return tuple(int(v * f) for v in c)


class Cell:
    """A cell drawn in grid units. Every coordinate that goes in is multiplied
    by S on the way to the image, so the art is written once and comes out at
    whatever CELL is. Ranges are inclusive, the way Pillow has them, and they
    scale half open: a box from 10 to 20 is eleven grid columns and stays
    eleven when it becomes twenty two pixels."""

    def __init__(self, size=CELL):
        self.size = size
        self.grid = size // S
        self.im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def box(self, x0, y0, x1, y1, c):
        self.d.rectangle([x0 * S, y0 * S, (x1 + 1) * S - 1, (y1 + 1) * S - 1], fill=c)

    def poly(self, points, c):
        self.d.polygon([(x * S, y * S) for x, y in points], fill=c)

    def ellipse(self, x0, y0, x1, y1, c):
        self.d.ellipse([x0 * S, y0 * S, (x1 + 1) * S - 1, (y1 + 1) * S - 1], fill=c)

    def px(self, x, y, c):
        if 0 <= x < self.grid and 0 <= y < self.grid:
            self.box(x, y, x, y, c + (255,) if len(c) == 3 else c)

    def outline(self, c=(16, 15, 18, 255), width=S):
        """A dark line around everything that is not transparent, width real
        pixels thick. Each pass walks the edge of what the last one left, so
        the line grows outwards and never eats into the figure."""
        for _ in range(width):
            src = self.im.load()
            edge = []
            for y in range(self.size):
                for x in range(self.size):
                    if src[x, y][3] != 0:
                        continue
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < self.size and 0 <= ny < self.size and src[nx, ny][3] > 128:
                            edge.append((x, y))
                            break
            for x, y in edge:
                self.im.putpixel((x, y), c)

    def lift(self, dy):
        """Move the whole figure up or down, for the bob of a walk cycle."""
        if dy == 0:
            return
        moved = Image.new("RGBA", (self.size, self.size), (0, 0, 0, 0))
        moved.paste(self.im, (0, dy * S))
        self.im = moved
        self.d = ImageDraw.Draw(self.im)


def shadow(c, t, strength=70):
    c.ellipse(32 - int(13 * t["bulk"]), FEET - 3, 32 + int(13 * t["bulk"]),
              FEET + 3, (0, 0, 0, strength))


def legs(c, t, phase, drop=0):
    """phase 0 steps out on the left, 2 on the right, 1 and 3 pass through."""
    cx, sw = 32, int(12 * t["bulk"])
    top, knee = 38 + drop, 53 + drop
    out = 3

    left, right = cx - sw + 1, cx + sw - 1
    lx, rx = left, right
    lsole, rsole = FEET, FEET

    if phase == 0:
        lx, lsole = left - out, FEET
        rx, rsole = right - 2, FEET - 3
    elif phase == 2:
        lx, lsole = left + 2, FEET - 3
        rx, rsole = right + out, FEET

    # daylight between the legs, so the silhouette reads at a distance
    c.box(lx, top, cx - 3, knee, t["trouser"])
    c.box(cx + 3, top, rx, knee, t["trouser_lo"])

    # a crease down the front of each leg, and the seam at the side
    c.box(lx + 1.5, top, lx + 2, knee, lighten(t["trouser"], 1.18))
    c.box(cx - 3.5, top, cx - 3, knee, darken(t["trouser"], 0.8))
    c.box(rx - 2, top, rx - 1.5, knee, lighten(t["trouser_lo"], 1.2))
    c.box(cx + 3, top, cx + 3.5, knee, darken(t["trouser_lo"], 0.85))

    c.box(lx - 1, knee, cx - 2, lsole, t["boot"])
    c.box(cx + 2, knee, rx + 1, rsole, t["boot"])
    c.box(lx - 1, knee, cx - 2, knee + 1, (70, 70, 76))
    c.box(cx + 2, knee, rx + 1, knee + 1, (70, 70, 76))

    # laces up the front of the boot, a lit toe cap and a sole under it
    for b, (x0, x1, sole) in enumerate(((lx - 1, cx - 2, lsole), (cx + 2, rx + 1, rsole))):
        mid = (x0 + x1) * 0.5
        shine = lighten(t["boot"], 1.9 if b == 0 else 1.5)

        for i in range(3):
            y = knee + 2 + i * 1.5
            c.box(mid - 1.5, y, mid + 1.5, y + 0.5, shine)

        c.box(x0, sole - 2, x1, sole - 1.5, lighten(t["boot"], 1.6))
        c.box(x0, sole - 1, x1, sole, darken(t["boot"], 0.55))


def torso(c, t):
    cx, sw = 32, int(12 * t["bulk"])

    c.poly([(cx - sw, 22), (cx + sw, 22), (cx + sw - 2, 40), (cx - sw + 2, 40)],
           t["cloth"])
    c.poly([(cx + 1, 22), (cx + sw, 22), (cx + sw - 2, 40), (cx + 1, 40)],
           t["cloth_lo"])
    c.box(cx - sw, 22, cx + sw, 23, t["cloth_hi"])

    # the seam where the sleeve is set into the shoulder, both sides
    c.box(cx - sw + 2.5, 22, cx - sw + 3, 27, darken(t["cloth"], 0.82))
    c.box(cx + sw - 3, 22, cx + sw - 2.5, 27, darken(t["cloth_lo"], 0.85))

    if t.get("stripes"):
        for y in range(24, 40, 4):
            c.box(cx - sw + 1, y, cx + sw - 1, y + 1, t["cloth_lo"])

    if t["vest"]:
        c.box(cx - sw + 2, 25, cx + sw - 2, 37, t["vest"])
        c.box(cx - 1, 25, cx, 37, t["cloth_lo"])
        c.box(cx - sw + 2, 25, cx + sw - 2, 26, lighten(t["vest"], 1.35))

        # the plate laced across his chest, and the strap over each shoulder
        c.box(cx - sw + 3, 28.5, cx + sw - 3, 29, darken(t["vest"], 0.7))
        c.box(cx - sw + 3, 34, cx + sw - 3, 34.5, darken(t["vest"], 0.7))
        c.box(cx - sw + 1.5, 22, cx - sw + 3.5, 25, darken(t["vest"], 0.8))
        c.box(cx + sw - 3.5, 22, cx + sw - 1.5, 25, darken(t["vest"], 0.7))
    else:
        # collar, and the line of buttons down the front
        c.poly([(cx - 4, 22), (cx, 26), (cx + 4, 22)], darken(t["cloth"], 0.72))
        c.poly([(cx - 3.5, 22), (cx, 25), (cx + 3.5, 22)], t["cloth_hi"])
        c.box(cx - 0.5, 26, cx + 0.5, 38, darken(t["cloth"], 0.84))

        for y in (28, 32, 36):
            c.box(cx - 1, y, cx, y + 1, lighten(t["cloth_hi"], 1.1))

    # the belt, and a pocket under each arm
    c.box(cx - sw + 2, 38, cx + sw - 2, 40, darken(t["trouser"], 0.7))
    c.box(cx - sw + 2, 38, cx + sw - 2, 38.5, lighten(t["trouser"], 1.25))
    if t.get("stripes"):
        buckle, shine = darken(t["trouser"], 0.55), t["trouser"]
    elif t["visor"]:
        buckle, shine = (62, 62, 68), (96, 96, 104)
    else:
        buckle, shine = (96, 84, 46), (148, 130, 72)

    c.box(cx - 2, 38, cx + 2, 40, buckle)
    c.box(cx - 2, 38, cx + 2, 38.5, shine)


def arms(c, t, mode, lead=0):
    """mode: 'hang' at his sides, 'aim' with the gun up, 'thrown' over him."""
    cx, sw = 32, int(12 * t["bulk"])

    if mode == "aim":
        c.box(cx - sw - 3, 24, cx - sw + 1, 33, t["cloth"])
        c.box(cx + sw - 1, 24, cx + sw + 3, 33, t["cloth_lo"])
        c.box(cx - sw - 3, 31.5, cx - sw + 1, 32.5, darken(t["cloth"], 0.72))
        c.box(cx + sw - 1, 31.5, cx + sw + 3, 32.5, darken(t["cloth_lo"], 0.75))

        # the weapon held out level, lit along the top, open at the muzzle
        c.box(cx - 7, 29, cx + 7, 35, t["gun"])
        c.box(cx - 7, 29, cx + 7, 30, t["gun_hi"])
        c.box(cx - 7, 34.5, cx + 7, 35, darken(t["gun"], 0.55))
        c.box(cx - 5, 31, cx - 4.5, 34, darken(t["gun"], 0.6))
        c.box(cx + 4.5, 31, cx + 5, 34, darken(t["gun"], 0.6))
        c.ellipse(cx - 3, 30, cx + 3, 36, (18, 18, 20))
        c.ellipse(cx - 2, 31, cx + 2, 35, (44, 44, 48))

        # both hands on it, with the fingers told apart
        for hx in (cx - 6, cx + 2):
            c.box(hx, 33, hx + 4, 36, t["skin"])

            for i in range(3):
                c.box(hx + 1 + i, 33, hx + 1 + i, 33.5, t["skin_lo"])
    elif mode == "thrown":
        # arms flung out sideways, the way a man goes when he is hit
        c.box(cx - sw - 7, 24, cx - sw + 1, 29, t["cloth"])
        c.box(cx + sw - 1, 24, cx + sw + 7, 29, t["cloth_lo"])
        c.box(cx - sw - 11, 25, cx - sw - 6, 30, t["skin"])
        c.box(cx + sw + 6, 25, cx + sw + 11, 30, t["skin_lo"])
    elif mode == "punch":
        # one fist thrown at whoever is in front of him
        c.box(cx - sw - 3, 26, cx - sw + 1, 40, t["cloth"])
        c.box(cx - sw - 4, 40, cx - sw + 2, 44, t["skin"])
        c.box(cx + 2, 24, cx + sw + 1, 30, t["cloth_lo"])
        c.box(cx + sw - 2, 22, cx + sw + 8, 32, t["skin"])
        c.box(cx + sw - 2, 22, cx + sw + 8, 24, lighten(t["skin"], 1.12))
    else:
        c.box(cx - sw - 3, 24 - lead, cx - sw + 1, 39 - lead, t["cloth"])
        c.box(cx + sw - 1, 24 + lead, cx + sw + 3, 39 + lead, t["cloth_lo"])

        # the cuff, then the hand, then the knuckles in it
        c.box(cx - sw - 3, 38 - lead, cx - sw + 1, 39 - lead, darken(t["cloth"], 0.72))
        c.box(cx + sw - 1, 38 + lead, cx + sw + 3, 39 + lead, darken(t["cloth_lo"], 0.75))
        c.box(cx - sw - 3, 39 - lead, cx - sw + 1, 42 - lead, t["skin"])
        c.box(cx + sw - 1, 39 + lead, cx + sw + 3, 42 + lead, t["skin"])

        for i in range(3):
            c.box(cx - sw - 2 + i, 40.5 - lead, cx - sw - 2 + i, 42 - lead, t["skin_lo"])
            c.box(cx + sw + i, 40.5 + lead, cx + sw + i, 42 + lead, t["skin_lo"])

        if t["gun"]:
            c.box(cx + sw, 36 + lead, cx + sw + 7, 39 + lead, t["gun"])
            c.box(cx + sw, 36 + lead, cx + sw + 7, 36.5 + lead, t["gun_hi"])
            c.box(cx + sw + 5.5, 35 + lead, cx + sw + 6.5, 36 + lead, t["gun"])


def head(c, t, lean=0, hurt=False):
    cx, y = 32 + lean, HEAD_Y
    dark = darken(t["skin_lo"], 0.82)

    # the jaw comes in at the bottom, so it is a face and not a brick
    c.poly([(cx - 6, y - 7), (cx + 6, y - 7), (cx + 6, y + 4),
            (cx + 4, y + 7), (cx - 4, y + 7), (cx - 6, y + 4)], t["skin"])
    c.poly([(cx + 2, y - 7), (cx + 6, y - 7), (cx + 6, y + 4),
            (cx + 4, y + 7), (cx + 2, y + 7)], t["skin_lo"])

    # an ear on the lit side, and the neck under the chin
    c.box(cx - 7, y, cx - 6, y + 2.5, t["skin_lo"])
    c.box(cx - 2.5, y + 7, cx + 2.5, y + 8, dark)

    if t["hat"]:
        c.box(cx - 7, y - 9, cx + 7, y - 5, t["hat"])
        c.box(cx - 7, y - 9, cx + 7, y - 8.5, lighten(t["hat"], 1.5))
        c.box(cx - 8, y - 5, cx + 8, y - 3, t["hat_hi"])
        c.box(cx - 8, y - 3.5, cx + 8, y - 3, darken(t["hat"], 0.55))

        # the band and the badge over his forehead
        c.box(cx - 7, y - 6, cx + 7, y - 5, darken(t["hat"], 0.7))
        c.box(cx - 1, y - 8, cx + 1, y - 6.5, (186, 172, 96))
    else:
        # cropped hair, nothing on his head
        c.box(cx - 6, y - 8, cx + 6, y - 4, t["hair"])
        c.box(cx - 6, y - 8, cx + 6, y - 7, lighten(t["hair"], 1.3))
        c.box(cx - 6, y - 4.5, cx + 6, y - 4, darken(t["hair"], 0.7))

    if t["visor"]:
        c.box(cx - 7, y - 3, cx + 7, y + 2, t["visor"])
        c.box(cx - 7, y - 3, cx + 7, y - 2, (255, 150, 140))
        c.box(cx - 7, y + 1.5, cx + 7, y + 2, darken(t["visor"], 0.5))
        c.box(cx - 5, y - 2.5, cx - 2, y - 1.5, (255, 220, 214))
    elif hurt:
        # eyes screwed shut and the mouth open
        c.box(cx - 4.5, y - 1.5, cx - 1.5, y - 1, dark)
        c.box(cx + 1.5, y - 1.5, cx + 4.5, y - 1, dark)
        c.box(cx - 4, y, cx - 2, y + 1, (26, 24, 26))
        c.box(cx + 2, y, cx + 4, y + 1, (26, 24, 26))
        c.box(cx - 2, y + 3, cx + 2, y + 6, (52, 22, 24))
        c.box(cx - 1.5, y + 3.5, cx + 1.5, y + 4, (28, 10, 12))
    else:
        # brow, eyes with a white to each, the nose beside them, and a mouth
        c.box(cx - 5, y - 2, cx - 1.5, y - 1.5, dark)
        c.box(cx + 1.5, y - 2, cx + 5, y - 1.5, dark)
        c.box(cx - 4, y - 1, cx - 2, y + 1, (26, 24, 26))
        c.box(cx + 2, y - 1, cx + 4, y + 1, (26, 24, 26))
        c.px(cx - 4, y - 1, (218, 214, 210))
        c.px(cx + 2, y - 1, (198, 194, 190))
        c.box(cx - 0.5, y - 0.5, cx + 0.5, y + 2, t["skin_lo"])
        c.box(cx - 1, y + 2, cx + 1, y + 2.5, dark)
        c.box(cx - 2, y + 4, cx + 2, y + 5, t["skin_lo"])
        c.box(cx - 2, y + 4, cx + 2, y + 4.5, dark)


def standing(c, t, frame):
    phase = {"walk1": 0, "walk2": 1, "walk3": 2, "walk4": 3}.get(frame, 1)
    lead = {"walk2": 1, "walk4": -1}.get(frame, 0)
    mode = "hang"
    if frame in ("aim", "fire"):
        mode = "aim"
    elif frame == "hit":
        mode = "punch"

    shadow(c, t)
    legs(c, t, phase)
    torso(c, t)
    arms(c, t, mode, lead)
    head(c, t)
    c.outline()

    if frame in ("walk2", "walk4"):
        c.lift(-1 if frame == "walk2" else 1)

    if frame == "fire":
        muzzle(c)


def muzzle(c):
    """The flash, over the outline, because nothing outlines a muzzle flash.
    Six arms of uneven length round a white core: a diamond reads as a
    diamond, and powder going off does not come out tidy."""
    cx, cy = 32, 33

    # no halo round it. A flat ellipse of low alpha over a dark shirt comes
    # out as a brown oval with a hard rim, which reads as an object and not
    # as light. The arms and the core do the work.
    arms = ((0.0, 9.5), (0.9, 5.0), (1.9, 7.0), (3.1, 9.0), (4.1, 5.5), (5.2, 6.5))
    for a, reach in arms:
        wide = 0.55
        c.poly([(cx + math.cos(a) * reach, cy + math.sin(a) * reach * 0.8),
                (cx + math.cos(a + wide) * 3.0, cy + math.sin(a + wide) * 2.4),
                (cx + math.cos(a - wide) * 3.0, cy + math.sin(a - wide) * 2.4)],
               (255, 186, 64, 200))

    c.ellipse(cx - 4, cy - 3, cx + 4, cy + 3, (255, 232, 160, 235))
    c.ellipse(cx - 2, cy - 1.5, cx + 2, cy + 1.5, (255, 253, 240, 255))


def hurting(c, t):
    """Hit and still on his feet: jolted back, and bleeding."""
    shadow(c, t)
    legs(c, t, 1)
    torso(c, t)
    arms(c, t, "thrown")
    head(c, t, lean=-3, hurt=True)
    c.outline()

    cx = 32
    c.box(cx - 5, 27, cx + 1, 29, BLOOD_HI)
    c.box(cx - 3, 29, cx + 4, 31, BLOOD)
    for x, y in ((cx + 9, 24), (cx + 12, 27), (cx - 11, 30), (cx + 10, 33)):
        c.px(x, y, BLOOD_HI)
        c.px(x + 1, y, BLOOD)


def falling(c, t, step):
    """The standing figure tipped over about his boots, which is what the
    code drawn art does, so the asset falls the same way."""
    big = Cell(CELL * 3)
    inner = Cell()
    shadow(inner, t, 40)
    legs(inner, t, 1, drop=1)
    torso(inner, t)
    arms(inner, t, "thrown")
    head(inner, t, lean=-2, hurt=True)
    inner.outline()
    big.im.paste(inner.im, (CELL, CELL))

    angle = step * 80.0
    pivot = (CELL + 32 * S, CELL + FEET * S)
    turned = big.im.rotate(-angle, resample=Image.NEAREST, center=pivot)
    dx = int(round(20 * S * math.sin(math.radians(angle))))
    out = Cell()
    out.im.paste(turned.crop((CELL + dx, CELL, CELL * 2 + dx, CELL * 2)), (0, 0))
    out.d = ImageDraw.Draw(out.im)

    if step > 0.5:
        out.ellipse(6, 50, 30, 60, (96, 17, 18, 150))
        out.ellipse(12, 52, 24, 58, (142, 24, 24, 190))

    return out


def down(c, t):
    """Face down across the tile: head to the left, boots to the right."""
    c.ellipse(6, 44, 58, 61, (48, 8, 9, 140))
    c.ellipse(10, 48, 32, 60, (96, 17, 18, 210))

    # the pool has a lit rim where the floor catches it
    c.ellipse(8, 45, 56, 60, (118, 22, 22, 90))

    # boots and legs, out to the right
    c.box(50, 48, 60, 56, t["boot"])
    c.box(50, 48, 60, 50, lighten(t["boot"], 2.0))
    c.box(58, 48, 60, 56, darken(t["boot"], 0.6))
    c.box(50, 51.5, 57, 52, lighten(t["boot"], 1.5))
    c.box(34, 47, 52, 53, t["trouser"])
    c.box(34, 53, 52, 57, t["trouser_lo"])
    c.box(34, 47, 52, 48, lighten(t["trouser"], 1.2))

    # the torso across the middle, shoulders towards the head
    c.poly([(16, 43), (36, 45), (36, 57), (16, 55)], t["cloth"])
    c.box(16, 43, 36, 45, lighten(t["cloth_hi"], 1.1))
    c.box(16, 54, 36, 57, t["cloth_lo"])

    if t["vest"]:
        c.box(20, 46, 33, 54, t["vest"])
        c.box(20, 46, 33, 47, lighten(t["vest"], 1.4))

    # an arm thrown out ahead of him, the fingers open
    c.box(18, 38, 26, 44, t["cloth_lo"])
    c.box(18, 38, 26, 38.5, lighten(t["cloth_lo"], 1.3))
    c.ellipse(14, 35, 22, 43, t["skin"])

    for i in range(3):
        c.box(13.5, 36.5 + i * 2, 16, 37.5 + i * 2, t["skin_lo"])

    # head and cap, small, because he is lying down
    c.ellipse(8, 46, 20, 57, t["skin"])
    c.ellipse(8, 50, 15, 57, t["skin_lo"])
    cap = t["hat"] or t["hair"]
    c.box(6, 44, 19, 49, cap)
    c.box(6, 44, 19, 45, lighten(cap, 1.25))
    c.box(6, 48.5, 19, 49, darken(cap, 0.6))

    if t["visor"]:
        c.box(8, 49, 17, 52, darken(t["visor"], 0.75))

    c.outline()


def asleep(c, t):
    """In the chair by the door, which is the only time a riot captain is
    worth walking up to."""
    cx = 32

    c.ellipse(cx - 14, FEET - 3, cx + 14, FEET + 2, (0, 0, 0, 70))

    # the chair, from the side he is not on
    c.box(cx + 8, 18, cx + 12, 44, (74, 56, 36))
    c.box(cx + 8, 18, cx + 12, 20, (104, 80, 52))
    c.box(cx + 11.5, 20, cx + 12, 44, (52, 39, 25))
    c.box(cx - 14, 40, cx + 12, 44, (88, 66, 42))
    c.box(cx - 14, 40, cx + 12, 41, (120, 92, 58))
    c.box(cx - 14, 43.5, cx + 12, 44, (56, 42, 27))

    # the grain, one line down the back
    c.box(cx + 9.5, 21, cx + 10, 39, (90, 68, 44))
    c.box(cx - 13, 44, cx - 9, FEET, (62, 47, 30))
    c.box(cx + 7, 44, cx + 11, FEET, (62, 47, 30))

    # boots out in front of him
    c.box(cx - 20, 41, cx - 6, 48, t["trouser"])
    c.box(cx - 20, 48, cx - 8, 52, t["trouser_lo"])
    c.box(cx - 25, 49, cx - 17, 56, t["boot"])
    c.box(cx - 25, 49, cx - 17, 50, (70, 70, 76))
    c.box(cx - 25, 55, cx - 17, 56, darken(t["boot"], 0.55))
    c.box(cx - 23, 51.5, cx - 19, 52, lighten(t["boot"], 1.8))

    # slumped back
    c.poly([(cx - 10, 22), (cx + 10, 22), (cx + 8, 42), (cx - 12, 42)], t["cloth"])
    c.poly([(cx + 1, 22), (cx + 10, 22), (cx + 8, 42), (cx + 1, 42)], t["cloth_lo"])
    if t["vest"]:
        c.poly([(cx - 8, 25), (cx + 8, 25), (cx + 6, 39), (cx - 10, 39)], t["vest"])
        c.box(cx - 8, 25, cx + 8, 26, lighten(t["vest"], 1.35))

    # an arm off his lap, and the gun across his knees
    c.box(cx - 16, 28, cx - 10, 42, t["cloth_hi"])
    c.ellipse(cx - 17, 41, cx - 11, 47, t["skin"])
    c.box(cx - 14, 38, cx + 2, 42, t["gun"])
    c.box(cx - 14, 38, cx + 2, 39, t["gun_hi"])
    c.box(cx - 14, 41.5, cx + 2, 42, darken(t["gun"], 0.55))

    # chin on his chest, cap over his eyes
    hx, hy = cx - 3, 17
    c.ellipse(hx - 7, hy - 7, hx + 7, hy + 7, t["skin"])
    c.ellipse(hx, hy - 4, hx + 7, hy + 7, t["skin_lo"])
    c.box(hx - 8, hy - 8, hx + 7, hy - 3, t["hat"])
    c.box(hx - 9, hy - 4, hx + 8, hy - 1, t["hat_hi"])
    if t["visor"]:
        c.box(hx - 7, hy - 1, hx + 6, hy + 2, darken(t["visor"], 0.8))
    else:
        c.box(hx - 5, hy + 1, hx - 2, hy + 2, (30, 27, 28))
        c.box(hx + 1, hy + 1, hx + 4, hy + 2, (30, 27, 28))

    c.outline()

    # and one small z, so there is no mistaking him at twenty tiles
    z = (214, 218, 226, 210)
    c.box(cx + 13, 7, cx + 21, 8, z)
    c.box(cx + 13, 13, cx + 21, 14, z)
    c.poly([(cx + 19, 9), (cx + 21, 9), (cx + 15, 13), (cx + 13, 13)], z)


def draw(tier, frame):
    t = TIERS[tier]

    if frame == "dead":
        c = Cell()
        down(c, t)

        return c.im

    if frame == "sleep":
        c = Cell()
        asleep(c, t)

        return c.im

    if frame == "pain":
        c = Cell()
        hurting(c, t)

        return c.im

    if frame in ("die1", "die2", "die3"):
        step = {"die1": 0.3, "die2": 0.65, "die3": 0.92}[frame]
        if tier == "con":
            step = 0.55

        return falling(Cell(), t, step).im

    c = Cell()
    standing(c, t, frame)

    return c.im


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/sprites"
    os.makedirs(out, exist_ok=True)
    n = 0
    for tier in ("g1", "g2", "g3"):
        for frame in FRAMES:
            draw(tier, frame).save("%s/%s.%s.png" % (out, tier, frame))
            n += 1

    for frame in CON_FRAMES:
        draw("con", frame).save("%s/con.%s.png" % (out, frame))
        n += 1

    print("%d files written to %s" % (n, out))
