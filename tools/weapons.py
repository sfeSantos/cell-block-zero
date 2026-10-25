"""The weapon in your hands, 200 by 150 a frame, into assets/views.

The hands sit at the bottom of the cell and the barrel runs up the screen,
which is the same place the code drawn art puts them, so a file dropped in
here lines up with the rest of the view. Same look as the guards: flat
colours, two tone shading, a dark line around the silhouette.

    python3 tools/weapons.py assets/views
"""

import math
import os
import sys

from PIL import Image, ImageDraw

W, H = 200, 150

# Where the grip sits and how big the weapon is drawn, copied from the code
# so the two kinds of art can be mixed frame by frame.
OX, OY, SC = 112, 132, 0.78

SKIN = (199, 153, 117)
SKIN_LO = (158, 117, 87)
SKIN_HI = (223, 181, 144)
CUFF = (128, 133, 143)
CUFF_HI = (158, 163, 173)
GUN = (66, 69, 77)
GUN_HI = (107, 112, 122)
GUN_LO = (38, 38, 43)
WOOD = (82, 54, 33)
WOOD_HI = (117, 79, 47)
BLOOD = (148, 13, 15)

# Dried, not fresh. The guard who came into the cell is an hour behind you
# and it is still on your hands.
DRIED = (112, 26, 24, 205)
DRIED_LO = (78, 17, 16, 190)
EDGE = (16, 15, 18, 255)

FRAMES = {"hatchet": 2, "revolver": 4, "uzi": 4, "launcher": 2,
          "grenades": 2, "flashes": 2, "knife": 2,
          "throat": 4, "head": 4, "neck": 4}


class View:

    def __init__(self):
        self.im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im, "RGBA")
        self.ox, self.oy, self.s = OX, OY, SC
        self.rot = 0.0

    # ------------------------------------------------------------ transform
    def at(self, ox, oy, s=1.0, rot=0.0):
        self.ox, self.oy, self.s, self.rot = ox, oy, s, rot

        return self

    def screen(self):
        return self.at(0, 0, 1.0, 0.0)

    def grip(self, lift=0):
        return self.at(OX, OY + lift, SC, 0.0)

    def p(self, x, y):
        if self.rot:
            c, s = math.cos(self.rot), math.sin(self.rot)
            x, y = x * c - y * s, x * s + y * c

        return (self.ox + x * self.s, self.oy + y * self.s)

    # --------------------------------------------------------------- shapes
    def poly(self, pts, c):
        self.d.polygon([self.p(x, y) for x, y in pts], fill=c)

    def rect(self, x, y, w, h, c):
        self.poly(((x, y), (x + w, y), (x + w, y + h), (x, y + h)), c)

    def disc(self, x, y, r, c):
        cx, cy = self.p(x, y)
        rr = r * self.s
        self.d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=c)

    def tube(self, cx, yTop, wTop, yBot, wBot, c):
        self.poly(((cx - wTop * 0.5, yTop), (cx + wTop * 0.5, yTop),
                   (cx + wBot * 0.5, yBot), (cx - wBot * 0.5, yBot)), c)

    def outline(self):
        src = self.im.load()
        edge = []
        for y in range(H):
            for x in range(W):
                if src[x, y][3] != 0:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and src[nx, ny][3] > 128:
                        edge.append((x, y))
                        break
        for x, y in edge:
            self.im.putpixel((x, y), EDGE)


# ----------------------------------------------------------------- the hands
def fists(v, spread=0):
    cy = -8
    v.disc(-15 - spread, cy - 14, 13, SKIN)
    v.rect(-28 - spread, cy - 14, 26, 26, SKIN)
    v.disc(13 + spread, cy - 10, 12, SKIN_LO)
    v.rect(2 + spread, cy - 10, 24, 24, SKIN_LO)

    # knuckles on the near hand
    for i in range(4):
        v.rect(-13, cy - 32 + i * 9, 26, 6, SKIN)
        v.rect(-13, cy - 27 + i * 9, 26, 2, SKIN_LO)
    v.rect(-28 - spread, cy - 14, 5, 26, SKIN_HI)

    v.rect(-32 - spread, cy + 10, 64 + spread * 2, 14, CUFF)
    v.rect(-32 - spread, cy + 10, 64 + spread * 2, 3, CUFF_HI)

    # what is left of the guard, across the knuckles and down one cuff
    v.rect(-13, cy - 33, 11, 4, DRIED)
    v.rect(-4, cy - 29, 5, 2, DRIED_LO)
    v.rect(2, cy - 24, 8, 3, DRIED)
    v.rect(-11, cy - 15, 6, 2, DRIED_LO)
    v.rect(-26 - spread, cy - 6, 5, 7, DRIED)
    v.rect(-24 - spread, cy + 2, 3, 4, DRIED_LO)
    v.rect(16 + spread, cy - 2, 4, 5, DRIED_LO)
    v.rect(-20 - spread, cy + 11, 7, 3, DRIED_LO)


