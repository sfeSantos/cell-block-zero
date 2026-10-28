"""The pickups, the bodies and the explosions, one 64 by 64 file a sprite,
written into assets/sprites.

A cell stands for a square one tile wide and one tile tall and the bottom edge
of it is the floor, so a thing you can pick up sits on that edge and a body
lies along it. The world draws a pickup at about two thirds of a tile and a
body at a whole one, which is why the pickups here are bold and short on
detail: twenty tiles away they are a dozen pixels and all that survives is the
silhouette and the colour. Same flat colours and dark outline as the guards
and the dogs, so the set reads as one.

The blood and the explosions are the exception. They are glows, so they get a
radial falloff and no outline at all, and three of them are drawn so small in
the world that colour is the only thing left of them.

    python3 tools/props.py assets/sprites
"""

import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw

CELL = 64
FLOOR = 60
EDGE = (16, 15, 18, 255)

STEEL = (84, 86, 94)
STEEL_HI = (138, 141, 150)
STEEL_LO = (52, 53, 59)
IRON = (70, 72, 78)
BLACK = (34, 34, 38)
BLACK_HI = (62, 62, 68)
BLACK_LO = (20, 20, 23)
BRASS = (184, 148, 56)
BRASS_HI = (226, 196, 104)
BRASS_LO = (132, 104, 38)
COPPER = (168, 102, 56)
OLIVE = (82, 90, 56)
OLIVE_HI = (116, 126, 78)
OLIVE_LO = (56, 62, 38)
WARHEAD = (158, 54, 42)
WARHEAD_HI = (196, 86, 68)
CANVAS = (88, 92, 74)
CANVAS_HI = (122, 126, 102)
CANVAS_LO = (60, 63, 50)
WHITE = (222, 222, 216)
WHITE_LO = (176, 176, 170)
RED = (176, 32, 32)
RED_HI = (214, 60, 56)
WOOD = (96, 64, 40)
WOOD_HI = (132, 92, 58)
WOOD_LO = (66, 44, 28)
TAPE = (52, 48, 42)
BONE = (206, 200, 182)
BONE_LO = (156, 150, 134)
BONE_SHADE = (116, 110, 96)
ROPE = (140, 118, 80)
ROPE_HI = (172, 148, 106)
GORE = (96, 18, 20)
GORE_HI = (138, 28, 28)
CON_SKIN = (179, 143, 117)
CON_SKIN_LO = (142, 110, 88)
CON_CLOTH = (143, 140, 133)
CON_CLOTH_LO = (110, 108, 103)
CON_STRIPE = (94, 93, 90)
CON_TROUSER = (102, 102, 107)
CON_HAIR = (62, 50, 42)

# The sergeant, so the man on your cell floor is the same man you meet walking
# about. These are the g2 colours out of tools/guards.py.
G2 = dict(
    skin=(189, 143, 107), skin_lo=(152, 111, 80),
    cloth=(87, 89, 59), cloth_lo=(62, 64, 41), cloth_hi=(116, 118, 80),
    trouser=(66, 66, 48), trouser_lo=(46, 46, 33),
    boot=(36, 33, 28), hat=(77, 79, 56), hat_hi=(104, 106, 76),
    vest=(56, 59, 43),
)


def lighten(c, f=1.3):
    return tuple(min(255, int(v * f)) for v in c[:3])


def darken(c, f=0.68):
    return tuple(int(v * f) for v in c[:3])


def sample(stops, t):
    """The colour at t along a list of (position, rgba) stops."""
    for i in range(1, len(stops)):
        t1, c1 = stops[i]
        if t <= t1 or i == len(stops) - 1:
            t0, c0 = stops[i - 1]
            k = 0.0 if t1 <= t0 else max(0.0, min(1.0, (t - t0) / (t1 - t0)))

            return tuple(int(c0[j] + (c1[j] - c0[j]) * k) for j in range(4))

    return stops[-1][1]


def gradient(cx, cy, rx, ry, stops):
    """An elliptical falloff on its own layer. Pillow has no primitive for it
    and it is what every glow in here is made of."""
    layer = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    px = layer.load()
    x0, x1 = max(0, int(cx - rx) - 1), min(CELL - 1, int(cx + rx) + 1)
    y0, y1 = max(0, int(cy - ry) - 1), min(CELL - 1, int(cy + ry) + 1)

    for y in range(y0, y1 + 1):
        dy = (y + 0.5 - cy) / max(0.5, ry)
        for x in range(x0, x1 + 1):
            dx = (x + 0.5 - cx) / max(0.5, rx)
            t = math.sqrt(dx * dx + dy * dy)
            if t <= 1:
                px[x, y] = sample(stops, t)

    return layer


