"""The walls, the doors and the ground, 64 by 64 each, in three looks.

    python3 tools/walls.py out-dir clean
    python3 tools/walls.py out-dir dirty
    python3 tools/walls.py out-dir worn

clean is a block that is still being kept; dirty is one nobody has washed in
years, with mould, grime and what was left after a bad night; worn is one that
has been left to the weather, with rust running out of every bolt and the
paint coming off in sheets. The three use the same shapes, so a wall is always
the same wall and only its condition changes.
"""

import os
import random
import sys

from PIL import Image, ImageDraw

SIZE = 64

NAMES = ("stone", "brick", "cell", "metal", "rock", "poster",
         "door-steel", "door-bars", "door-red", "door-blue", "door-yellow",
         "exit", "locker", "locker-open",
         "panel-stone", "panel-brick", "panel-cell", "panel-metal",
         "panel-rock", "panel-poster", "floor", "ceiling")

# How each look shifts the whole set before anything else is drawn on it.
LOOKS = {
    "clean": dict(gain=1.08, tint=(1.00, 1.00, 1.03)),
    "dirty": dict(gain=0.84, tint=(1.03, 1.00, 0.92)),
    "worn": dict(gain=0.96, tint=(1.06, 0.99, 0.90)),
}

LOOK = "clean"
RNG = random.Random(7)


def tone(c, f=1.0):
    look = LOOKS[LOOK]
    g = look["gain"] * f

    return tuple(max(0, min(255, int(v * g * look["tint"][i]))) for i, v in enumerate(c))


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


class Tex:

    def __init__(self):
        self.im = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def fill(self, c, grain=0):
        self.rect(0, 0, SIZE - 1, SIZE - 1, c, grain)

    def rect(self, x0, y0, x1, y1, c, grain=0):
        if grain:
            for y in range(max(0, y0), min(SIZE, y1 + 1)):
                for x in range(max(0, x0), min(SIZE, x1 + 1)):
                    n = RNG.randint(-grain, grain)
                    self.im.putpixel((x, y), (max(0, min(255, c[0] + n)),
                                              max(0, min(255, c[1] + n)),
                                              max(0, min(255, c[2] + n))))
        else:
            self.d.rectangle([x0, y0, x1, y1], fill=c)

    def px(self, x, y, c):
        if 0 <= x < SIZE and 0 <= y < SIZE:
            self.im.putpixel((x, y), c)

    def blend(self, x, y, c, a):
        if not (0 <= x < SIZE and 0 <= y < SIZE):
            return
        old = self.im.getpixel((x, y))
        self.im.putpixel((x, y), mix(old, c, a))

    def hline(self, y, x0, x1, c):
        self.d.line([(x0, y), (x1, y)], fill=c)

    def vline(self, x, y0, y1, c):
        self.d.line([(x, y0), (x, y1)], fill=c)

    def shade(self, amount):
        """A little less light towards the bottom of every tile."""
        for y in range(SIZE):
            f = 1 - (y / SIZE) * amount
            for x in range(SIZE):
                r, g, b = self.im.getpixel((x, y))
                self.im.putpixel((x, y), (int(r * f), int(g * f), int(b * f)))