def flash(v, x, y, s=1.0, quiet=False):
    if quiet:
        v.disc(x, y, 7 * s, (255, 234, 158, 115))
        v.disc(x, y - 6 * s, 11 * s, (148, 145, 138, 72))

        return

    v.poly(((x - 20 * s, y + 4 * s), (x, y - 30 * s), (x + 20 * s, y + 4 * s),
            (x, y + 14 * s)), (255, 206, 94, 205))
    v.disc(x, y - 7 * s, 15 * s, (255, 178, 52, 165))
    v.disc(x, y, 11 * s, (255, 242, 182, 245))


# --------------------------------------------------------------- the weapons
def hatchet_body(v, x, y, rot, s=1.0):
    v.at(x, y, s, rot)
    v.rect(-7, -96, 14, 98, WOOD)
    v.rect(-7, -96, 4, 98, WOOD_HI)
    v.rect(2, -96, 5, 98, (56, 36, 22))
    v.poly(((-8, -96), (24, -106), (32, -82), (-8, -74)), (140, 144, 152))
    v.poly(((22, -104), (32, -82), (27, -79), (17, -100)), (226, 230, 238))
    v.poly(((-8, -82), (14, -88), (18, -79), (-8, -74)), (96, 99, 106))
    v.rect(-10, -26, 20, 18, (46, 46, 50))
    v.rect(-10, -26, 20, 3, (76, 76, 82))


def w_hatchet(v, frame):
    fire = frame == 2
    lift = -4 if fire else 0
    v.grip(lift)
    hx, hr = (-30, 0.95) if fire else (14, 0.3)
    px, py = v.p(hx, 0)
    hatchet_body(v, px, py, hr, SC)
    v.grip(lift)
    fists(v, 2)


def w_revolver(v, frame):
    fire = frame in (2, 4)
    sil = frame >= 3
    v.grip(-5 if fire else 0)

    v.poly(((-15, -2), (15, -2), (11, -42), (-9, -42)), WOOD)
    v.poly(((-15, -2), (-7, -2), (-5, -42), (-9, -42)), WOOD_HI)
    v.rect(-17, -60, 34, 20, GUN)
    v.rect(-17, -60, 34, 3, GUN_HI)
    v.rect(-17, -43, 34, 3, GUN_LO)
    v.disc(-3, -43, 8, GUN_LO)
    v.rect(-14, -80, 28, 22, (79, 82, 90))
    v.rect(-14, -80, 28, 2, GUN_HI)
    v.disc(0, -69, 9, (56, 56, 64))
    v.disc(0, -69, 3, (18, 18, 20))
    v.tube(0, -122, 14, -78, 20, GUN)
    v.tube(-5, -120, 3, -78, 4, GUN_HI)
    v.tube(6, -120, 3, -78, 4, GUN_LO)
    v.rect(-4, -126, 8, 6, GUN_LO)

    if sil:
        v.tube(0, -132, 22, -86, 28, (38, 40, 46))
        v.tube(-7, -130, 4, -86, 5, (66, 69, 77))
        for i in range(4):
            v.rect(-11, -124 + i * 10, 22, 3, (23, 23, 28))

    fists(v, 0)
    v.outline()

    if fire:
        flash(v, 0, -134 if sil else -126, 1.0, sil)


def w_uzi(v, frame):
    fire = frame in (2, 4)
    sil = frame >= 3
    v.grip(-4 if fire else 0)

    v.poly(((-24, -4), (-6, -8), (-2, -46), (-20, -42)), (48, 48, 54))
    v.rect(-18, -74, 36, 30, (59, 59, 66))
    v.rect(-18, -74, 36, 3, GUN_HI)
    v.rect(-18, -56, 36, 2, GUN_LO)
    v.rect(-18, -74, 4, 30, (82, 84, 92))
    v.rect(14, -70, 8, 10, (43, 43, 48))
    v.disc(-2, -50, 7, GUN_LO)
    v.tube(0, -116, 13, -72, 18, GUN)
    v.tube(-4, -114, 3, -72, 4, GUN_HI)
    v.rect(-5, -120, 10, 5, GUN_LO)

    if sil:
        v.tube(0, -130, 22, -80, 26, (38, 40, 46))
        for i in range(4):
            v.rect(-11, -122 + i * 11, 22, 3, (23, 23, 28))

    fists(v, 4)
    v.outline()

    if fire:
        flash(v, 0, -132 if sil else -122, 0.9, sil)
        if not sil:
            v.grip(-4)
            v.disc(22, -106, 7, (143, 143, 148, 77))


