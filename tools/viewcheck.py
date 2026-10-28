"""Says whether the code drawn weapon views still match the files.

The weapon in your hands exists twice: tools/weapons.py writes
assets/views/*.png, and the view builders in src/art.lua draw the same frames
for whichever file is missing. They are meant to be the same picture, and
twice now they have drifted without anybody noticing. This builds the view
sheet both ways in one LOVE run, once with assets/views in place and once
with art.VIEW_DIR pointed at nothing, and compares the two cell by cell.

    python3 tools/viewcheck.py

It prints a line per weapon and leaves with 1 if any weapon row falls below
95% silhouette overlap. --frames prints every frame instead of the range over
a row, and --crops writes the two versions of each frame side by side so you
can look at what the numbers are complaining about.

LOVE has to do the drawing, since the fallback is love.graphics calls and
nothing else can run them, so the work is split: this script copies the game
into a scratch directory with a main.lua that dumps both sheets, and then
does the measuring here where Pillow is.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

# What counts as part of the silhouette. The outline tools/weapons.py paints
# is opaque and the flashes are not, so the line sits where a pixel starts to
# read as the shape rather than as a glow over it.
SOLID = 128

# Below this a row is a failure. The execution frames were ported once and
# never touched, and they have always measured 98, which is what says the bar
# is reachable.
FLOOR = 95.0

WEAPONS = ("hatchet", "revolver", "uzi", "launcher", "grenades", "flashes",
           "knife")

CONF = """function love.conf(t)
    t.identity = "cbz-viewcheck"
    t.version = "11.4"
    t.window.width = 320
    t.window.height = 200
    t.window.fullscreen = false
    t.window.vsync = 0
    t.modules.physics = false
    t.modules.joystick = false
    t.modules.touch = false
    t.modules.video = false
end
"""

# art.VIEW_DIR is a plain field, so the second pass only has to point it at a
# folder that is not there to get the sheet the game falls back to.
MAIN = """io.stdout:setvbuf("line")

-- whatever a run before this one left behind, so a pass cannot be read off a
-- stale dump
for _, name in ipairs({"files.png", "code.png", "rects.txt"}) do
    love.filesystem.remove(name)
end

local function dump(art, tag)
    art.views:newImageData():encode("png", tag .. ".png")
    print(string.format("DUMP %s %d", tag, art.loaded.views))
end

function love.load()
    require("src.textures").load()

    local art = require("src.art")
    art.load()
    dump(art, "files")

    local rects = {}
    for _, name in ipairs(art.VIEW_ORDER) do
        for col = 1, art.VIEW_FRAMES[name] do
            local x, y, w, h = art.viewQuad(name, col):getViewport()
            rects[#rects + 1] = string.format("%s %d %d %d %d %d",
                name, col, x, y, w, h)
        end
    end
    love.filesystem.write("rects.txt", table.concat(rects, "\\n"))

    art.VIEW_DIR = "assets/views.none"
    art.load()
    dump(art, "code")

    print("SAVEDIR " .. love.filesystem.getSaveDirectory())
    love.event.quit(0)
end