class Cell:

    def __init__(self):
        self.im = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im, "RGBA")

    def box(self, x0, y0, x1, y1, c):
        self.d.rectangle([x0, y0, x1, y1], fill=c)

    def poly(self, pts, c):
        self.d.polygon(pts, fill=c)

    def disc(self, cx, cy, r, c):
        self.d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c)

    def oval(self, cx, cy, rx, ry, c):
        self.d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=c)

    def ring(self, cx, cy, rx, ry, c, w=1):
        self.d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], outline=c, width=w)

    def line(self, x0, y0, x1, y1, c, w=1):
        self.d.line([x0, y0, x1, y1], fill=c, width=w)

    def plate(self, x0, y0, x1, y1, c, hi=None, lo=None):
        """A flat slab with the light coming from above."""
        self.box(x0, y0, x1, y1, c)
        self.box(x0, y0, x1, y0, hi or lighten(c))
        self.box(x0, y1, x1, y1, lo or darken(c))

    def tube(self, x0, y0, x1, y1, c, hi=None, lo=None):
        """A cylinder lying on its side: one bright line along the top and a
        dark one along the bottom is enough to turn a box into a pipe."""
        self.box(x0, y0, x1, y1, c)
        self.box(x0, y0 + 1, x1, y0 + 1, hi or lighten(c, 1.5))
        self.box(x0, y1 - 1, x1, y1, lo or darken(c, 0.7))

    def grad(self, cx, cy, rx, ry, stops):
        self.im = Image.alpha_composite(self.im, gradient(cx, cy, rx, ry, stops))
        self.d = ImageDraw.Draw(self.im, "RGBA")

    def punch(self, cx, cy, rx, ry):
        """Take a bite out of what is already drawn, which is how the keys get
        the hole through the bow."""
        mask = Image.new("L", (CELL, CELL), 255)
        ImageDraw.Draw(mask).ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=0)
        self.im.putalpha(ImageChops.multiply(self.im.split()[3], mask))

    def outline(self, c=EDGE):
        """One dark pixel around everything solid, so the shape still reads
        against a dark corridor."""
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
            self.im.putpixel((x, y), c)


def pool(cell, cx, cy, rx, ry, a=160):
    """Blood on the floor. This never gets the outline: a dark line round a
    puddle reads as a rug."""
    cell.grad(cx, cy, rx, ry, [
        (0.0, GORE + (a,)),
        (0.55, GORE + (int(a * 0.86),)),
        (0.86, (70, 12, 14, int(a * 0.45))),
        (1.0, (70, 12, 14, 0)),
    ])


def grounded(body, rx=14, ry=4, cy=FLOOR + 1, a=90):
    """A sprite over its own shadow. The shadow goes down after the outline
    rather than before, so the dark line round the sprite is not eaten by it."""
    base = Cell()
    base.grad(32, cy, rx, ry, [(0.0, (0, 0, 0, a)), (0.6, (0, 0, 0, int(a * 0.55))),
                               (1.0, (0, 0, 0, 0))])

    return Image.alpha_composite(base.im, body.im)


# ----------------------------------------------------------------- the pickups
#
# Twenty things you can walk over and take. Every one of them stands on the
# bottom edge of the cell with a shadow under it, because a pickup floating a
# few pixels off the floor is the one thing that gives the billboard away.


def item_uzi():
    c = Cell()
    # the wire stock folded along the top, which is how they carry them
    c.plate(12, 36, 25, 40, BLACK_HI, (88, 88, 94), BLACK)
    c.plate(16, 40, 44, 50, BLACK, BLACK_HI, BLACK_LO)
    c.box(19, 43, 41, 44, BLACK_LO)
    c.tube(44, 43, 57, 47, STEEL_LO, STEEL_HI)
    c.box(50, 39, 53, 43, BLACK)
    c.box(56, 44, 57, 46, (10, 10, 12))
    c.plate(25, 50, 33, 60, STEEL_LO, STEEL, (40, 41, 45))
    c.box(26, 53, 32, 54, BRASS_LO)
    c.poly([(35, 50), (42, 50), (40, 59), (35, 59)], BLACK_HI)
    c.box(33, 49, 36, 52, BLACK_LO)
    c.outline()

    return grounded(c, rx=19)


def item_launcher():
    c = Cell()
    c.tube(10, 34, 48, 48, OLIVE, OLIVE_HI, OLIVE_LO)
    c.oval(11, 41, 3, 7, (26, 28, 22))
    c.poly([(48, 34), (48, 48), (60, 41)], WARHEAD)
    c.poly([(48, 34), (48, 41), (60, 41)], WARHEAD_HI)
    c.plate(20, 29, 32, 34, OLIVE_LO, OLIVE)
    c.box(24, 25, 27, 30, IRON)
    c.box(24, 25, 24, 30, STEEL_HI)
    c.plate(13, 29, 20, 34, (62, 52, 40), (92, 78, 60))
    c.poly([(26, 48), (34, 48), (32, 60), (27, 60)], OLIVE_LO)
    c.box(27, 51, 31, 52, (40, 44, 30))
    c.outline()

    return grounded(c, rx=22)