def w_launcher(v, frame):
    fire = frame == 2
    v.grip(-6 if fire else 0)

    v.tube(0, -120, 30, -22, 50, (69, 79, 66))
    v.tube(-13, -118, 5, -22, 9, (102, 115, 97))
    v.tube(13, -118, 4, -22, 7, (43, 51, 41))
    v.disc(0, -22, 25, (54, 61, 51))
    v.disc(0, -22, 16, (18, 20, 18))
    v.rect(-32, -96, 15, 12, (59, 66, 54))
    v.rect(-28, -112, 5, 18, (79, 87, 74))
    v.rect(-16, -126, 32, 7, (56, 64, 54))
    v.rect(-16, -126, 32, 2, (96, 106, 90))

    fists(v, 6)
    v.outline()

    if fire:
        flash(v, 0, -130, 1.4)
        v.grip(-6)
        v.disc(-30, -4, 18, (143, 143, 148, 102))
        v.disc(26, 2, 20, (128, 128, 133, 77))


def thrower(v, frame, ball):
    """Frame one is the thing in your hand, frame two is the arm gone."""
    v.grip()

    if frame == 2:
        v.rect(-16, -138, 32, 92, SKIN)
        v.rect(-16, -138, 6, 92, SKIN_HI)
        v.rect(-16, -66, 32, 16, CUFF)
        v.rect(-16, -66, 32, 3, CUFF_HI)
        v.disc(0, -140, 18, SKIN)
        for i in range(3):
            v.rect(-15, -152 + i * 9, 30, 6, SKIN)
            v.rect(-15, -147 + i * 9, 30, 2, SKIN_LO)
        v.disc(-15, -136, 7, SKIN_LO)
        v.rect(-14, -150, 10, 4, DRIED)
        v.rect(-6, -144, 6, 3, DRIED_LO)
        v.rect(-14, -120, 5, 9, DRIED)
        v.rect(2, -104, 4, 6, DRIED_LO)
        v.outline()

        return

    v.at(OX, OY - 58 * SC, SC, 0.0)
    ball(v)
    v.grip()
    v.rect(-18, -34, 36, 44, SKIN)
    v.rect(-18, -34, 5, 44, SKIN_HI)
    v.disc(-16, -34, 11, SKIN)
    v.disc(16, -34, 11, SKIN_LO)
    v.rect(-16, -30, 9, 4, DRIED)
    v.rect(-4, -22, 6, 3, DRIED_LO)
    v.rect(8, -34, 5, 6, DRIED)
    v.rect(-18, 2, 36, 14, CUFF)
    v.rect(-18, 2, 36, 3, CUFF_HI)
    v.outline()


def w_grenades(v, frame):
    def ball(v):
        v.disc(0, 0, 20, (66, 87, 51))
        v.disc(-7, -7, 9, (97, 122, 71))
        v.rect(-7, -32, 14, 11, (102, 102, 107))
        v.disc(13, -29, 7, (143, 143, 153))

    thrower(v, frame, ball)


def w_knife(v, frame):
    def ball(v):
        v.rect(-5, -4, 10, 26, (71, 51, 33))
        v.rect(-5, -4, 4, 26, (102, 74, 46))
        v.rect(-9, -8, 18, 5, (117, 120, 128))
        v.poly(((-6, -10), (6, -10), (2, -60), (-2, -60)), (194, 199, 209))
        v.poly(((-6, -10), (-2, -10), (-2, -58)), (240, 242, 247))

    thrower(v, frame, ball)


def w_flashes(v, frame):
    def ball(v):
        v.rect(-14, -30, 28, 44, (117, 120, 128))
        v.rect(-14, -30, 5, 44, (158, 162, 171))
        v.rect(-14, -16, 28, 11, (240, 240, 230))
        v.rect(-14, -1, 28, 6, (209, 184, 51))
        v.rect(-7, -38, 14, 9, (77, 79, 84))

    thrower(v, frame, ball)


# ------------------------------------------------------------- the executions
def victim(v, sink=0, lean=0.0, slump=False):
    """The guard from behind, filling the lower half of the view."""
    v.at(100, 88 + sink, 1.0, 0.0)
    v.poly(((-56, 0), (56, 0), (66, 62), (-66, 62)), (61, 69, 92))
    v.rect(-56, 0, 112, 7, (77, 84, 112))
    v.poly(((2, 0), (56, 0), (66, 62), (2, 62)), (47, 53, 71))
    v.rect(-30, 22, 60, 4, (46, 51, 69))

    v.at(100, 90 + sink, 1.0, lean)
    v.rect(-15, -26, 30, 30, (184, 138, 107))
    v.rect(-15, -26, 30, 6, (148, 107, 84))
    v.disc(0, -48, 30, (133, 97, 74))
    v.disc(0, -50, 28, (194, 148, 115))
    v.disc(2, -50, 26, (168, 125, 96))
    v.disc(0, -57, 29, (43, 51, 79))
    v.disc(0, -59, 26, (56, 66, 97))
    v.disc(-27, -46, 7, (163, 120, 92))
    v.disc(27, -46, 7, (140, 103, 79))
    v.rect(-31, -60, 62, 6, (31, 36, 56))

    if slump:
        v.rect(-20, -34, 40, 10, (115, 15, 18, 204))