function love.draw() end
"""


def build_sheets(root):
    """Both sheets and the frame rectangles, out of one LOVE run."""
    work = tempfile.mkdtemp(prefix="viewcheck-")
    try:
        for part in ("src", "assets"):
            shutil.copytree(os.path.join(root, part), os.path.join(work, part))
        for name, text in (("conf.lua", CONF), ("main.lua", MAIN)):
            with open(os.path.join(work, name), "w") as out:
                out.write(text)

        run = subprocess.run(["love", work], capture_output=True, text=True,
                             timeout=600)
        out = run.stdout
        save = re.search(r"^SAVEDIR (.+)$", out, re.M)
        painted = dict(re.findall(r"^DUMP (\w+) (\d+)$", out, re.M))

        if run.returncode != 0 or not save:
            sys.stderr.write(out + run.stderr)
            raise SystemExit("viewcheck: the LOVE pass did not finish")

        if painted.get("files") == "0":
            raise SystemExit("viewcheck: assets/views is empty, nothing to "
                             "compare the code against")

        if painted.get("code") != "0":
            raise SystemExit("viewcheck: the second pass still painted files "
                             "over the drawing, so it is not the fallback")

        save = save.group(1)
        files = Image.open(os.path.join(save, "files.png")).convert("RGBA")
        code = Image.open(os.path.join(save, "code.png")).convert("RGBA")
        rects = []
        with open(os.path.join(save, "rects.txt")) as text:
            for line in text:
                name, col, x, y, w, h = line.split()
                rects.append((name, int(col),
                              (int(x), int(y),
                               int(x) + int(w), int(y) + int(h))))

        return files, code, rects
    finally:
        shutil.rmtree(work, ignore_errors=True)


def measure(a, b):
    """One frame of the file art against one frame of the drawing: how much
    of the silhouette they share, how much more ink the file has, and how far
    apart the colour is on the ink both of them have."""
    pa, pb = a.load(), b.load()
    w, h = a.size
    both = only_a = only_b = 0
    colour = 0

    for y in range(h):
        for x in range(w):
            ca, cb = pa[x, y], pb[x, y]
            ina, inb = ca[3] >= SOLID, cb[3] >= SOLID

            if ina and inb:
                both += 1
                colour += (abs(ca[0] - cb[0]) + abs(ca[1] - cb[1])
                           + abs(ca[2] - cb[2])) / 3
            elif ina:
                only_a += 1
            elif inb:
                only_b += 1

    union = both + only_a + only_b
    ink_a, ink_b = both + only_a, both + only_b

    return {
        "iou": 100.0 * both / union if union else 100.0,
        "ink": 100.0 * (ink_a - ink_b) / ink_b if ink_b else 0.0,
        "colour": colour / both if both else 0.0,
    }


def band(values, fmt):
    """A column of the table: one number when every frame agrees, the two
    ends of the range when they do not."""
    lo, hi = fmt % min(values), fmt % max(values)

    return lo if lo == hi else "%s to %s" % (lo, hi)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frames", action="store_true",
                    help="one line per frame instead of a range per weapon")
    ap.add_argument("--crops", metavar="DIR",
                    help="write each frame as file against code, side by side")
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    files, code, rects = build_sheets(root)

    if args.crops:
        os.makedirs(args.crops, exist_ok=True)

    rows = {}
    for name, col, box in rects:
        a, b = files.crop(box), code.crop(box)
        rows.setdefault(name, []).append((col, measure(a, b)))

        if args.crops:
            w, h = a.size
            pair = Image.new("RGBA", (w * 2 + 8, h), (24, 24, 28, 255))
            pair.paste(b, (0, 0), b)
            pair.paste(a, (w + 8, 0), a)
            pair.save("%s/%s.%d.png" % (args.crops, name, col))

    print("%-10s %-14s %-14s %s" % ("row", "IoU", "ink, file to code",
                                    "mean colour"))
    bad = []
    for name, frames in rows.items():
        worst = min(m["iou"] for _, m in frames)
        if name in WEAPONS and worst < FLOOR:
            bad.append("%s is at %.0f%%" % (name, worst))

        if args.frames:
            for col, m in frames:
                print("%-10s %-14s %-14s %.1f"
                      % ("%s.%d" % (name, col), "%.0f%%" % m["iou"],
                         "%+.0f%%" % m["ink"], m["colour"]))
            continue

        print("%-10s %-14s %-14s %s"
              % (name,
                 band([m["iou"] for _, m in frames], "%.0f%%"),
                 band([m["ink"] for _, m in frames], "%+.0f%%"),
                 band([m["colour"] for _, m in frames], "%.0f")))

    if bad:
        print("\nbelow the %.0f%% floor: %s" % (FLOOR, ", ".join(bad)))

        return 1

    print("\nevery weapon row is at %.0f%% or better" % FLOOR)

    return 0


if __name__ == "__main__":
    sys.exit(main())