def pineapple(c, cx, cy, r, front):
    body = OLIVE if front else OLIVE_LO
    c.disc(cx, cy, r, body)
    c.oval(cx - r // 3, cy - r // 2, r // 2, max(2, r // 3), lighten(body, 1.45))
    for i in (-1, 0, 1):
        c.box(cx - r + 2, cy + i * 4, cx + r - 2, cy + i * 4, darken(body, 0.72))

    c.box(cx - 2, cy - r - 1, cx + 2, cy - r + 2, IRON)
    c.box(cx - 2, cy - r - 1, cx + 2, cy - r - 1, STEEL_HI)
    c.ring(cx + 5, cy - r - 2, 3, 3, STEEL_HI)


def item_grenades():
    c = Cell()
    pineapple(c, 41, 51, 7, False)
    pineapple(c, 25, 52, 8, True)
    c.outline()

    return grounded(c, rx=18)


def stun(c, x, top, front):
    body = STEEL if front else STEEL_LO
    c.plate(x, top, x + 11, 60, body, STEEL_HI, (38, 39, 43))
    c.box(x, top + 7, x + 11, top + 12, WHITE)
    c.box(x, top + 7, x + 11, top + 7, (244, 244, 238))
    c.box(x, top + 14, x + 11, top + 15, (198, 166, 44))
    c.box(x + 3, top - 4, x + 8, top, IRON)
    c.box(x + 3, top - 4, x + 8, top - 4, STEEL_HI)


def item_flashes():
    c = Cell()
    stun(c, 36, 36, False)
    stun(c, 20, 40, True)
    c.outline()

    return grounded(c, rx=17)


def standing_round(c, x, base, h):
    c.box(x, base - h, x + 3, base, BRASS)
    c.box(x, base - h, x, base, BRASS_HI)
    c.poly([(x, base - h), (x + 3, base - h), (x + 1, base - h - 4)], COPPER)


def lying_round(c, x, y, w):
    c.box(x, y, x + w, y + 3, BRASS)
    c.box(x, y, x + w, y, BRASS_HI)
    c.poly([(x + w, y), (x + w + 4, y + 1), (x + w, y + 3)], COPPER)


def item_bullets():
    c = Cell()
    # a stripper clip holding five, and two that came loose in somebody's pocket
    for i in range(5):
        standing_round(c, 19 + i * 5, 52, 14)

    c.plate(17, 46, 43, 51, STEEL_LO, STEEL_HI, (38, 39, 43))
    lying_round(c, 12, 55, 11)
    lying_round(c, 33, 57, 12)
    c.outline()

    return grounded(c, rx=19, ry=3)


def item_clips():
    c = Cell()
    # a pair of uzi magazines taped together, so they do not read as loose
    # revolver rounds lying on the floor
    for x, body in ((18, STEEL_LO), (32, STEEL)):
        c.plate(x, 34, x + 12, 60, body, STEEL_HI, (38, 39, 43))
        c.box(x + 3, 38, x + 4, 57, darken(body, 0.72))
        c.box(x + 9, 38, x + 10, 57, darken(body, 0.72))
        c.plate(x + 3, 30, x + 9, 35, BRASS, BRASS_HI, BRASS_LO)

    c.plate(16, 40, 46, 45, TAPE, (74, 70, 62), (34, 32, 28))
    c.plate(16, 51, 46, 56, TAPE, (74, 70, 62), (34, 32, 28))
    c.outline()

    return grounded(c, rx=18)


def item_ammobox():
    c = Cell()
    c.plate(14, 36, 52, 60, CANVAS, CANVAS_HI, CANVAS_LO)
    c.plate(14, 36, 52, 42, CANVAS_HI, lighten(CANVAS_HI, 1.18), CANVAS)
    c.box(14, 47, 52, 48, CANVAS_LO)

    for x in (14, 48):
        c.plate(x, 36, x + 4, 60, IRON, STEEL_HI, BLACK_LO)

    c.plate(24, 51, 42, 57, OLIVE_LO, OLIVE)
    c.box(27, 53, 39, 54, CANVAS_HI)
    c.box(27, 55, 35, 56, CANVAS_HI)
    c.plate(26, 30, 40, 36, IRON, STEEL_HI)
    c.punch(33, 31, 5, 2)
    lying_round(c, 1, 56, 8)
    c.outline()

    return grounded(c, rx=23)


def rocket(c, cx, top, front):
    body = OLIVE if front else OLIVE_LO
    c.poly([(cx - 4, top + 7), (cx + 4, top + 7), (cx, top)], WARHEAD)
    c.poly([(cx - 4, top + 7), (cx, top + 7), (cx, top)], WARHEAD_HI)
    c.plate(cx - 4, top + 7, cx + 4, top + 28, body, lighten(body, 1.4),
            darken(body))
    c.box(cx - 2, top + 11, cx - 1, top + 26, lighten(body, 1.3))
    c.box(cx - 4, top + 16, cx + 4, top + 17, darken(body, 0.62))
    c.poly([(cx - 8, top + 28), (cx - 4, top + 28), (cx - 4, top + 21)], IRON)
    c.poly([(cx + 8, top + 28), (cx + 4, top + 28), (cx + 4, top + 21)], STEEL_LO)
    c.box(cx - 2, top + 26, cx + 2, top + 28, STEEL_LO)


def item_rockets():
    c = Cell()
    rocket(c, 42, 28, False)
    rocket(c, 24, 32, True)
    c.outline()

    return grounded(c, rx=19)


# Shoulder straps and a gap for the neck, because on the floor a plain slab
# reads as a crate and this has to read as something you put on.
def vest_shape(body, plate_c, mark=None):
    c = Cell()
    hi, lo = lighten(body, 1.32), darken(body, 0.7)

    for x0, x1, col in ((19, 26, body), (38, 45, lo)):
        c.plate(x0, 21, x1, 34, col, hi)
        c.box(x0, 26, x1, 28, TAPE)

    c.poly([(17, 31), (47, 31), (49, 45), (45, 60), (19, 60), (15, 45)], body)
    c.poly([(32, 31), (47, 31), (49, 45), (45, 60), (32, 60)], lo)
    c.box(17, 31, 31, 32, hi)
    c.box(31, 32, 33, 60, darken(body, 0.5))
    c.plate(19, 36, 45, 44, plate_c, lighten(plate_c, 1.5), darken(plate_c, 0.6))
    c.plate(19, 47, 45, 55, plate_c, lighten(plate_c, 1.5), darken(plate_c, 0.6))

    if mark:
        c.plate(28, 48, 36, 54, mark)

    c.outline()

    return grounded(c, rx=20)


def item_vest():
    return vest_shape(CANVAS, (66, 69, 55))


def item_vestheavy():
    return vest_shape((52, 55, 64), (34, 36, 42), (190, 168, 44))


def item_medkit():
    c = Cell()
    c.plate(13, 34, 51, 60, WHITE, (242, 242, 236), WHITE_LO)
    c.box(13, 41, 51, 42, WHITE_LO)
    c.box(28, 44, 36, 58, RED)
    c.box(19, 48, 45, 54, RED)
    c.box(28, 44, 36, 44, RED_HI)
    c.box(19, 48, 27, 48, RED_HI)
    c.box(37, 48, 45, 48, RED_HI)
    c.plate(29, 38, 35, 42, STEEL_LO, STEEL_HI)
    c.plate(25, 28, 39, 34, WHITE_LO, WHITE)
    c.punch(32, 29, 5, 2)
    c.outline()

    return grounded(c, rx=21)


def item_snack():
    c = Cell()
    c.plate(10, 50, 54, 60, STEEL_LO, STEEL_HI, (36, 37, 41))
    c.box(10, 53, 54, 54, STEEL)
    c.oval(23, 47, 10, 7, (168, 124, 70))
    c.oval(21, 44, 6, 3, (206, 164, 104))
    c.box(18, 47, 28, 48, (128, 90, 50))
    c.disc(42, 46, 7, (150, 52, 44))
    c.oval(39, 43, 3, 2, (198, 86, 74))
    c.box(42, 37, 43, 40, (74, 58, 38))
    c.outline()

    return grounded(c, rx=22, ry=3)


def item_silencer():
    c = Cell()
    c.tube(14, 44, 46, 56, BLACK, BLACK_HI, BLACK_LO)
    for x in range(18, 44, 5):
        c.box(x, 45, x + 1, 55, (22, 22, 25))

    c.plate(46, 46, 53, 54, STEEL_LO, STEEL_HI, (34, 35, 39))
    c.oval(15, 50, 2, 5, (10, 10, 12))
    c.outline()

    return grounded(c, rx=20, ry=3)


# The three keys are a colour first and a shape second: telling red from
# yellow across a room is the whole job.
def key_shape(col):
    c = Cell()
    hi, lo = lighten(col, 1.5), darken(col, 0.66)
    c.disc(22, 45, 11, col)
    c.oval(20, 40, 7, 4, hi)
    c.punch(22, 45, 5, 5)
    c.plate(31, 43, 53, 49, col, hi, lo)

    for x in (39, 47):
        c.box(x, 49, x + 3, 57, col)
        c.box(x, 49, x, 57, hi)
        c.box(x + 3, 49, x + 3, 57, lo)

    c.outline()

    return grounded(c, rx=17, ry=3)


def item_redkey():
    return key_shape((198, 48, 42))


def item_bluekey():
    return key_shape((58, 104, 196))


def item_yellowkey():
    return key_shape((206, 176, 44))


def item_knife():
    c = Cell()
    c.plate(8, 46, 27, 55, (62, 48, 36), (96, 76, 56), (40, 32, 24))
    for x in range(11, 26, 5):
        c.box(x, 46, x + 1, 55, (40, 32, 24))

    c.plate(27, 44, 30, 57, STEEL_LO, STEEL_HI, (34, 35, 39))
    c.poly([(30, 46), (54, 50), (30, 55)], STEEL)
    c.poly([(30, 46), (54, 50), (32, 51)], (188, 192, 200))
    c.outline()

    return grounded(c, rx=21, ry=3)


# A leg trap: folded shut it is a thing you carry, open it is a thing you hope
# somebody walks into, and sprung it has already had somebody.
def trap_shape(kind):
    c = Cell()

    if kind == "set":
        c.oval(32, 50, 17, 10, IRON)
        c.oval(32, 50, 12, 6, BLACK_LO)
        for i in range(10):
            a = i / 10.0 * math.pi * 2
            x = 32 + math.cos(a) * 14
            y = 50 + math.sin(a) * 8
            c.poly([(x - 2, y + 1), (x + 2, y + 1), (x, y - 7)], STEEL)
            c.poly([(x - 2, y + 1), (x, y + 1), (x, y - 7)], STEEL_HI)

        c.plate(27, 46, 37, 53, STEEL_HI, (178, 180, 188), STEEL)
    elif kind == "sprung":
        c.plate(16, 44, 48, 54, IRON, STEEL_HI, BLACK_LO)
        for i in range(6):
            x = 18 + i * 5
            c.poly([(x, 44), (x + 3, 44), (x + 1, 38)], STEEL)
            c.poly([(x + 2, 54), (x + 5, 54), (x + 3, 60)], STEEL_LO)
    else:
        c.plate(16, 42, 48, 56, STEEL, STEEL_HI, STEEL_LO)
        c.plate(24, 37, 40, 42, IRON, STEEL_HI)
        for x in range(19, 46, 5):
            c.box(x, 45, x + 2, 53, STEEL_LO)

    # the chain and the stake, the reason it is still there afterwards
    c.plate(2, 55, 16, 58, IRON, STEEL_HI, BLACK_LO)
    for x in range(3, 15, 4):
        c.box(x, 55, x + 1, 58, BLACK_LO)

    c.outline()
    im = grounded(c, rx=21, ry=4)

    if kind == "sprung":
        blood = Cell()
        pool(blood, 27, 50, 10, 6, 150)
        pool(blood, 41, 53, 7, 4, 120)
        im = Image.alpha_composite(im, blood.im)

    return im


def item_trap():
    return trap_shape("folded")


def item_trapset():
    return trap_shape("set")


def item_trapsprung():
    return trap_shape("sprung")


ITEMS = ("uzi", "launcher", "grenades", "flashes", "bullets", "clips",
         "ammobox", "rockets", "vest", "vestheavy", "medkit", "snack",
         "silencer", "redkey", "bluekey", "yellowkey", "knife", "trap",
         "trapset", "trapsprung")


# ------------------------------------------------------------------ the props
#
# What is left in the old cells, drawn at a whole tile. These have a pool of
# blood instead of a shadow, which is laid down first and never outlined.


def prop_skeleton():
    c = Cell()
    # the shackles, still bolted into the wall above him
    for wx in (23, 41):
        c.plate(wx - 1, 0, wx + 1, 13, IRON, STEEL_HI, BLACK_LO)
        c.plate(wx - 5, 12, wx + 5, 18, IRON, STEEL_HI, BLACK_LO)
        c.punch(wx, 15, 3, 2)

    # the arms hanging from them
    c.poly([(22, 16), (26, 16), (29, 38), (25, 39)], BONE)
    c.poly([(42, 16), (38, 16), (35, 38), (39, 39)], BONE_LO)
    c.disc(27, 39, 3, BONE_LO)
    c.disc(37, 39, 3, BONE_SHADE)

    # ribs over the spine, slumped forward onto the pelvis
    c.box(30, 37, 34, 55, BONE_SHADE)
    for i in range(5):
        y = 39 + i * 3
        c.box(25, y, 39, y, BONE)
        c.box(25, y + 1, 39, y + 1, BONE_LO)

    c.poly([(26, 53), (38, 53), (40, 59), (24, 59)], BONE)
    c.box(26, 57, 38, 59, BONE_LO)

    # and the legs folded out along the floor
    c.poly([(27, 55), (31, 58), (14, 61), (13, 57)], BONE)
    c.poly([(37, 55), (33, 58), (50, 61), (51, 57)], BONE_LO)
    c.disc(13, 59, 3, BONE_SHADE)
    c.disc(51, 59, 3, BONE_SHADE)

    # the skull, chin on the chest
    c.disc(32, 31, 8, BONE)
    c.oval(29, 28, 4, 3, (232, 228, 214))
    c.box(27, 34, 37, 38, BONE_LO)
    c.box(27, 29, 31, 33, (18, 16, 16))
    c.box(34, 29, 38, 33, (18, 16, 16))
    c.box(31, 34, 33, 36, (24, 22, 22))
    for x in range(28, 37, 3):
        c.box(x, 36, x + 1, 38, (30, 28, 28))

    c.outline()

    under = Cell()
    pool(under, 32, 58, 15, 6, 95)

    return Image.alpha_composite(under.im, c.im)


def prop_hanged():
    rope = Cell()
    rope.plate(31, 0, 33, 12, ROPE, ROPE_HI, darken(ROPE))
    rope.plate(28, 11, 36, 15, darken(ROPE, 0.85), ROPE)
    rope.outline()

    c = Cell()
    c.disc(32, 24, 7, CON_SKIN)
    c.oval(29, 21, 4, 3, lighten(CON_SKIN, 1.12))
    c.box(26, 16, 38, 19, CON_HAIR)
    c.box(28, 22, 30, 24, (26, 22, 22))
    c.box(34, 22, 36, 24, (26, 22, 22))
    c.box(29, 28, 35, 30, darken(CON_SKIN, 0.8))
    c.plate(27, 29, 37, 32, ROPE, ROPE_HI)

    c.poly([(23, 32), (41, 32), (38, 48), (26, 48)], CON_CLOTH)
    c.poly([(32, 32), (41, 32), (38, 48), (32, 48)], CON_CLOTH_LO)
    for i in range(3):
        c.box(24, 34 + i * 4, 40, 35 + i * 4, CON_STRIPE)

    c.plate(19, 32, 23, 47, CON_CLOTH)
    c.plate(41, 32, 45, 47, CON_CLOTH_LO)
    c.disc(21, 48, 3, CON_SKIN)
    c.disc(43, 48, 3, CON_SKIN_LO)
    c.plate(26, 47, 31, 58, CON_TROUSER)
    c.plate(33, 47, 38, 58, darken(CON_TROUSER, 0.85))
    c.disc(28, 59, 3, CON_SKIN)
    c.disc(35, 59, 3, CON_SKIN_LO)
    c.outline()

    # hanging off true, turning on the rope
    c.im = c.im.rotate(-7, resample=Image.NEAREST, center=(32, 14))

    # the stool he kicked over
    stool = Cell()
    stool.plate(8, 54, 22, 58, WOOD, WOOD_HI, WOOD_LO)
    stool.plate(9, 58, 12, 62, WOOD_LO)
    stool.plate(18, 58, 21, 62, WOOD_LO)
    stool.outline()

    out = Image.alpha_composite(rope.im, c.im)

    return Image.alpha_composite(out, stool.im)


def prop_body():
    under = Cell()
    pool(under, 30, 55, 20, 8, 170)
    pool(under, 46, 58, 9, 4, 120)

    c = Cell()
    # face down, head to the left, one arm thrown out in front of him
    c.poly([(20, 44), (44, 42), (46, 56), (22, 58)], CON_CLOTH)
    c.poly([(20, 52), (46, 50), (46, 56), (22, 58)], CON_CLOTH_LO)
    for i in range(3):
        c.box(22, 45 + i * 4, 44, 46 + i * 4, CON_STRIPE)

    c.plate(43, 48, 57, 56, CON_TROUSER, lighten(CON_TROUSER, 1.2),
            darken(CON_TROUSER))
    c.plate(55, 49, 61, 55, (32, 30, 28), (56, 52, 48))
    c.disc(16, 49, 7, CON_SKIN)
    c.oval(14, 46, 4, 3, lighten(CON_SKIN, 1.1))
    c.box(11, 43, 21, 46, CON_HAIR)
    c.poly([(26, 40), (34, 37), (37, 41), (29, 44)], CON_CLOTH)
    c.disc(37, 39, 3, CON_SKIN_LO)
    c.outline()

    return Image.alpha_composite(under.im, c.im)


def prop_remains():
    under = Cell()
    pool(under, 32, 55, 22, 9, 180)
    pool(under, 14, 58, 9, 4, 130)
    pool(under, 50, 57, 10, 5, 130)

    c = Cell()
    # an arm, a leg and a piece of ribcage, which is what the squad left
    c.plate(9, 48, 24, 54, CON_SKIN, lighten(CON_SKIN, 1.1), CON_SKIN_LO)
    c.box(22, 48, 25, 54, (112, 22, 24))
    c.disc(9, 51, 3, CON_SKIN)
    c.plate(40, 50, 54, 57, CON_TROUSER, lighten(CON_TROUSER, 1.2),
            darken(CON_TROUSER))
    c.plate(52, 51, 59, 57, (32, 30, 28), (56, 52, 48))
    c.box(37, 50, 40, 57, (112, 22, 24))

    for i in range(3):
        y = 42 + i * 3
        c.box(27, y, 38, y, BONE)
        c.box(27, y + 1, 38, y + 1, BONE_LO)

    c.box(31, 41, 34, 50, BONE_SHADE)
    c.outline()

    out = Image.alpha_composite(under.im, c.im)

    spots = Cell()
    pool(spots, 27, 56, 5, 3, 160)
    pool(spots, 38, 58, 4, 2, 140)

    return Image.alpha_composite(out, spots.im)


def prop_deadguard():
    under = Cell()
    pool(under, 30, 56, 17, 7, 170)
    pool(under, 44, 58, 8, 4, 120)

    t = G2
    c = Cell()
    # on his back, the way you find him when you come to on the cell floor
    c.poly([(22, 42), (46, 40), (48, 56), (24, 58)], t["cloth"])
    c.poly([(22, 51), (48, 49), (48, 56), (24, 58)], t["cloth_lo"])
    c.plate(26, 43, 42, 52, t["vest"], lighten(t["vest"], 1.3),
            darken(t["vest"]))
    c.plate(44, 46, 58, 55, t["trouser"], lighten(t["trouser"], 1.25),
            t["trouser_lo"])
    c.plate(55, 47, 61, 54, t["boot"], (62, 58, 52))
    c.disc(17, 47, 7, t["skin"])
    c.oval(15, 44, 4, 3, lighten(t["skin"], 1.1))
    c.plate(10, 40, 24, 44, t["hat"], t["hat_hi"])
    c.poly([(28, 38), (36, 35), (39, 39), (31, 42)], t["cloth"])
    c.disc(39, 37, 3, t["skin_lo"])

    # the revolver that fell out of his hand, which is where yours comes from
    c.plate(44, 33, 58, 38, (46, 46, 51), (86, 87, 94), (28, 28, 32))
    c.box(50, 38, 54, 42, (46, 46, 51))
    c.outline()

    return Image.alpha_composite(under.im, c.im)


def prop_stain():
    # Dried blood with nobody left beside it. It cannot live in the floor
    # texture: one file is painted on every tile of its kind, so a stain in
    # there would run the length of the corridor.
    c = Cell()
    pool(c, 30, 52, 18, 10, 120)
    pool(c, 42, 56, 11, 6, 100)
    pool(c, 20, 57, 9, 5, 100)
    pool(c, 31, 53, 11, 6, 150)
    pool(c, 39, 58, 6, 3, 140)
    pool(c, 24, 59, 5, 3, 140)

    # the spots that flew out of it and dried on their own
    for x, y, r in ((9, 50, 3), (53, 52, 3), (46, 46, 2), (14, 60, 3),
                    (57, 59, 2), (36, 44, 2)):
        pool(c, x, y, r, max(1, r - 1), 110)

    return c.im


# ---------------------------------------------------------------- the effects
#
# Two kinds here. The four things in flight are objects, so they are outlined
# like a pickup and sit in the middle of the cell instead of on the floor. The
# eight glows are a radial falloff and nothing else: no outline, because a dark
# line round a fireball is the one way to make it look like a sticker.


def fx_knife():
    c = Cell()
    c.plate(4, 28, 22, 36, (62, 48, 36), (96, 76, 56), (40, 32, 24))
    c.plate(22, 26, 25, 38, STEEL_LO, STEEL_HI, (34, 35, 39))
    c.poly([(25, 28), (56, 32), (25, 36)], STEEL)
    c.poly([(25, 28), (56, 32), (27, 33)], (196, 200, 208))
    c.outline()

    return c.im


def fx_rocket():
    c = Cell()
    c.plate(24, 27, 42, 37, OLIVE, OLIVE_HI, OLIVE_LO)
    c.poly([(42, 27), (42, 37), (54, 32)], WARHEAD)
    c.poly([(42, 27), (42, 32), (54, 32)], WARHEAD_HI)
    c.poly([(24, 27), (18, 23), (18, 41), (24, 37)], IRON)
    c.outline()

    flame = Cell()
    flame.grad(14, 32, 11, 6, [(0.0, (255, 240, 200, 235)),
                               (0.4, (255, 168, 56, 190)),
                               (1.0, (200, 70, 20, 0))])
    flame.grad(5, 32, 9, 5, [(0.0, (255, 150, 40, 150)), (1.0, (180, 60, 20, 0))])

    return Image.alpha_composite(flame.im, c.im)


def fx_grenade():
    c = Cell()
    pineapple(c, 32, 34, 9, True)
    c.outline()

    return c.im


def fx_flash():
    c = Cell()
    c.plate(25, 20, 39, 46, STEEL, STEEL_HI, (38, 39, 43))
    c.box(25, 28, 39, 33, WHITE)
    c.box(25, 28, 39, 28, (244, 244, 238))
    c.box(25, 35, 39, 36, (198, 166, 44))
    c.plate(28, 16, 36, 20, IRON, STEEL_HI)
    c.outline()

    return c.im


# Where the fire and the smoke sit, as angle, distance and size. The numbers
# are uneven on purpose: six lobes at even spacing and even size comes out as a
# flower, which is the one thing an explosion must not look like.
LOBES = ((0.00, 0.95, 1.12), (1.15, 0.72, 0.86), (2.05, 1.10, 1.24),
         (3.05, 0.86, 0.94), (4.20, 1.02, 1.16), (5.25, 0.76, 0.82))

PUFFS = ((0.35, 1.05, 1.00), (1.30, 0.84, 1.22), (2.20, 1.12, 0.88),
         (3.10, 0.92, 1.10), (3.95, 1.08, 0.94), (4.85, 0.80, 1.18),
         (5.70, 1.00, 1.05))


def fx_boom(step):
    """One of the four frames of a fireball: it grows, it cools, and the smoke
    it leaves behind takes the fire's place."""
    c = Cell()
    r = 14 + step * 16

    # the smoke goes down first, so the fire sits inside it
    for a, dist, size in PUFFS:
        a += step * 1.1
        c.grad(32 + math.cos(a) * r * 0.92 * dist,
               33 + math.sin(a) * r * 0.74 * dist,
               (7 + step * 5) * size, (7 + step * 5) * size,
               [(0.0, (58, 54, 52, int(70 + step * 110))),
                (0.55, (58, 54, 52, int(60 + step * 95))),
                (1.0, (58, 54, 52, 0))])

    # The fire stays solid all four frames and goes from orange to the colour
    # of what is left over. It is the world that fades the sprite out, in
    # fx:collect, so a frame that is already half transparent fades twice.
    def cool(hot, cold):
        return tuple(int(hot[i] + (cold[i] - hot[i]) * step) for i in range(3))

    c.grad(32, 33, r * 0.94, r * 0.8, [
        (0.0, cool((228, 108, 30), (104, 58, 42)) + (236,)),
        (0.72, cool((206, 88, 24), (88, 48, 36)) + (224,)),
        (1.0, (90, 44, 26, 0)),
    ])

    for a, dist, size in LOBES:
        a += step * 0.8
        c.grad(32 + math.cos(a) * r * 0.6 * dist,
               33 + math.sin(a) * r * 0.48 * dist,
               r * 0.46 * size, r * 0.42 * size,
               [(0.0, cool((244, 136, 40), (132, 74, 50)) + (240,)),
                (0.7, cool((226, 104, 30), (112, 62, 44)) + (232,)),
                (1.0, (120, 54, 26, 0))])

    # the core, which cools from white to the colour of the rest of it and
    # then stops being there at all
    hot = (255 - int(step * 20), 250 - int(step * 130), 222 - int(step * 180))
    c.grad(32, 33, r * (0.72 - step * 0.3), r * (0.64 - step * 0.28), [
        (0.0, hot + (int(235 - step * 215),)),
        (0.45, (255, 196, 80, int(220 - step * 200))),
        (1.0, (236, 120, 36, 0)),
    ])

    return c.im


def fx_pop():
    c = Cell()
    c.grad(32, 32, 31, 31, [(0.0, (255, 255, 252, 255)),
                            (0.45, (255, 255, 248, 240)),
                            (0.8, (236, 232, 200, 120)),
                            (1.0, (220, 214, 180, 0))])

    return c.im


def blob(mid, hi):
    """Blood, a spark and a puff of smoke. The world draws these at a tenth of
    a tile, so there is nothing to see but the colour and a soft edge."""
    c = Cell()
    c.grad(32, 32, 14, 14, [(0.0, mid), (0.55, mid), (1.0, mid[:3] + (0,))])
    c.grad(27, 28, 6, 6, [(0.0, hi), (1.0, hi[:3] + (0,))])

    return c.im


def fx_blood():
    return blob((120, 20, 22, 240), (178, 40, 36, 220))


def fx_spark():
    return blob((250, 206, 90, 240), (255, 250, 220, 255))


def fx_smoke():
    return blob((118, 116, 114, 150), (150, 148, 146, 120))


PROPS = ("skeleton", "hanged", "body", "remains", "deadguard", "stain")

FX = ("knife", "rocket", "grenade", "flash", "boom1", "boom2", "boom3",
      "boom4", "pop", "blood", "spark", "smoke")


def draw(name):
    """name is the cell the game asks for, such as item.uzi or fx.boom3."""
    group, _, what = name.partition(".")

    if group == "item":
        return globals()["item_" + what]()

    if group == "prop":
        return globals()["prop_" + what]()

    if what.startswith("boom"):
        return fx_boom((int(what[4:]) - 1) / 3.0)

    return globals()["fx_" + what]()


def names():
    return (["item." + n for n in ITEMS] + ["prop." + n for n in PROPS]
            + ["fx." + n for n in FX])


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/sprites"
    os.makedirs(out, exist_ok=True)

    for name in names():
        draw(name).save("%s/%s.png" % (out, name))

    print("%d files written to %s" % (len(names()), out))
