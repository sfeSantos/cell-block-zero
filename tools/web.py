"""Build the browser version of the game into docs/play.

The engine is love.js, LOVE 11.4 built for WebAssembly with Emscripten. Two
runtime files come out of that package, love.js and love.wasm, and they are
kept in docs/play so GitHub Pages serves the whole thing on its own. The rest
is ours: the page in tools/web/index.html, and the game packed as a plain
.love that the page hands to the engine.

    python3 tools/web.py

The engine is only downloaded the first time, or when --engine asks for it
again. The one patch made to love.js is noted in patch_engine below.
"""

import hashlib
import io
import os
import shutil
import sys
import tarfile
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "play")

ENGINE = "https://registry.npmjs.org/love.js/-/love.js-11.4.1.tgz"
ENGINE_SHA1 = "4b3772a53713c2404b760ae794562d8a72d457ec"

# The compatibility build is the one GitHub Pages can serve: the other needs
# the two cross origin isolation headers, which Pages does not send.
INSIDE = "package/src/compat/"

# What goes in the .love, which is the same list the desktop zip gets.
PACK = ("conf.lua", "main.lua", "LICENSE.md", "src", "levels", "assets")
SKIP = (".swp", ".pyc", ".love")

# love.js mounts the save directory on IndexedDB and flushes it when the page
# unloads, which is one event and not a reliable one. The file keeps FS to
# itself, so hand it to the page and let the page flush on a timer as well.
EXPORT_FS = 'Module["FS"]=FS;window.addEventListener("beforeunload"'
BEFORE_FS = 'window.addEventListener("beforeunload"'


def fetch_engine():
    print("downloading %s" % ENGINE)
    blob = urllib.request.urlopen(ENGINE, timeout=120).read()
    got = hashlib.sha1(blob).hexdigest()

    if got != ENGINE_SHA1:
        raise SystemExit("love.js-11.4.1.tgz is not the one this script knows:"
            " sha1 %s, expected %s" % (got, ENGINE_SHA1))

    print("  %d bytes, sha1 %s" % (len(blob), got))

    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as tar:
        for name in ("love.js", "love.wasm"):
            member = tar.getmember(INSIDE + name)
            with open(os.path.join(OUT, name), "wb") as f:
                shutil.copyfileobj(tar.extractfile(member), f)
            print("  %s, %d bytes" % (name, member.size))


def patch_engine():
    path = os.path.join(OUT, "love.js")
    text = open(path, encoding="utf8").read()

    if EXPORT_FS in text:
        return False

    if BEFORE_FS not in text:
        raise SystemExit("love.js is not the build this script knows about")

    open(path, "w", encoding="utf8").write(text.replace(BEFORE_FS, EXPORT_FS, 1))

    return True


def files():
    for entry in PACK:
        full = os.path.join(ROOT, entry)
        if os.path.isfile(full):
            yield full, entry

            continue

        for here, dirs, names in os.walk(full):
            dirs.sort()
            for name in sorted(names):
                if not name.endswith(SKIP):
                    path = os.path.join(here, name)
                    yield path, os.path.relpath(path, ROOT)


def pack():
    path = os.path.join(OUT, "game.love")
    count = 0

    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for full, name in files():
            zf.write(full, name.replace(os.sep, "/"))
            count += 1

    return path, count


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    missing = not os.path.exists(os.path.join(OUT, "love.wasm"))

    if missing or "--engine" in sys.argv:
        fetch_engine()

    print("patched love.js" if patch_engine() else "love.js already patched")

    shutil.copy(os.path.join(ROOT, "tools", "web", "index.html"),
        os.path.join(OUT, "index.html"))

    path, count = pack()
    print("%s, %d files, %d bytes" % (path, count, os.path.getsize(path)))
    print("open docs/play/index.html over http, not from the file system")