# ------------------------------------------------------------------ shapes
def blocks(t, base, mortar, bw, bh, stagger=True):
    t.fill(base, 7)

    for y in range(0, SIZE, bh):
        t.hline(y, 0, SIZE - 1, mortar)
        shift = (y // bh % 2) * (bw // 2) if stagger else 0
        for x in range(0, SIZE, bw):
            t.vline((x + shift) % SIZE, y, min(SIZE - 1, y + bh - 1), mortar)
        for x in range(SIZE):
            t.px(x, y + 1, mix(base, (255, 255, 255), 0.18))
            t.px(x, y + bh - 1, mix(base, (0, 0, 0), 0.28))


def rivets(t, step, light, dark, inset=0):
    for y in range(step + inset, SIZE, step):
        for x in range(step + inset, SIZE, step):
            t.px(x, y, light)
            t.px(x - 1, y, mix(light, dark, 0.4))
            t.px(x, y - 1, mix(light, dark, 0.2))
            t.px(x + 1, y + 1, dark)


def frame(t, inset, c):
    for i in range(inset):
        t.hline(i, 0, SIZE - 1, c)
        t.hline(SIZE - 1 - i, 0, SIZE - 1, mix(c, (0, 0, 0), 0.3))
        t.vline(i, 0, SIZE - 1, c)
        t.vline(SIZE - 1 - i, 0, SIZE - 1, mix(c, (0, 0, 0), 0.3))


def keyhole(t, c):
    t.rect(28, 40, 36, 50, mix(c, (0, 0, 0), 0.55))
    t.rect(29, 41, 35, 49, c)
    t.rect(31, 43, 33, 47, (18, 18, 20))


# ------------------------------------------------------------------- walls
def stone(t):
    blocks(t, tone((116, 116, 110)), tone((74, 74, 70)), 32, 16)
    t.shade(0.10)


def brick(t):
    blocks(t, tone((122, 72, 56)), tone((98, 94, 88)), 16, 8)
    t.shade(0.12)


def cellwall(t):
    """Painted blockwork with the rail the bunks are bolted to."""
    blocks(t, tone((108, 116, 112)), tone((70, 76, 74)), 21, 12)
    t.rect(0, 30, SIZE - 1, 34, tone((92, 100, 98)), 4)
    t.hline(30, 0, SIZE - 1, tone((126, 134, 130)))
    t.hline(34, 0, SIZE - 1, tone((54, 58, 57)))
    t.shade(0.12)


def metal(t):
    t.fill(tone((100, 102, 108)), 5)
    for y in range(0, SIZE, 16):
        t.hline(y, 0, SIZE - 1, tone((68, 70, 76)))
        t.hline(y + 1, 0, SIZE - 1, tone((126, 128, 134)))
    rivets(t, 16, tone((150, 152, 158)), tone((52, 53, 58)))
    t.shade(0.14)


def rock(t):
    t.fill(tone((92, 88, 82)), 10)
    for _ in range(26):
        x, y = RNG.randrange(SIZE), RNG.randrange(SIZE)
        w, h = RNG.randint(5, 13), RNG.randint(4, 9)
        c = tone((92, 88, 82), RNG.uniform(0.82, 1.18))
        t.rect(x, y, x + w, y + h, c, 6)
        t.hline(y, x, x + w, mix(c, (255, 255, 255), 0.12))
        t.hline(y + h, x, x + w, mix(c, (0, 0, 0), 0.3))
    t.shade(0.12)


def poster(t):
    stone(t)
    t.rect(14, 10, 49, 47, tone((198, 190, 168)), 4)
    t.rect(14, 10, 49, 11, tone((226, 220, 200)))
    t.rect(17, 14, 46, 20, tone((150, 40, 36)))
    for x in range(19, 45, 5):
        t.rect(x, 24, x + 3, 30, tone((70, 66, 60)))
    t.rect(19, 34, 44, 36, tone((70, 66, 60)))
    t.rect(19, 39, 38, 41, tone((70, 66, 60)))
    t.shade(0.10)


# ------------------------------------------------------------------- doors
def steeldoor(t):
    t.fill(tone((88, 90, 96)), 5)
    frame(t, 3, tone((62, 64, 70)))
    t.rect(8, 8, 55, 28, tone((98, 100, 106)), 4)
    t.rect(8, 8, 55, 9, tone((124, 126, 132)))
    t.rect(8, 27, 55, 28, tone((58, 60, 66)))
    t.rect(18, 13, 45, 23, tone((26, 27, 30)))
    for x in range(20, 45, 6):
        t.vline(x, 13, 23, tone((120, 122, 128)))
    t.rect(8, 34, 55, 55, tone((94, 96, 102)), 4)
    t.rect(40, 40, 50, 48, tone((70, 72, 78)))
    t.rect(42, 42, 48, 46, tone((132, 134, 140)))
    rivets(t, 14, tone((140, 142, 148)), tone((48, 49, 54)), 1)
    t.shade(0.12)


def barsdoor(t):
    t.fill((14, 14, 17))
    for x in range(4, SIZE - 4, 10):
        t.rect(x, 0, x + 3, SIZE - 1, tone((74, 76, 82)), 5)
        t.vline(x, 0, SIZE - 1, tone((112, 114, 120)))
        t.vline(x + 3, 0, SIZE - 1, tone((42, 43, 47)))
    t.rect(0, 28, SIZE - 1, 32, tone((70, 72, 78)), 5)
    t.hline(28, 0, SIZE - 1, tone((104, 106, 112)))
    t.rect(26, 33, 37, 39, tone((88, 84, 70)))
    t.rect(29, 35, 34, 38, (20, 20, 22))
    t.shade(0.10)


def lockeddoor(t, c):
    t.fill(tone((82, 86, 94)), 5)
    frame(t, 3, tone((56, 58, 66)))
    t.rect(0, 20, SIZE - 1, 29, mix(c, (0, 0, 0), 0.3), 4)
    t.hline(20, 0, SIZE - 1, c)
    t.hline(29, 0, SIZE - 1, mix(c, (0, 0, 0), 0.6))
    t.rect(10, 38, 53, 51, tone((70, 74, 82)), 4)
    keyhole(t, c)
    rivets(t, 20, tone((124, 126, 132)), tone((46, 47, 52)))
    t.shade(0.16)


def exitdoor(t):
    t.fill(tone((72, 76, 82)), 5)
    frame(t, 4, tone((50, 54, 60)))
    t.rect(10, 10, 53, 29, tone((34, 78, 44)), 3)
    t.hline(10, 10, 53, (80, 200, 104))
    for i in range(10):
        t.rect(22 + i, 20 - i, 22 + i, 20 + i, (116, 238, 142))
    t.rect(18, 18, 23, 22, (116, 238, 142))
    t.rect(14, 38, 49, 53, tone((62, 66, 72)), 4)
    t.rect(28, 42, 35, 49, tone((176, 158, 56)))
    t.rect(30, 44, 33, 53, tone((214, 198, 78)))
    t.shade(0.14)


def locker(t, opened):
    t.fill(tone((70, 74, 82)), 4)
    t.rect(6, 2, 57, 61, tone((86, 90, 100)), 5)
    t.rect(6, 2, 57, 3, tone((116, 120, 130)))
    t.vline(6, 2, 61, tone((112, 116, 126)))
    t.vline(57, 2, 61, tone((54, 57, 64)))
    t.hline(61, 6, 57, tone((48, 50, 58)))

    if opened:
        t.rect(10, 6, 53, 58, (22, 23, 27))
        t.rect(10, 30, 53, 32, tone((70, 74, 82)))
        # whatever was left in it, as shapes in the dark
        t.rect(16, 18, 27, 29, tone((112, 96, 52)))
        t.rect(16, 18, 27, 19, tone((150, 130, 70)))
        t.rect(33, 14, 45, 29, tone((58, 70, 60)))
        t.rect(36, 36, 48, 50, tone((128, 42, 40)))
        t.rect(38, 40, 46, 42, (226, 226, 226))
        t.rect(40, 36, 44, 50, (226, 226, 226))
        t.vline(53, 6, 58, tone((40, 42, 48)))
    else:
        for y in range(10, 26, 4):
            t.rect(16, y, 47, y + 1, tone((56, 59, 66)))
            t.rect(16, y + 1, 47, y + 1, tone((104, 108, 118)))
        t.rect(44, 32, 50, 44, tone((56, 59, 66)))
        t.rect(45, 33, 49, 43, tone((130, 134, 144)))
        t.rect(30, 2, 32, 61, tone((62, 66, 74)))

    t.shade(0.12)


def loose(t):
    """The tell on a panel that slides back: a hairline down both sides, the
    scuff on the floor where it has been dragged, and the worn patch where
    hands have pushed it."""
    for y in range(SIZE):
        t.px(0, y, (12, 12, 14))
        t.px(1, y, (28, 28, 31))
        t.px(SIZE - 1, y, (12, 12, 14))
        t.px(SIZE - 2, y, (28, 28, 31))

    for x in range(3, SIZE - 3):
        n = (x * 7 % 5) * 3
        t.px(x, SIZE - 2, (112 + n, 107 + n, 97 + n))
        if x % 3:
            t.px(x, SIZE - 3, (92 + n, 87 + n, 79 + n))

    for y in range(26, 39):
        for x in range(24, 41):
            if (x + y) % 3 == 0:
                t.blend(x, y, (150, 146, 136), 0.5)


# ------------------------------------------------------------------ ground
def floor(t):
    t.fill(tone((104, 102, 96)), 8)
    for v in (0, 32):
        t.hline(v, 0, SIZE - 1, tone((68, 66, 62)))
        t.hline(v + 1, 0, SIZE - 1, tone((122, 120, 114)))
        t.vline(v, 0, SIZE - 1, tone((68, 66, 62)))
        t.vline(v + 1, 0, SIZE - 1, tone((122, 120, 114)))
    for _ in range(170):
        x, y = RNG.randrange(SIZE), RNG.randrange(SIZE)
        t.blend(x, y, (210, 206, 196), 0.18)
    for _ in range(70):
        x, y = RNG.randrange(SIZE), RNG.randrange(SIZE)
        t.blend(x, y, (40, 38, 36), 0.35)
    t.rect(29, 0, 34, SIZE - 1, tone((88, 86, 82)), 5)
    t.vline(29, 0, SIZE - 1, tone((58, 57, 54)))
    t.vline(34, 0, SIZE - 1, tone((58, 57, 54)))


def ceiling(t):
    t.fill(tone((76, 76, 82)), 5)
    t.rect(6, 6, 57, 57, tone((88, 88, 94)), 4)
    t.hline(6, 6, 57, tone((112, 112, 118)))
    t.hline(57, 6, 57, tone((54, 54, 60)))
    t.vline(6, 6, 57, tone((106, 106, 112)))
    t.vline(57, 6, 57, tone((54, 54, 60)))
    t.rect(0, 0, SIZE - 1, 4, tone((62, 62, 68)), 4)
    t.rect(0, 0, 4, SIZE - 1, tone((62, 62, 68)), 4)
    for i in range(2, SIZE, 16):
        t.px(2, i, tone((124, 124, 130)))
        t.px(i, 2, tone((124, 124, 130)))
    # the strip light, dead for years
    t.rect(20, 24, 44, 30, tone((56, 56, 60)))
    t.rect(22, 26, 42, 28, tone((132, 132, 126)))


# ------------------------------------------------------------------- grime
def drips(t, x0, x1, c, count, top=0):
    for _ in range(count):
        x = RNG.randint(x0, x1)
        y = RNG.randint(top, top + 12)
        run = RNG.randint(6, 26)
        a = RNG.uniform(0.25, 0.5)
        for i in range(run):
            t.blend(x, y + i, c, a * (1 - i / run))
            if i % 4 == 0:
                t.blend(x + 1, y + i, c, a * 0.4 * (1 - i / run))


def splat(t, cx, cy, r, c):
    for _ in range(r * 9):
        a = RNG.uniform(0, 6.283)
        d = RNG.uniform(0, r) * RNG.uniform(0.4, 1.0)
        x = int(cx + d * __import__("math").cos(a))
        y = int(cy + d * __import__("math").sin(a) * 0.8)
        t.blend(x, y, c, RNG.uniform(0.45, 0.9))
    for _ in range(r):
        x = int(cx + RNG.uniform(-r * 1.8, r * 1.8))
        y = int(cy + RNG.uniform(-r * 1.5, r * 1.5))
        t.blend(x, y, c, RNG.uniform(0.3, 0.7))


def patches(t, c, count, size, alpha):
    for _ in range(count):
        cx, cy = RNG.randrange(SIZE), RNG.randrange(SIZE)
        w, h = RNG.randint(size, size * 2), RNG.randint(size, size * 2)
        for y in range(cy, cy + h):
            for x in range(cx, cx + w):
                d = ((x - cx - w / 2) / w) ** 2 + ((y - cy - h / 2) / h) ** 2
                if d < 0.25 and RNG.random() > 0.3:
                    t.blend(x % SIZE, y % SIZE, c, alpha * (1 - d * 3))


def cracks(t, count, c):
    for _ in range(count):
        x, y = RNG.randrange(SIZE), RNG.randrange(SIZE)
        dx, dy = RNG.choice(((1, 1), (1, -1), (0, 1), (1, 0)))
        for _ in range(RNG.randint(10, 26)):
            t.blend(x, y, c, 0.55)
            t.blend(x + 1, y, c, 0.2)
            x += dx if RNG.random() > 0.3 else 0
            y += dy if RNG.random() > 0.3 else 0
            if RNG.random() > 0.85:
                dx, dy = RNG.choice(((1, 1), (1, -1), (0, 1), (1, 0)))


def grime(t, name):
    """What the years have left on this one."""
    wall = name in ("stone", "brick", "cell", "metal", "rock", "poster")
    ground = name in ("floor", "ceiling")

    if LOOK == "clean":
        if wall or ground:
            patches(t, (255, 255, 255), 2, 6, 0.06)
            cracks(t, 1, (44, 44, 46))

        return

    if LOOK == "dirty":
        # soot and mould where the damp sits
        patches(t, (36, 42, 32), 4, 9, 0.5)
        patches(t, (24, 22, 20), 3, 12, 0.4)
        drips(t, 0, SIZE - 1, (28, 30, 26), 7)
        if name != "ceiling":
            for y in range(SIZE - 16, SIZE):
                a = (y - (SIZE - 16)) / 16 * 0.45
                for x in range(SIZE):
                    if RNG.random() > 0.25:
                        t.blend(x, y, (22, 22, 20), a)

        # blood goes where it stays: pools on the floor, a smear on the
        # bars and on the locker somebody was dragged past. Not on every
        # wall, or a corridor of the same tile turns into a slaughterhouse.
        if name == "floor":
            splat(t, RNG.randint(20, 42), RNG.randint(18, 40), 15, (104, 16, 16))
            splat(t, RNG.randint(8, 54), RNG.randint(8, 54), 7, (84, 13, 13))
        elif name in ("door-bars", "locker"):
            cx, cy = RNG.randint(20, 44), RNG.randint(26, 40)
            splat(t, cx, cy, 5, (96, 15, 15))
            for x in range(cx - 3, cx + 4, 3):
                run = RNG.randint(6, 14)
                for i in range(run):
                    t.blend(x, cy + 3 + i, (78, 12, 12), 0.55 * (1 - i / run))

        if name == "cell":
            # somebody kept count on this one, scratched into the paint
            for i in range(5):
                for y in range(40, 50):
                    t.blend(44 + i * 2, y, (48, 48, 46), 0.5)

        return

    # worn: rust out of the bolts, paint off the walls, cracks everywhere
    rust = (138, 76, 32)
    drips(t, 0, SIZE - 1, rust, 9)
    patches(t, rust, 3, 8, 0.45)
    patches(t, (198, 196, 186), 3, 7, 0.3)
    cracks(t, 4, (38, 36, 36))
    for _ in range(90):
        x, y = RNG.randrange(SIZE), RNG.randrange(SIZE)
        t.blend(x, y, (30, 28, 26), RNG.uniform(0.2, 0.6))


PAINTERS = {
    "stone": stone, "brick": brick, "cell": cellwall, "metal": metal,
    "rock": rock, "poster": poster,
    "door-steel": steeldoor, "door-bars": barsdoor,
    "door-red": lambda t: lockeddoor(t, (214, 46, 46)),
    "door-blue": lambda t: lockeddoor(t, (56, 108, 228)),
    "door-yellow": lambda t: lockeddoor(t, (234, 200, 40)),
    "exit": exitdoor,
    "locker": lambda t: locker(t, False),
    "locker-open": lambda t: locker(t, True),
    "floor": floor, "ceiling": ceiling,
}


def draw(name):
    t = Tex()
    base = name[6:] if name.startswith("panel-") else name
    PAINTERS[base](t)
    grime(t, base)
    if name.startswith("panel-"):
        loose(t)

    return t.im


if __name__ == "__main__":
    out, LOOK = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for name in NAMES:
        RNG.seed(hash((LOOK, name)) & 0xffff)
        draw(name).save("%s/%s.png" % (out, name))

    print("%d files written to %s" % (len(NAMES), out))