def grip_hand(v, x, y, rot, s=1.0):
    v.at(x, y, s, rot)
    v.rect(-20, 0, 40, 64, (107, 77, 56))
    v.disc(0, 0, 19, (107, 77, 56))
    v.rect(-18, 2, 36, 60, (224, 179, 140))
    v.rect(-18, 2, 6, 60, (240, 201, 166))
    v.rect(-18, 48, 36, 14, CUFF)
    v.disc(0, 0, 17, (224, 179, 140))
    for i in range(3):
        v.rect(-16, -12 + i * 9, 32, 6, (173, 128, 97))

    v.rect(-15, -10, 12, 5, DRIED)
    v.rect(-2, 0, 9, 4, DRIED_LO)
    v.rect(-14, 16, 7, 9, DRIED)


def splatter(v, n, sx, sy, spread, size):
    v.screen()
    for i in range(1, n + 1):
        a = (i / n) * math.pi * 2
        r = spread * (0.3 + (i % 3) * 0.3)
        v.disc(sx + math.cos(a) * r, sy + math.sin(a) * r * 0.6,
               size * (0.4 + (i % 4) * 0.25), BLOOD + (217,))


def x_throat(v, frame):
    lean = (-0.05, -0.18, -0.26, -0.36)[frame - 1]
    victim(v, (frame - 1) * 3, lean, frame >= 3)
    grip_hand(v, 58 - frame * 2, 52, 1.95 - frame * 0.07, 0.8)

    if frame == 1:
        hatchet_body(v, 188, 148, 0.35, 0.85)
    elif frame == 2:
        hatchet_body(v, 236, 72, -1.45, 0.85)
        splatter(v, 4, 150, 68, 10, 4)
    elif frame == 3:
        hatchet_body(v, 186, 70, -1.55, 0.85)
        splatter(v, 13, 104, 66, 30, 7)
    else:
        hatchet_body(v, 132, 66, -1.7, 0.85)
        splatter(v, 18, 92, 72, 42, 9)
        v.screen()
        v.rect(44, 86, 112, 10, BLOOD + (153,))


def x_head(v, frame):
    victim(v, (frame - 1) * 5, 0.04 * frame, frame >= 3)

    if frame == 1:
        hatchet_body(v, 170, 56, -2.5, 0.95)
    elif frame == 2:
        hatchet_body(v, 142, 26, -1.5, 0.95)
    elif frame == 3:
        hatchet_body(v, 104, 22, -0.25, 0.95)
        splatter(v, 12, 100, 42, 26, 7)
    else:
        hatchet_body(v, 112, 34, -0.6, 0.95)
        splatter(v, 18, 100, 52, 38, 9)
        v.screen()
        v.rect(56, 58, 92, 8, BLOOD + (140,))

    grip_hand(v, 178, 112, -0.45, 0.8)


def x_neck(v, frame):
    twist = (0, 0.06, 0.5, 0.95)[frame - 1]
    reach = (34, 18, 10, 12)[frame - 1]
    victim(v, (frame - 1) * 3, twist)
    grip_hand(v, 100 - 38 - reach, 50, 1.6 + twist, 0.8)
    grip_hand(v, 100 + 38 + reach, 50, -1.6 + twist, 0.8)
    v.screen()

    if frame == 3:
        for i in range(1, 5):
            v.rect(120 + i * 7, 30 + i * 5, 15, 3, (242, 242, 242, 115))
    elif frame == 4:
        v.rect(50, 34, 100, 4, (235, 235, 235, 77))
        v.rect(58, 44, 84, 3, (235, 235, 235, 51))


DRAW = {"hatchet": w_hatchet, "revolver": w_revolver, "uzi": w_uzi,
        "launcher": w_launcher, "grenades": w_grenades, "flashes": w_flashes,
        "knife": w_knife, "throat": x_throat, "head": x_head, "neck": x_neck}


def draw(name, frame):
    v = View()
    DRAW[name](v, frame)

    return v.im


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/views"
    os.makedirs(out, exist_ok=True)
    n = 0
    for name, count in FRAMES.items():
        for frame in range(1, count + 1):
            draw(name, frame).save("%s/%s.%d.png" % (out, name, frame))
            n += 1

    print("%d files written to %s" % (n, out))
