-- Every sprite is drawn into one canvas at load time: guards, pickups,
-- projectiles, explosions, and the weapon the player holds. Cells are 128 by
-- 128 and a cell always stands for a square one tile wide and one tile tall, so
-- the raycaster never needs per sprite measurements.
--
-- The drawing below is all written against a 64 wide grid, which is the size
-- the cell used to be. GRID is that grid and CELL is what it is painted into,
-- and push() scales one to the other, so a coordinate here means a sixty
-- fourth of a tile whatever the cell grows to. The files in assets/ are drawn
-- at the full CELL, which is the whole point: they carry detail this code
-- cannot, and they win wherever they exist.

local textures = require("src.textures")

local art = {}

local CELL = 128
local GRID = 64
local SCALE = CELL / GRID
local COLS = 10

local cells = {}
local quads = {}
local used = 0

local lg = love and love.graphics

local function reserve(name)
    local col = used % COLS
    local row = math.floor(used / COLS)
    used = used + 1
    cells[name] = {x = col * CELL, y = row * CELL}

    return cells[name]
end

local function push(name)
    local c = cells[name]
    lg.push()
    lg.setScissor(c.x, c.y, CELL, CELL)
    lg.translate(c.x, c.y)
    lg.scale(SCALE)
end

local function pop()
    lg.setScissor()
    lg.pop()
end

local function rect(x, y, w, h, c)
    lg.setColor(c)
    lg.rectangle("fill", x, y, w, h)
end

local function poly(c, ...)
    lg.setColor(c)
    lg.polygon("fill", ...)
end

local function disc(x, y, r, c)
    lg.setColor(c)
    lg.circle("fill", x, y, r, math.max(8, r * 3))
end

local function tint(c, f)
    return {c[1] * f, c[2] * f, c[3] * f, c[4] or 1}
end

-- The three guard looks. Difficulty reads off this table as well, so the
-- numbers that matter in a fight sit next to the ones that only matter on
-- screen.
art.TIERS = {
    {
        key = "g1",
        name = "Guard",
        skin = {0.80, 0.62, 0.48},
        shirt = {0.27, 0.34, 0.54},
        trouser = {0.20, 0.22, 0.30},
        boot = {0.12, 0.12, 0.14},
        hat = {0.18, 0.22, 0.36},
        gun = {0.22, 0.22, 0.24},
        bulk = 1.0,
        vest = nil,
        visor = nil,
    },
    {
        key = "g2",
        name = "Sergeant",
        skin = {0.74, 0.56, 0.42},
        shirt = {0.34, 0.35, 0.23},
        trouser = {0.26, 0.26, 0.19},
        boot = {0.14, 0.13, 0.11},
        hat = {0.30, 0.31, 0.22},
        gun = {0.18, 0.18, 0.20},
        bulk = 1.1,
        vest = {0.22, 0.23, 0.17},
        visor = nil,
    },
    {
        key = "g3",
        name = "Riot captain",
        skin = {0.70, 0.52, 0.40},
        shirt = {0.15, 0.16, 0.19},
        trouser = {0.11, 0.12, 0.14},
        boot = {0.08, 0.08, 0.09},
        hat = {0.10, 0.11, 0.13},
        gun = {0.14, 0.14, 0.16},
        bulk = 1.25,
        vest = {0.19, 0.20, 0.24},
        visor = {0.85, 0.20, 0.18},
    },
}

art.FRAMES = {"idle", "walk1", "walk2", "walk3", "walk4", "aim", "fire", "pain",
    "die1", "die2", "die3", "dead", "sleep"}

local function head(t, x, y, lean)
    local hx = x + lean
    disc(hx, y, 7, t.skin)
    rect(hx - 7, y - 8, 14, 5, t.hat)
    rect(hx - 8, y - 4, 16, 2, tint(t.hat, 0.8))

    if t.visor then
        rect(hx - 7, y - 2, 14, 5, t.visor)
        rect(hx - 7, y - 2, 14, 1, tint(t.visor, 1.5))
    else
        rect(hx - 4, y - 1, 2, 2, {0.08, 0.08, 0.10})
        rect(hx + 2, y - 1, 2, 2, {0.08, 0.08, 0.10})
        rect(hx - 2, y + 4, 4, 1, {0.45, 0.28, 0.24})
    end
end

local function legs(t, cx, swing)
    local w = 7 * t.bulk
    rect(cx - w - 1 + swing, 38, w, 18, t.trouser)
    rect(cx + 1 - swing, 38, w, 18, tint(t.trouser, 0.85))
    rect(cx - w - 1 + swing, 55, w, 5, t.boot)
    rect(cx + 1 - swing, 55, w, 5, tint(t.boot, 0.85))
end

local function torso(t, cx, lean)
    local sw = 13 * t.bulk
    local hw = 9 * t.bulk
    poly(t.shirt,
        cx - sw + lean, 22,
        cx + sw + lean, 22,
        cx + hw, 40,
        cx - hw, 40)
    poly(tint(t.shirt, 0.82),
        cx + 2 + lean, 22,
        cx + sw + lean, 22,
        cx + hw, 40,
        cx + 2, 40)

    if t.vest then
        poly(t.vest,
            cx - sw + 2 + lean, 24,
            cx + sw - 2 + lean, 24,
            cx + hw - 1, 37,
            cx - hw + 1, 37)
        rect(cx - 1 + lean, 24, 2, 13, tint(t.vest, 0.7))
    end
end

local function armsDown(t, cx, swing)
    local sw = 13 * t.bulk
    rect(cx - sw - 2 - swing, 23, 5, 17, tint(t.shirt, 0.9))
    rect(cx + sw - 3 + swing, 23, 5, 17, tint(t.shirt, 0.75))
    disc(cx - sw + swing * -1, 41, 3, t.skin)
    disc(cx + sw - 1 + swing, 41, 3, t.skin)
end

local function sideGun(t, cx)
    rect(cx + 9, 36, 10, 4, t.gun)
    rect(cx + 12, 39, 3, 5, tint(t.gun, 0.8))
end

local function aimedGun(t, cx, flash)
    local sw = 13 * t.bulk
    rect(cx - sw - 1, 24, 6, 9, tint(t.shirt, 0.9))
    rect(cx + sw - 5, 24, 6, 9, tint(t.shirt, 0.75))
    disc(cx - 6, 32, 4, t.skin)
    disc(cx + 6, 32, 4, t.skin)
    rect(cx - 5, 28, 10, 7, t.gun)
    disc(cx, 31, 3, {0.05, 0.05, 0.06})

    if flash then
        disc(cx, 31, 7, {1, 0.92, 0.55, 0.9})
        disc(cx, 31, 12, {1, 0.68, 0.18, 0.45})
        poly({1, 0.85, 0.35, 0.7},
            cx - 14, 31, cx, 26, cx + 14, 31, cx, 36)
    end
end

-- Asleep in the chair by the door, which is the only time a riot captain is
-- worth walking up to.
local function sleeper(t)
    local cx = 32

    disc(cx, 60, 12, {0, 0, 0, 0.28})

    -- the chair, seen from the side he is not on
    rect(cx - 14, 40, 26, 4, {0.34, 0.26, 0.17})
    rect(cx + 8, 20, 5, 24, {0.30, 0.23, 0.15})
    rect(cx - 13, 44, 4, 16, {0.26, 0.20, 0.13})
    rect(cx + 8, 44, 4, 16, {0.26, 0.20, 0.13})

    -- boots out in front of him
    rect(cx - 20, 48, 16, 7, t.trouser)
    rect(cx - 24, 50, 7, 7, t.boot)
    rect(cx - 20, 42, 14, 7, tint(t.trouser, 0.88))

    -- slumped back, arms off his lap
    poly(t.shirt, cx - 10, 22, cx + 10, 22, cx + 8, 42, cx - 12, 42)
    if t.vest then
        poly(t.vest, cx - 8, 25, cx + 8, 25, cx + 6, 39, cx - 10, 39)
    end

    rect(cx - 16, 30, 6, 14, tint(t.shirt, 0.9))
    disc(cx - 14, 44, 3, t.skin)
    rect(cx + 6, 30, 5, 12, tint(t.shirt, 0.78))

    -- the gun across his knees
    rect(cx - 12, 40, 16, 4, t.gun)

    -- chin on his chest
    lg.push()
    lg.translate(cx - 2, 20)
    lg.rotate(0.35)
    lg.translate(-(cx - 2), -20)
    disc(cx - 2, 16, 7, t.skin)
    rect(cx - 9, 8, 14, 5, t.hat)
    rect(cx - 10, 12, 16, 2, tint(t.hat, 0.8))
    rect(cx - 6, 17, 3, 1, {0.10, 0.09, 0.09})
    rect(cx, 17, 3, 1, {0.10, 0.09, 0.09})
    lg.pop()

    -- and one small z, so there is no mistaking him at twenty tiles
    local zc = {0.80, 0.82, 0.86, 0.75}
    rect(cx + 12, 8, 8, 2, zc)
    rect(cx + 12, 14, 8, 2, zc)
    poly(zc, cx + 18, 10, cx + 20, 10, cx + 14, 14, cx + 12, 14)
end

local function guardFrame(t, frame)
    local cx = 32
    local phase = ({walk1 = 0, walk2 = 1, walk3 = 2, walk4 = 3})[frame]

    if frame == "sleep" then
        return sleeper(t)
    end

    if frame == "die1" or frame == "die2" or frame == "die3" or frame == "dead" then
        local step = ({die1 = 0.3, die2 = 0.65, die3 = 0.95, dead = 1})[frame]
        lg.push()
        lg.translate(cx, 60)
        lg.rotate(step * 1.45)
        lg.translate(-cx, -60)
        legs(t, cx, 3)
        torso(t, cx, 0)
        armsDown(t, cx, -4)
        head(t, cx, 14, 0)
        lg.pop()

        if step > 0.6 then
            disc(26, 58, 7 * step, {0.35, 0.05, 0.06, 0.8})
            disc(38, 60, 5 * step, {0.30, 0.04, 0.05, 0.7})
        end

        return
    end

    local swing = 0
    local lean = 0
    if phase then
        swing = math.floor(math.sin(phase * math.pi / 2) * 4)
        lean = math.floor(math.cos(phase * math.pi / 2) * 1)
    elseif frame == "pain" then
        lean = -3
    end

    disc(cx, 60, 11 * t.bulk, {0, 0, 0, 0.35})
    legs(t, cx, swing)
    torso(t, cx, lean)

    if frame == "aim" or frame == "fire" then
        aimedGun(t, cx, frame == "fire")
    else
        armsDown(t, cx, swing)
        sideGun(t, cx)
    end

    head(t, cx, 14, lean)

    if frame == "pain" then
        lg.setColor(0.75, 0.10, 0.10, 0.45)
        lg.rectangle("fill", 14, 12, 36, 46)
        disc(cx + 6, 28, 4, {0.55, 0.06, 0.07, 0.85})
    end
end

local STEEL = {0.30, 0.31, 0.34}
local DARK = {0.14, 0.14, 0.16}
local BRASS = {0.72, 0.58, 0.22}

local items = {}

function items.uzi()
    rect(16, 40, 26, 9, DARK)
    rect(18, 36, 10, 5, tint(DARK, 1.4))
    rect(42, 42, 12, 4, STEEL)
    rect(24, 49, 7, 12, tint(DARK, 1.2))
    rect(14, 43, 4, 8, tint(DARK, 0.8))
    rect(34, 49, 4, 6, tint(DARK, 0.9))
end

function items.launcher()
    rect(10, 40, 40, 11, {0.26, 0.30, 0.25})
    rect(10, 40, 40, 3, {0.38, 0.43, 0.36})
    disc(50, 45, 6, {0.22, 0.25, 0.21})
    poly({0.62, 0.20, 0.16}, 50, 40, 58, 45, 50, 51)
    rect(22, 34, 12, 6, {0.20, 0.23, 0.19})
    rect(26, 51, 5, 8, {0.18, 0.20, 0.17})
end

function items.grenades()
    for _, g in ipairs({{24, 48}, {38, 52}}) do
        disc(g[1], g[2], 7, {0.26, 0.34, 0.20})
        disc(g[1] - 2, g[2] - 2, 3, {0.36, 0.46, 0.26})
        rect(g[1] - 3, g[2] - 10, 6, 4, {0.40, 0.40, 0.42})
        disc(g[1] + 5, g[2] - 9, 3, {0.55, 0.55, 0.58})
    end
end

function items.flashes()
    for _, g in ipairs({{25, 48}, {39, 52}}) do
        rect(g[1] - 5, g[2] - 8, 10, 16, {0.44, 0.45, 0.48})
        rect(g[1] - 5, g[2] - 3, 10, 4, {0.92, 0.92, 0.88})
        rect(g[1] - 5, g[2] + 3, 10, 2, {0.80, 0.70, 0.20})
        rect(g[1] - 3, g[2] - 12, 6, 4, {0.30, 0.31, 0.33})
    end
end

function items.bullets()
    for i = 0, 4 do
        rect(22 + i * 4, 48, 3, 10, BRASS)
        poly({0.52, 0.40, 0.16}, 22 + i * 4, 48, 25 + i * 4, 48, 23.5 + i * 4, 44)
    end
    rect(20, 54, 24, 5, {0.35, 0.36, 0.38})
end

-- A pair of uzi magazines, taped together the way the wing guards carry
-- them, so they do not read as loose revolver rounds on the floor.
function items.clips()
    for _, x in ipairs({20, 33}) do
        rect(x, 36, 11, 22, {0.26, 0.27, 0.30})
        rect(x, 36, 11, 3, {0.40, 0.42, 0.46})
        rect(x + 1, 41, 2, 15, {0.17, 0.18, 0.20})
        rect(x + 8, 41, 2, 15, {0.17, 0.18, 0.20})
        rect(x + 3, 33, 5, 4, BRASS)
    end

    rect(18, 44, 28, 3, {0.14, 0.14, 0.16})
    rect(18, 52, 28, 3, {0.14, 0.14, 0.16})
end

function items.ammobox()
    rect(14, 38, 36, 20, {0.32, 0.34, 0.24})
    rect(14, 38, 36, 4, {0.44, 0.46, 0.32})
    rect(14, 46, 36, 2, {0.22, 0.24, 0.17})
    rect(28, 34, 8, 5, {0.26, 0.28, 0.20})
    for i = 0, 3 do
        rect(18 + i * 6, 32, 3, 7, BRASS)
    end
    rect(18, 50, 28, 4, {0.20, 0.21, 0.15})
end

function items.rockets()
    for _, r in ipairs({{24, 0}, {38, 4}}) do
        rect(r[1] - 4, 40 + r[2], 8, 16, {0.30, 0.33, 0.28})
        poly({0.62, 0.20, 0.16}, r[1] - 4, 40 + r[2], r[1] + 4, 40 + r[2], r[1], 31 + r[2])
        rect(r[1] - 6, 54 + r[2], 12, 3, {0.22, 0.24, 0.20})
    end
end

-- Shoulder straps and a gap for the neck, because on the floor a plain slab
-- reads as a crate and this has to read as something you put on.
local function vestShape(body, plate, mark)
    poly(body, 18, 34, 27, 34, 27, 38, 37, 38, 37, 34, 46, 34,
        48, 48, 44, 60, 20, 60, 16, 48)
    rect(31, 38, 2, 22, tint(body, 0.7))
    rect(21, 42, 22, 3, plate)
    rect(21, 50, 22, 3, plate)
    rect(14, 36, 8, 16, tint(body, 0.85))
    rect(42, 36, 8, 16, tint(body, 0.85))
    rect(14, 36, 8, 2, tint(body, 1.2))
    rect(42, 36, 8, 2, tint(body, 1.2))
    poly(tint(body, 1.25), 18, 34, 26, 34, 24, 40, 17, 40)
    rect(24, 55, 16, 3, tint(plate, 0.8))

    if mark then
        rect(29, 44, 6, 6, mark)
    end
end

function items.vest()
    vestShape({0.34, 0.36, 0.30}, {0.26, 0.28, 0.23})
end

function items.vestheavy()
    vestShape({0.18, 0.19, 0.22}, {0.12, 0.13, 0.15}, {0.80, 0.72, 0.20})
end

function items.medkit()
    rect(16, 38, 32, 22, {0.86, 0.86, 0.84})
    rect(16, 38, 32, 3, {0.70, 0.70, 0.68})
    rect(28, 42, 8, 14, {0.78, 0.14, 0.14})
    rect(22, 46, 20, 6, {0.78, 0.14, 0.14})
    rect(26, 34, 12, 5, {0.60, 0.60, 0.58})
end

function items.snack()
    rect(14, 46, 36, 12, {0.40, 0.41, 0.44})
    rect(14, 46, 36, 2, {0.54, 0.55, 0.58})
    disc(26, 48, 6, {0.58, 0.44, 0.26})
    disc(39, 49, 5, {0.42, 0.46, 0.28})
    rect(20, 42, 10, 5, {0.66, 0.52, 0.30})
end

local function keyShape(c)
    disc(26, 44, 8, c)
    lg.setBlendMode("replace")
    disc(26, 44, 4, {0, 0, 0, 0})
    lg.setBlendMode("alpha")
    rect(32, 42, 18, 4, c)
    rect(44, 46, 3, 6, c)
    rect(38, 46, 3, 5, c)
    disc(24, 41, 3, tint(c, 1.5))
end

function items.redkey()
    keyShape({0.84, 0.20, 0.18})
end

function items.bluekey()
    keyShape({0.26, 0.46, 0.88})
end

function items.yellowkey()
    keyShape({0.90, 0.78, 0.18})
end

function items.silencer()
    rect(18, 44, 28, 10, {0.16, 0.17, 0.19})
    rect(18, 44, 28, 2, {0.30, 0.31, 0.34})
    for x = 22, 42, 6 do
        rect(x, 44, 2, 10, {0.10, 0.10, 0.12})
    end
    rect(44, 46, 6, 6, {0.26, 0.27, 0.30})
end

-- A leg trap: folded shut it is a thing you carry, open it is a thing you
-- hope somebody walks into.
local function trapShape(open, sprung)
    local steel = {0.38, 0.39, 0.42}
    local dark = {0.22, 0.23, 0.25}
    local light = {0.54, 0.56, 0.60}

    if open then
        disc(32, 50, 15, {0, 0, 0, 0.25})
        disc(32, 50, 11, dark)
        disc(32, 50, 7, {0.10, 0.10, 0.11})
        for i = 0, 7 do
            local a = i / 8 * math.pi * 2
            local x = 32 + math.cos(a) * 12
            local y = 50 + math.sin(a) * 7
            poly(steel, x - 2, y, x + 2, y, x, y - 7)
        end

        rect(30, 44, 4, 3, light)
        rect(16, 54, 32, 3, dark)

        return
    end

    if sprung then
        disc(32, 50, 13, {0, 0, 0, 0.25})
        rect(18, 44, 28, 10, dark)
        rect(18, 44, 28, 2, light)
        for i = 0, 5 do
            poly(steel, 20 + i * 5, 44, 23 + i * 5, 44, 21 + i * 5, 38)
        end

        disc(26, 49, 4, {0.42, 0.06, 0.07, 0.8})
        disc(38, 52, 3, {0.36, 0.05, 0.06, 0.7})

        return
    end

    rect(18, 42, 28, 14, steel)
    rect(18, 42, 28, 3, light)
    rect(18, 53, 28, 3, dark)
    rect(24, 38, 16, 5, dark)
    for x = 21, 43, 6 do
        rect(x, 45, 3, 8, dark)
    end
end

function items.trap()
    trapShape(false, false)
end

function items.trapset()
    trapShape(true, false)
end

function items.trapsprung()
    trapShape(false, true)
end

function items.knife()
    rect(14, 46, 14, 7, {0.28, 0.20, 0.13})
    rect(14, 46, 14, 2, {0.40, 0.29, 0.18})
    rect(27, 44, 3, 11, {0.46, 0.47, 0.50})
    poly({0.74, 0.76, 0.80}, 30, 45, 48, 48, 30, 53)
    poly({0.90, 0.92, 0.95}, 30, 45, 48, 48, 32, 49)
end

art.ITEM_ORDER = {"uzi", "launcher", "grenades", "flashes", "bullets", "clips",
    "ammobox", "rockets", "vest", "vestheavy", "medkit", "snack", "silencer",
    "redkey", "bluekey", "yellowkey", "knife", "trap", "trapset", "trapsprung"}

-- What is left in the old cells. Every prop stands on the floor of its tile,
-- so a cell is drawn with the ground at the bottom edge and nothing is ever
-- taller than the wall behind it.
local BONE = {0.80, 0.78, 0.70}
local BONE_DARK = {0.58, 0.56, 0.50}
local GORE = {0.36, 0.06, 0.07, 0.80}
local GORE_THIN = {0.30, 0.05, 0.06, 0.50}
local IRON = {0.34, 0.35, 0.38}
local ROPE = {0.52, 0.44, 0.30}
local CON_SKIN = {0.70, 0.56, 0.46}
local CON_SHIRT = {0.56, 0.55, 0.52}
local CON_STRIPE = {0.38, 0.38, 0.40}
local CON_TROUSER = {0.40, 0.40, 0.42}

local props = {}

-- Chained to the wall and left there. The shackles still hold the wrists up
-- while the rest of him has come apart on the floor.
function props.skeleton()
    disc(32, 59, 11, {0, 0, 0, 0.22})
    disc(32, 58, 8, GORE_THIN)

    for _, wx in ipairs({24, 40}) do
        rect(wx - 1, 0, 3, 13, IRON)
        rect(wx, 0, 1, 13, tint(IRON, 1.4))
        rect(wx - 4, 12, 9, 5, tint(IRON, 0.8))
        rect(wx - 4, 13, 9, 1, tint(IRON, 1.3))
    end

    -- arms hanging from the shackles down to the shoulders
    poly(BONE, 23, 17, 26, 17, 28, 38, 26, 39)
    poly(BONE, 41, 17, 38, 17, 36, 38, 38, 39)
    disc(27, 39, 3, BONE_DARK)
    disc(37, 39, 3, BONE_DARK)

    -- ribs and spine, slumped forward over the pelvis
    rect(31, 38, 3, 17, BONE_DARK)
    for i = 0, 4 do
        rect(26, 40 + i * 3, 12, 2, BONE)
        rect(26, 41 + i * 3, 12, 1, BONE_DARK)
    end

    rect(27, 54, 11, 5, BONE)
    rect(27, 57, 11, 2, BONE_DARK)

    -- legs folded out along the floor
    poly(BONE, 28, 56, 30, 59, 17, 61, 16, 58)
    poly(BONE, 37, 56, 35, 59, 48, 61, 49, 58)
    disc(16, 59, 3, BONE_DARK)
    disc(49, 59, 3, BONE_DARK)

    -- the skull, chin on the chest
    disc(32, 32, 7, BONE)
    rect(28, 35, 8, 4, BONE_DARK)
    rect(28, 30, 4, 4, {0.10, 0.09, 0.09})
    rect(34, 30, 4, 4, {0.10, 0.09, 0.09})
    rect(31, 34, 2, 2, {0.12, 0.11, 0.11})
end

-- A man who found his own way out, and the stool he kicked over.
function props.hanged()
    rect(31, 0, 2, 11, ROPE)
    rect(32, 0, 1, 11, tint(ROPE, 1.3))
    rect(28, 10, 8, 4, tint(ROPE, 0.85))
    rect(30, 13, 4, 3, ROPE)

    lg.push()
    lg.translate(32, 22)
    lg.rotate(0.13)
    lg.translate(-32, -30)

    disc(32, 25, 6, CON_SKIN)
    rect(27, 19, 10, 3, {0.26, 0.22, 0.20})
    rect(29, 24, 2, 2, {0.10, 0.09, 0.09})
    rect(34, 24, 2, 2, {0.10, 0.09, 0.09})

    poly(CON_SHIRT, 23, 31, 41, 31, 38, 47, 26, 47)
    for i = 0, 2 do
        rect(24, 33 + i * 4, 16, 2, CON_STRIPE)
    end

    rect(20, 31, 4, 15, tint(CON_SHIRT, 0.9))
    rect(40, 31, 4, 15, tint(CON_SHIRT, 0.8))
    disc(22, 47, 3, CON_SKIN)
    disc(42, 47, 3, CON_SKIN)

    rect(26, 46, 5, 12, CON_TROUSER)
    rect(33, 46, 5, 12, tint(CON_TROUSER, 0.85))
    disc(28, 58, 3, {0.70, 0.56, 0.46})
    disc(35, 58, 3, {0.62, 0.50, 0.41})

    lg.pop()

    rect(12, 56, 13, 4, {0.36, 0.28, 0.18})
    rect(13, 59, 3, 4, {0.28, 0.21, 0.13})
    rect(21, 59, 3, 4, {0.28, 0.21, 0.13})
end

-- Somebody who did not make it, face down where he fell.
function props.body()
    disc(28, 56, 14, GORE)
    disc(44, 58, 8, GORE_THIN)
    disc(18, 59, 6, GORE_THIN)

    rect(22, 46, 22, 11, CON_SHIRT)
    for i = 0, 2 do
        rect(22, 48 + i * 3, 22, 2, CON_STRIPE)
    end

    rect(42, 49, 15, 8, CON_TROUSER)
    rect(55, 50, 6, 6, {0.14, 0.13, 0.12})
    disc(17, 50, 6, CON_SKIN)
    rect(13, 45, 9, 3, {0.26, 0.22, 0.20})
    poly(tint(CON_SHIRT, 0.9), 26, 44, 34, 42, 36, 46, 28, 48)
    disc(35, 42, 3, CON_SKIN)
end

-- And somebody the riot squad got to first.
function props.remains()
    disc(32, 56, 17, GORE)
    disc(16, 59, 8, GORE_THIN)
    disc(48, 58, 9, GORE_THIN)
    disc(38, 50, 5, GORE_THIN)

    rect(12, 50, 14, 5, CON_SKIN)
    rect(24, 50, 4, 5, {0.42, 0.06, 0.07})
    disc(12, 52, 3, CON_SKIN)

    rect(40, 53, 13, 6, CON_TROUSER)
    rect(51, 53, 7, 6, {0.14, 0.13, 0.12})
    rect(38, 53, 4, 6, {0.42, 0.06, 0.07})

    rect(29, 44, 9, 2, BONE)
    rect(29, 47, 9, 2, BONE_DARK)
    rect(32, 43, 2, 7, BONE_DARK)
    disc(27, 57, 4, {0.46, 0.08, 0.09, 0.9})
    disc(36, 59, 3, {0.46, 0.08, 0.09, 0.9})
end

-- Dried blood on the floor, on its own with nobody left beside it. It cannot
-- live in the floor texture: that one tile is painted on the whole block, so
-- a stain in the file would run the length of every corridor. The world lays
-- these down tile by tile instead.
--
-- This one is painted into the ground rather than stood up in it, so it fills
-- its cell instead of sitting along the bottom edge the way a billboard does.
function props.stain()
    disc(31, 31, 20, GORE_THIN)
    disc(45, 40, 12, GORE_THIN)
    disc(18, 41, 10, GORE_THIN)
    disc(32, 33, 13, GORE)
    disc(41, 44, 7, GORE)
    disc(23, 45, 6, GORE)

    -- the spots that flew out of it and dried on their own
    for _, p in ipairs({{8, 24, 2}, {56, 28, 2}, {50, 14, 1}, {13, 54, 2},
        {58, 50, 1}, {37, 10, 1}}) do
        disc(p[1], p[2], p[3], GORE_THIN)
    end
end

art.PROP_ORDER = {"skeleton", "hanged", "body", "remains", "stain"}

-- The guard on your cell floor, which is where the hatchet, the revolver and
-- the vest came from. Drawn from the sergeant's own dead frame so it is the
-- same man you see walking about everywhere else.
local function deadGuard()
    disc(30, 58, 9, {0.34, 0.06, 0.07, 0.75})
    disc(40, 59, 6, {0.28, 0.04, 0.05, 0.6})
    guardFrame(art.TIERS[2], "dead")
end

-- The dogs. Drawn side on, because a dog coming at you is mostly teeth and
-- the shape only reads from the side.
local DOG = {0.26, 0.21, 0.17}
local DOG_LO = {0.17, 0.14, 0.11}
local DOG_HI = {0.34, 0.28, 0.22}

local function dogFrame(frame)
    local bite = frame == "bite"
    local down = frame == "dead"

    if down then
        disc(32, 56, 16, {0, 0, 0, 0.30})
        rect(14, 48, 34, 10, DOG)
        rect(44, 50, 12, 8, DOG_LO)
        disc(54, 52, 5, DOG)
        rect(16, 44, 6, 6, DOG_LO)
        rect(30, 44, 6, 6, DOG_LO)
        disc(26, 58, 8, {0.34, 0.05, 0.06, 0.7})

        return
    end

    local swing = (frame == "walk2") and -3 or 3

    disc(32, 58, 13, {0, 0, 0, 0.26})

    -- tail, body, haunches
    poly(DOG, 12, 34, 18, 32, 20, 42, 14, 44)
    rect(16, 36, 30, 14, DOG)
    rect(16, 36, 30, 3, DOG_HI)
    disc(20, 43, 8, DOG)

    -- legs
    rect(18 + swing, 48, 5, 11, DOG_LO)
    rect(26 - swing, 48, 5, 11, DOG_LO)
    rect(36 + swing, 48, 5, 11, DOG_LO)
    rect(42 - swing, 48, 5, 11, DOG_LO)

    -- neck and head, low and forward
    poly(DOG, 42, 34, 49, 30, 53, 40, 44, 44)
    disc(49, 36, 7, DOG)
    poly(DOG_HI, 46, 26, 50, 26, 48, 33)
    poly(DOG_HI, 51, 27, 55, 28, 52, 34)
    rect(53, 36, 9, 5, DOG_LO)
    rect(60, 36, 2, 2, {0.08, 0.07, 0.07})
    rect(46, 33, 3, 2, {0.86, 0.78, 0.30})

    if bite then
        -- jaws open: a dark wedge with the mouth in it and two fangs
        poly(DOG_LO, 52, 31, 63, 28, 63, 35, 53, 37)
        poly(DOG_LO, 53, 39, 63, 46, 63, 40, 52, 38)
        poly({0.42, 0.11, 0.13}, 54, 36, 62, 35, 62, 40, 54, 38)
        poly({0.94, 0.92, 0.86}, 56, 34, 59, 34, 58, 39)
        poly({0.94, 0.92, 0.86}, 60, 39, 62, 39, 61, 35)
    elseif frame == "pain" then
        lg.setColor(0.75, 0.10, 0.10, 0.45)
        lg.rectangle("fill", 14, 30, 46, 26)
    end
end

art.DOG_FRAMES = {"walk1", "walk2", "bite", "pain", "dead"}

-- Everything the animation code can ask for, pointed at the five it has. Each
-- of these gets a cell of its own on the sheet, drawn with the frame it names,
-- so it can be replaced on its own from assets/sprites.
art.DOG_ALIAS = {
    idle = "walk1",
    walk3 = "walk1",
    walk4 = "walk2",
    aim = "bite",
    fire = "bite",
    sleep = "walk1",
    die1 = "dead",
    die2 = "dead",
    die3 = "dead",
}

-- The prisoners who are still alive. Same build as a guard so they read as
-- people at a glance, in cell clothes and with nothing but their hands.
local CON = {
    skin = CON_SKIN,
    shirt = CON_SHIRT,
    trouser = CON_TROUSER,
    boot = {0.30, 0.28, 0.26},
    bulk = 0.92,
}

local function conFigure(frame)
    local cx = 32
    local swing = 0
    local lean = 0

    if frame == "walk1" then
        swing = 4
    elseif frame == "walk2" then
        swing = -4
    elseif frame == "pain" then
        lean = -3
    end

    if frame == "dead" or frame == "die1" then
        local step = frame == "dead" and 1 or 0.5
        lg.push()
        lg.translate(cx, 58)
        lg.rotate(step * 1.45)
        lg.translate(-cx, -58)
    end

    disc(cx, 60, 10 * CON.bulk, {0, 0, 0, 0.32})
    legs(CON, cx, swing)

    poly(CON.shirt,
        cx - 12 + lean, 22, cx + 12 + lean, 22, cx + 8, 40, cx - 8, 40)
    for i = 0, 3 do
        rect(cx - 12 + lean + i, 25 + i * 4, 24 - i * 2, 2, CON_STRIPE)
    end

    if frame == "hit" then
        -- a swing that comes from the shoulder, because it is all he has
        rect(cx + 6, 16, 6, 16, tint(CON.shirt, 0.85))
        disc(cx + 12, 14, 4, CON.skin)
        rect(cx - 14, 26, 6, 14, tint(CON.shirt, 0.9))
        disc(cx - 14, 40, 3, CON.skin)
    else
        rect(cx - 15 - swing, 23, 5, 17, tint(CON.shirt, 0.9))
        rect(cx + 10 + swing, 23, 5, 17, tint(CON.shirt, 0.8))
        disc(cx - 13 - swing, 41, 3, CON.skin)
        disc(cx + 13 + swing, 41, 3, CON.skin)
    end

    local hx = cx + lean
    disc(hx, 14, 7, CON.skin)
    rect(hx - 6, 7, 12, 3, {0.26, 0.22, 0.20})
    rect(hx - 4, 12, 2, 2, {0.10, 0.09, 0.09})
    rect(hx + 2, 12, 2, 2, {0.10, 0.09, 0.09})

    if frame == "pain" then
        lg.setColor(0.75, 0.10, 0.10, 0.45)
        lg.rectangle("fill", 16, 12, 32, 44)
    end

    if frame == "dead" or frame == "die1" then
        lg.pop()
        disc(30, 58, 8, GORE_THIN)
    end
end

art.CON_FRAMES = {"idle", "walk1", "walk2", "hit", "pain", "die1", "dead"}

-- End over end, so it reads as a blade and not as a bullet.
local function flyingKnife()
    rect(10, 29, 26, 6, {0.78, 0.80, 0.84})
    rect(10, 29, 26, 2, {0.94, 0.95, 0.97})
    poly({0.86, 0.88, 0.92}, 36, 29, 50, 32, 36, 35)
    rect(2, 28, 9, 8, {0.28, 0.20, 0.13})
    rect(2, 28, 9, 2, {0.40, 0.29, 0.18})
end

local function thrownGrenade()
    disc(32, 32, 7, {0.26, 0.34, 0.20})
    disc(29, 29, 3, {0.38, 0.48, 0.28})
    rect(29, 23, 6, 4, {0.40, 0.40, 0.42})
end

local function thrownFlash()
    rect(26, 24, 12, 18, {0.46, 0.47, 0.50})
    rect(26, 30, 12, 5, {0.94, 0.94, 0.90})
    rect(26, 37, 12, 2, {0.82, 0.72, 0.20})
end

local function flyingRocket()
    rect(26, 26, 14, 9, {0.32, 0.35, 0.30})
    poly({0.64, 0.22, 0.16}, 40, 26, 50, 30.5, 40, 35)
    poly({0.26, 0.28, 0.24}, 26, 26, 20, 22, 20, 39, 26, 35)
    disc(20, 30.5, 5, {1, 0.80, 0.30, 0.9})
    disc(14, 30.5, 4, {1, 0.52, 0.14, 0.7})
    disc(8, 30.5, 3, {0.9, 0.35, 0.10, 0.4})
end

local function fireball(step)
    local r = 10 + step * 20
    disc(32, 34, r, {1, 0.42, 0.10, 0.85 - step * 0.3})
    disc(32 - step * 4, 32 - step * 6, r * 0.7, {1, 0.72, 0.22, 0.9 - step * 0.35})
    disc(32 + step * 6, 30 - step * 10, r * 0.45, {1, 0.92, 0.60, 0.95 - step * 0.5})
    for i = 1, 6 do
        local a = i * 1.047 + step * 2
        disc(32 + math.cos(a) * r * 0.9, 34 + math.sin(a) * r * 0.7, 5 - step * 3,
            {0.35, 0.30, 0.28, 0.5 - step * 0.3})
    end
end

local function flashPop()
    disc(32, 32, 30, {1, 1, 0.96, 0.9})
    disc(32, 32, 20, {1, 1, 1, 1})
end

local function blob(c)
    disc(32, 32, 10, c)
    disc(27, 28, 5, {c[1] * 1.3, c[2] * 1.3, c[3] * 1.3, c[4]})
end


-- The weapon in your hands, drawn twice. Everything from here down to
-- art.VIEW_ORDER is the fallback, used for whatever has no file in
-- assets/views, and tools/weapons.py writes the files that take its place.
-- The two have to be changed together or the game stops looking the same with
-- an empty assets folder, which is the one thing the fallback is for.
art.VIEW_W = 400
art.VIEW_H = 300

-- Same arrangement as the sprites: the builders below are written against the
-- 200 by 150 the view used to be, and the sheet is painted at twice that.
local VIEW_GRID_W = 200
local VIEW_SCALE = art.VIEW_W / VIEW_GRID_W

-- How wide the sheet is packed, in frames. Not a limit on a weapon's frames:
-- the 42 of them are laid out end to end and wrapped, because a row for every
-- weapon at ten frames wide would be a 4000 pixel texture and some cards
-- still stop at 4096.
art.VIEW_PACK = 7

local views = {}

local SKIN = {0.78, 0.60, 0.46}
local SKIN_LO = {0.62, 0.46, 0.34}
local CUFF = {0.50, 0.52, 0.56}
local BLOOD = {0.58, 0.05, 0.06}
local GUN = {0.26, 0.27, 0.30}
local GUN_HI = {0.42, 0.44, 0.48}
local GUN_LO = {0.15, 0.15, 0.17}
local WOOD = {0.32, 0.21, 0.13}

local HOLD_X, HOLD_Y, HOLD_S = 112, 132, 0.78

-- A view model is drawn the way the player sees it: hands at the bottom of the
-- cell, barrel running up the screen and narrowing towards the horizon.
local function held(lift, draw)
    lg.push()
    lg.translate(HOLD_X, HOLD_Y + (lift or 0))
    lg.scale(HOLD_S, HOLD_S)
    draw()
    lg.pop()
end

local function tube(cx, yTop, wTop, yBot, wBot, c)
    poly(c, cx - wTop * 0.5, yTop, cx + wTop * 0.5, yTop,
        cx + wBot * 0.5, yBot, cx - wBot * 0.5, yBot)
end

local SKIN_HI = {0.88, 0.71, 0.56}
local FINGERS = {22, 26, 25, 21}

-- One finger round the front of the grip: a bar with the knuckle end rounded
-- off on the left, a lit top edge and the crease of the next one under it.
local function finger(x, y, w, h, base, shade)
    rect(x, y, w, h, base)
    disc(x, y + h * 0.5, h * 0.5, base)
    rect(x, y, w, 2, SKIN_HI)
    rect(x - 1, y + h - 2, w + 1, 2, shade)
end

-- One hand on the weapon, the right, seen from behind and a little above.
-- The other one is busy with doors, lockers and the man on the floor.
local function fists(spread)
    local hx = 2 + (spread or 0) * 0.5
    local cy = -8

    rect(hx - 4, cy - 30, 26, 42, SKIN)
    rect(hx + 16, cy - 30, 6, 42, SKIN_HI)
    disc(hx + 9, cy - 30, 13, SKIN)
    rect(hx + 2, cy - 24, 2, 20, SKIN_HI)
    rect(hx + 8, cy - 22, 2, 17, SKIN_HI)

    for i, w in ipairs(FINGERS) do
        finger(hx - 18, cy - 28 + (i - 1) * 9, w, 8, SKIN, SKIN_LO)
    end

    -- the thumb, over the top of them and pointing in
    poly(SKIN_HI, hx + 20, cy - 28, hx + 12, cy - 38, hx - 2, cy - 38,
        hx - 6, cy - 30, hx + 6, cy - 24, hx + 18, cy - 22)
    poly(SKIN, hx + 10, cy - 36, hx - 2, cy - 35, hx - 4, cy - 30,
        hx + 8, cy - 29)

    rect(hx - 6, cy + 6, 28, 12, SKIN_LO)
    rect(hx - 8, cy + 14, 32, 15, CUFF)
    rect(hx - 8, cy + 14, 32, 3, {0.62, 0.64, 0.68})
end

-- The left hand, the one the comment above says is busy with doors and
-- lockers and the man on the floor. It only comes up for a reload, so it is
-- drawn on its own: the back of it towards us and the fingers closed round
-- whatever it has hold of.
local function offHand(x, y, rot, s)
    lg.push()
    lg.translate(x, y)
    lg.rotate(rot or 0)
    lg.scale(s or 1, s or 1)

    rect(-16, -12, 32, 30, SKIN)
    rect(-16, -12, 32, 3, SKIN_HI)
    disc(0, 16, 16, SKIN)

    for i = 0, 3 do
        finger(-20, -14 + i * 9, 22, 8, SKIN, SKIN_LO)
    end

    poly(SKIN_HI, 16, -10, 24, -4, 24, 8, 14, 10)
    rect(-16, 22, 32, 14, CUFF)
    rect(-16, 22, 32, 3, {0.62, 0.64, 0.68})

    lg.pop()
end

local function muzzleFlash(x, y, s, quiet)
    if quiet then
        disc(x, y, 7 * s, {1, 0.92, 0.62, 0.45})
        disc(x, y - 6 * s, 11 * s, {0.58, 0.57, 0.54, 0.28})

        return
    end

    disc(x, y, 12 * s, {1, 0.94, 0.62, 0.95})
    disc(x, y - 8 * s, 17 * s, {1, 0.68, 0.18, 0.6})
    poly({1, 0.88, 0.42, 0.75},
        x - 20 * s, y + 4 * s, x, y - 28 * s, x + 20 * s, y + 4 * s, x, y + 13 * s)
end

local function hatchetBody(rot, s)
    lg.push()
    lg.rotate(rot)
    lg.scale(s or 1, s or 1)
    rect(-7, -96, 14, 98, WOOD)
    rect(-7, -96, 4, 98, {0.46, 0.31, 0.18})
    poly({0.60, 0.62, 0.66}, -8, -96, 24, -106, 32, -82, -8, -74)
    poly({0.88, 0.90, 0.94}, 22, -104, 32, -82, 27, -79, 17, -100)
    rect(-10, -26, 20, 18, {0.20, 0.20, 0.22})
    lg.pop()
end

function views.hatchet(frame)
    local fire = frame == 2

    held(fire and -4 or 0, function()
        lg.push()
        lg.translate(fire and -30 or 14, 0)
        hatchetBody(fire and 0.95 or 0.3)
        lg.pop()
        fists(2)
    end)
end

-- One body for every frame of the gun, so the cylinder cannot drift between
-- the one you fire and the one you reload. `hollow` is the frame it has swung
-- out of.
local function revolverBody(sil, hollow)
    poly(WOOD, -15, -2, 15, -2, 11, -42, -9, -42)
    poly({0.40, 0.27, 0.17}, -15, -2, -7, -2, -5, -42, -9, -42)
    rect(-17, -60, 34, 20, GUN)
    rect(-17, -60, 34, 3, GUN_HI)
    disc(-3, -43, 8, GUN_LO)
    rect(-14, -80, 28, 22, {0.31, 0.32, 0.35})
    rect(-14, -80, 28, 2, GUN_HI)

    if hollow then
        rect(-11, -78, 22, 18, {0.07, 0.07, 0.08})
    else
        disc(0, -69, 9, {0.22, 0.22, 0.25})
        disc(0, -69, 3, {0.07, 0.07, 0.08})
    end

    tube(0, -122, 14, -78, 20, GUN)
    tube(-5, -120, 3, -78, 4, GUN_HI)
    rect(-4, -126, 8, 6, GUN_LO)

    if sil then
        tube(0, -132, 22, -86, 28, {0.15, 0.16, 0.18})
        tube(-7, -130, 4, -86, 5, {0.26, 0.27, 0.30})
        for i = 0, 3 do
            rect(-11, -124 + i * 10, 22, 3, {0.09, 0.09, 0.11})
        end
    end
end

-- The cylinder out on its crane, chambers towards us. `loaded` is how many of
-- the six have a round in them.
local function revolverCylinder(x, y, loaded)
    lg.push()
    lg.translate(x, y)
    rect(6, -3, 16, 6, GUN_LO)
    disc(0, 0, 13, {0.38, 0.39, 0.42})
    disc(0, 0, 11, {0.30, 0.31, 0.34})

    for i = 0, 5 do
        local a = i / 6 * math.pi * 2
        disc(math.cos(a) * 7, math.sin(a) * 7, 3.4,
            i < loaded and BRASS or {0.06, 0.06, 0.07})
    end

    disc(0, 0, 2.5, GUN_HI)
    lg.pop()
end

-- Six rounds in a ring, which is the only way anybody reloads one of these
-- with a man coming down the corridor.
local function speedloader(x, y)
    lg.push()
    lg.translate(x, y)
    disc(0, 0, 12, {0.24, 0.24, 0.26})

    for i = 0, 5 do
        local a = i / 6 * math.pi * 2
        disc(math.cos(a) * 7, math.sin(a) * 7, 3.4, BRASS)
    end

    disc(0, 0, 3, {0.40, 0.42, 0.46})
    lg.pop()
end

-- The three frames of a reload: the cylinder out with the empties still in
-- it, the loader pushed up into it, and the gun rolling back upright. Which
-- one is on screen comes off Player:reloadStage, so they follow the weapon's
-- own reload time instead of a clock of their own.
local function revolverReload(step, sil)
    local roll = ({0.40, 0.44, 0.16})[step + 1]

    held(({4, 8, 1})[step + 1], function()
        lg.push()
        lg.rotate(roll)

        if step == 1 then
            speedloader(-28, -54)
        end

        revolverBody(sil, step < 2)

        if step == 0 then
            revolverCylinder(-28, -66, 0)
            speedloader(-48, -34)
            offHand(-52, -6, -0.2, 0.8)
        elseif step == 1 then
            revolverCylinder(-28, -66, 6)
            offHand(-46, -22, -0.25, 0.8)
        end

        fists(0)
        lg.pop()
    end)
end

function views.revolver(frame)
    if frame >= 5 then
        return revolverReload((frame - 5) % 3, frame >= 8)
    end

    local fire = frame == 2 or frame == 4
    local sil = frame >= 3

    held(fire and -5 or 0, function()
        revolverBody(sil, false)

        if fire then
            muzzleFlash(0, sil and -134 or -126, 1, sil)
        end

        fists(0)
    end)
end

-- The magazine goes through the grip on one of these, so `mag` is the
-- difference between a gun you can fire and one you cannot.
local function uziBody(sil, mag)
    poly({0.13, 0.13, 0.15}, -26, -2, -4, -7, 0, -46, -22, -42)

    if mag then
        poly({0.19, 0.19, 0.21}, -24, -4, -6, -8, -2, -46, -20, -42)
    else
        poly({0.05, 0.05, 0.06}, -23, -8, -7, -12, -4, -44, -20, -40)
    end

    rect(-18, -74, 36, 30, {0.23, 0.23, 0.26})
    rect(-18, -74, 36, 3, GUN_HI)
    rect(-18, -56, 36, 2, GUN_LO)
    rect(14, -70, 8, 10, {0.17, 0.17, 0.19})
    disc(-2, -50, 7, GUN_LO)
    tube(0, -116, 13, -72, 18, GUN)
    tube(-4, -114, 3, -72, 4, GUN_HI)
    rect(-5, -120, 10, 5, GUN_LO)

    if sil then
        tube(0, -130, 22, -80, 26, {0.15, 0.16, 0.18})
        for i = 0, 3 do
            rect(-11, -122 + i * 11, 22, 3, {0.09, 0.09, 0.11})
        end
    end
end

-- A magazine on its own, top end at the origin, for the one coming out and
-- the one going in.
local function uziMag(x, y, rot)
    lg.push()
    lg.translate(x, y)
    lg.rotate(rot or 0)
    poly({0.19, 0.19, 0.21}, -9, 0, 9, 0, 11, 42, -7, 42)
    poly({0.27, 0.27, 0.30}, -9, 0, -3, 0, -5, 42, -7, 42)
    rect(-8, 1, 16, 4, BRASS)
    rect(-8, 1, 16, 1, {0.86, 0.72, 0.30})
    lg.pop()
end

-- Out, in, and the bolt back: the same three steps the revolver gets, on the
-- uzi's own 1.55 seconds.
local function uziReload(step, sil)
    held(({5, 9, 2})[step + 1], function()
        if step == 2 then
            uziBody(sil, true)
            rect(-14, -80, 18, 6, GUN_HI)
            offHand(-24, -62, -0.3, 0.7)
        else
            uziBody(sil, false)

            if step == 0 then
                uziMag(-46, -12, 0.8)
                offHand(-34, -36, 0.1, 0.72)
            else
                uziMag(-40, -22, 0.18)
                offHand(-46, 12, 0.14, 0.8)
            end
        end

        fists(4)
    end)
end

function views.uzi(frame)
    if frame >= 5 then
        return uziReload((frame - 5) % 3, frame >= 8)
    end

    local fire = frame == 2 or frame == 4
    local sil = frame >= 3

    held(fire and -4 or 0, function()
        uziBody(sil, true)

        if fire then
            muzzleFlash(0, sil and -132 or -122, 0.9, sil)
            if not sil then
                disc(22, -106, 7, {0.56, 0.56, 0.58, 0.3})
            end
        end

        fists(4)
    end)
end

function views.launcher(frame)
    local fire = frame == 2

    held(fire and -6 or 0, function()
        tube(0, -120, 30, -22, 50, {0.27, 0.31, 0.26})
        tube(-13, -118, 5, -22, 9, {0.40, 0.45, 0.38})
        tube(13, -118, 4, -22, 7, {0.17, 0.20, 0.16})
        disc(0, -22, 25, {0.21, 0.24, 0.20})
        disc(0, -22, 16, {0.07, 0.08, 0.07})
        rect(-32, -96, 15, 12, {0.23, 0.26, 0.21})
        rect(-28, -112, 5, 18, {0.31, 0.34, 0.29})
        rect(-16, -126, 32, 7, {0.22, 0.25, 0.21})

        if fire then
            muzzleFlash(0, -130, 1.4)
            disc(-30, -4, 18, {0.56, 0.56, 0.58, 0.4})
            disc(26, 2, 20, {0.50, 0.50, 0.52, 0.3})
        end

        fists(6)
    end)
end

local function thrower(frame, ball)
    held(0, function()
        if frame == 2 then
            -- the arm gone out after it, open hand at the end of the throw
            rect(-14, -138, 28, 92, SKIN)
            rect(8, -138, 6, 92, SKIN_HI)
            rect(-14, -66, 28, 16, CUFF)
            rect(-14, -152, 28, 20, SKIN)
            disc(10, -148, 12, SKIN)

            for i, w in ipairs({24, 26, 23}) do
                finger(-16, -158 + (i - 1) * 9, w, 8, SKIN, SKIN_LO)
            end

            poly(SKIN_HI, 12, -154, 4, -164, -8, -162, -6, -154, 6, -150)

            return
        end

        lg.push()
        lg.translate(0, -58)
        ball()
        lg.pop()

        -- the hand closed round it, fingers curled over the front
        rect(-14, -36, 28, 46, SKIN)
        rect(8, -36, 6, 46, SKIN_HI)
        disc(0, -36, 14, SKIN)

        for i, w in ipairs({24, 27, 26, 22}) do
            finger(-16, -40 + (i - 1) * 9, w, 8, SKIN, SKIN_LO)
        end

        poly(SKIN_HI, 14, -38, 6, -48, -6, -47, -8, -39, 4, -33)
        rect(-6, -44, 8, 3, SKIN)
        rect(-16, 6, 32, 14, CUFF)
    end)
end

function views.grenades(frame)
    thrower(frame, function()
        disc(0, 0, 20, {0.26, 0.34, 0.20})
        disc(-7, -7, 9, {0.38, 0.48, 0.28})
        rect(-7, -32, 14, 11, {0.40, 0.40, 0.42})
        disc(13, -29, 7, {0.56, 0.56, 0.60})
    end)
end

function views.knife(frame)
    thrower(frame, function()
        rect(-5, -4, 10, 26, {0.28, 0.20, 0.13})
        rect(-5, -4, 4, 26, {0.40, 0.29, 0.18})
        rect(-9, -8, 18, 5, {0.46, 0.47, 0.50})
        poly({0.76, 0.78, 0.82}, -6, -10, 6, -10, 2, -60, -2, -60)
        poly({0.94, 0.95, 0.97}, -6, -10, -2, -10, -2, -58)
    end)
end

function views.flashes(frame)
    thrower(frame, function()
        rect(-14, -30, 28, 44, {0.46, 0.47, 0.50})
        rect(-14, -16, 28, 11, {0.94, 0.94, 0.90})
        rect(-14, -1, 28, 6, {0.82, 0.72, 0.20})
        rect(-7, -38, 14, 9, {0.30, 0.31, 0.33})
    end)
end

local function splatter(n, sx, sy, spread, size)
    for i = 1, n do
        local a = (i / n) * math.pi * 2
        local r = spread * (0.3 + (i % 3) * 0.3)
        disc(sx + math.cos(a) * r, sy + math.sin(a) * r * 0.6,
            size * (0.4 + (i % 4) * 0.25), {BLOOD[1], BLOOD[2], BLOOD[3], 0.85})
    end
end

local function hatchetAt(x, y, rot, s)
    lg.push()
    lg.translate(x, y)
    hatchetBody(rot, s)
    lg.pop()
end

-- The three executions, four frames each, drawn in the same cell as a weapon:
-- the guard seen from behind, filling the lower half of the view.
local function victim(sink, lean, slump)
    lg.push()
    lg.translate(100, 88 + (sink or 0))
    lg.scale(1, 1)

    poly({0.24, 0.27, 0.36}, -56, 0, 56, 0, 66, 62, -66, 62)
    rect(-56, 0, 112, 7, {0.30, 0.33, 0.44})
    rect(-30, 22, 60, 4, {0.18, 0.20, 0.27})

    lg.push()
    lg.translate(0, 2)
    lg.rotate(lean or 0)
    rect(-15, -26, 30, 30, {0.72, 0.54, 0.42})
    rect(-15, -26, 30, 6, {0.58, 0.42, 0.33})
    disc(0, -48, 30, {0.52, 0.38, 0.29})
    disc(0, -50, 28, {0.76, 0.58, 0.45})
    disc(0, -57, 29, {0.17, 0.20, 0.31})
    disc(0, -59, 26, {0.22, 0.26, 0.38})
    disc(-27, -46, 7, {0.64, 0.47, 0.36})
    disc(27, -46, 7, {0.64, 0.47, 0.36})
    rect(-31, -60, 62, 6, {0.12, 0.14, 0.22})

    if slump then
        rect(-20, -34, 40, 10, {0.45, 0.06, 0.07, 0.8})
    end

    lg.pop()
    lg.pop()
end

local function gripHand(x, y, rot, s)
    lg.push()
    lg.translate(x, y)
    lg.rotate(rot)
    lg.scale(s or 1, s or 1)
    rect(-20, 0, 40, 64, {0.42, 0.30, 0.22})
    disc(0, 0, 19, {0.42, 0.30, 0.22})
    rect(-18, 2, 36, 60, {0.88, 0.70, 0.55})
    rect(-18, 48, 36, 14, CUFF)
    disc(0, 0, 17, {0.88, 0.70, 0.55})
    for i = 0, 2 do
        rect(-16, -12 + i * 9, 32, 6, {0.68, 0.50, 0.38})
    end
    lg.pop()
end

function views.throat(frame)
    local lean = ({-0.05, -0.18, -0.26, -0.36})[frame]
    victim((frame - 1) * 3, lean, frame >= 3)
    gripHand(58 - frame * 2, 52, 1.95 - frame * 0.07, 0.8)

    if frame == 1 then
        hatchetAt(188, 148, 0.35, 0.85)
    elseif frame == 2 then
        hatchetAt(236, 72, -1.45, 0.85)
        splatter(4, 150, 68, 10, 4)
    elseif frame == 3 then
        hatchetAt(186, 70, -1.55, 0.85)
        splatter(13, 104, 66, 30, 7)
    else
        hatchetAt(132, 66, -1.7, 0.85)
        splatter(18, 92, 72, 42, 9)
        rect(44, 86, 112, 10, {BLOOD[1], BLOOD[2], BLOOD[3], 0.6})
    end
end

function views.head(frame)
    victim((frame - 1) * 5, 0.04 * frame, frame >= 3)

    if frame == 1 then
        hatchetAt(170, 56, -2.5, 0.95)
    elseif frame == 2 then
        hatchetAt(142, 26, -1.5, 0.95)
    elseif frame == 3 then
        hatchetAt(104, 22, -0.25, 0.95)
        splatter(12, 100, 42, 26, 7)
    else
        hatchetAt(112, 34, -0.6, 0.95)
        splatter(18, 100, 52, 38, 9)
        rect(56, 58, 92, 8, {BLOOD[1], BLOOD[2], BLOOD[3], 0.55})
    end

    gripHand(178, 112, -0.45, 0.8)
end

function views.neck(frame)
    local twist = ({0, 0.06, 0.5, 0.95})[frame]
    local reach = ({34, 18, 10, 12})[frame]
    victim((frame - 1) * 3, twist)
    gripHand(100 - 38 - reach, 50, 1.6 + twist, 0.8)
    gripHand(100 + 38 + reach, 50, -1.6 + twist, 0.8)

    if frame == 3 then
        for i = 1, 4 do
            rect(120 + i * 7, 30 + i * 5, 15, 3, {0.95, 0.95, 0.95, 0.45})
        end
    elseif frame == 4 then
        rect(50, 34, 100, 4, {0.92, 0.92, 0.92, 0.3})
        rect(58, 44, 84, 3, {0.92, 0.92, 0.92, 0.2})
    end
end

art.VIEW_ORDER = {"hatchet", "revolver", "uzi", "launcher", "grenades", "flashes",
    "knife", "throat", "head", "neck"}

-- How many columns of the sheet each row really uses.
art.VIEW_FRAMES = {
    hatchet = 2,
    revolver = 10,
    uzi = 10,
    launcher = 2,
    grenades = 2,
    flashes = 2,
    knife = 2,
    throat = 4,
    head = 4,
    neck = 4,
}

-- Where the three frames of a reload start on the row: the plain set, and
-- then the same three with the silencer on. A view with no line here has no
-- frames of its own and the HUD only dips it out of the way.
art.RELOAD_VIEW = {
    revolver = {plain = 5, quiet = 8},
    uzi = {plain = 5, quiet = 8},
}

art.TAKEDOWNS = {"throat", "head", "neck"}

-- Every cell is drawn in code, and then anything the player has dropped into
-- assets/ is painted over the top of it. A file is matched to a cell by its
-- name: assets/sprites/g2.aim.png replaces the sergeant taking aim, and
-- assets/views/revolver.2.png the second frame of the revolver in your hands.
-- Nothing has to be there, and whatever is missing stays as it was drawn.
art.SPRITE_DIR = "assets/sprites"
art.VIEW_DIR = "assets/views"

art.loaded = {sprites = 0, views = 0, walls = 0}

local function readImage(path)
    if not (love.filesystem.getInfo and love.filesystem.getInfo(path)) then
        return nil
    end

    local ok, image = pcall(love.graphics.newImage, path)
    if not ok then
        print("art: could not read " .. path)

        return nil
    end

    image:setFilter("nearest", "nearest")

    return image
end

-- Painted over the generated cell, scaled to the cell if the file is not
-- exactly the size we draw at, so art can be supplied at any resolution.
local function paintOver(image, x, y, w, h)
    lg.setScissor(x, y, w, h)
    lg.setBlendMode("replace")
    lg.setColor(0, 0, 0, 0)
    lg.rectangle("fill", x, y, w, h)
    lg.setBlendMode("alpha")
    lg.setColor(1, 1, 1, 1)

    local iw, ih = image:getDimensions()
    lg.draw(image, x, y, 0, w / iw, h / ih)
    lg.setScissor()
end

local EXTRAS = {
    ["fx.knife"] = flyingKnife,
    ["fx.rocket"] = flyingRocket,
    ["fx.grenade"] = thrownGrenade,
    ["fx.flash"] = thrownFlash,
    ["fx.boom1"] = function() fireball(0) end,
    ["fx.boom2"] = function() fireball(0.33) end,
    ["fx.boom3"] = function() fireball(0.66) end,
    ["fx.boom4"] = function() fireball(1) end,
    ["fx.pop"] = flashPop,
    ["fx.blood"] = function() blob({0.52, 0.06, 0.07, 0.95}) end,
    ["fx.spark"] = function() blob({0.95, 0.80, 0.35, 0.95}) end,
    ["fx.smoke"] = function() blob({0.45, 0.44, 0.44, 0.55}) end,
}

local EXTRA_ORDER = {"fx.knife", "fx.rocket", "fx.grenade", "fx.flash", "fx.boom1", "fx.boom2",
    "fx.boom3", "fx.boom4", "fx.pop", "fx.blood", "fx.spark", "fx.smoke"}

-- Every cell the sheet carries, in the order it is laid down, each with the
-- drawing that fills it. The list comes before the canvas so the sheet can be
-- made as tall as the cells need instead of a fixed ten rows, which was two
-- cells off being full.
local function spriteCells()
    local list = {}

    local function cell(name, draw)
        list[#list + 1] = {name = name, draw = draw}
    end

    for _, t in ipairs(art.TIERS) do
        for _, frame in ipairs(art.FRAMES) do
            cell(t.key .. "." .. frame, function() guardFrame(t, frame) end)
        end
    end

    for _, name in ipairs(art.ITEM_ORDER) do
        cell("item." .. name, items[name])
    end

    for _, name in ipairs(art.PROP_ORDER) do
        cell("prop." .. name, props[name])
    end

    cell("prop.deadguard", deadGuard)

    for _, frame in ipairs(art.DOG_FRAMES) do
        cell("dg." .. frame, function() dogFrame(frame) end)
    end

    -- An alias has a cell of its own, drawn with the frame it points at.
    -- Handing it the real frame's cell would save the room, but then a file
    -- named after the alias would land on the real frame and repaint it.
    -- Sorted, so two loads lay the sheet out the same way.
    local aliases = {}

    for alias in pairs(art.DOG_ALIAS) do
        aliases[#aliases + 1] = alias
    end

    table.sort(aliases)

    for _, alias in ipairs(aliases) do
        local real = art.DOG_ALIAS[alias]
        cell("dg." .. alias, function() dogFrame(real) end)
    end

    for _, frame in ipairs(art.CON_FRAMES) do
        cell("con." .. frame, function() conFigure(frame) end)
    end

    for _, name in ipairs(EXTRA_ORDER) do
        cell(name, EXTRAS[name])
    end

    return list
end

function art.load()
    lg = love.graphics
    art.loaded = {sprites = 0, views = 0, walls = 0}

    -- loading twice has to give the same sheet, not carry on filling the
    -- one before it
    cells = {}
    quads = {}
    used = 0

    local list = spriteCells()

    for _, c in ipairs(list) do
        reserve(c.name)
    end

    local sheet = lg.newCanvas(COLS * CELL, math.ceil(#list / COLS) * CELL)
    sheet:setFilter("nearest", "nearest")

    lg.push("all")
    lg.setCanvas(sheet)
    lg.clear(0, 0, 0, 0)
    lg.setBlendMode("alpha")

    for _, c in ipairs(list) do
        push(c.name)
        c.draw()
        pop()
    end

    -- The player's own sprites, over the top of ours, while the sheet is still
    -- the canvas being drawn to. An alias takes the file named after itself
    -- when there is one, and the file of the frame it points at when there is
    -- not, so it goes on looking like that frame either way. Only a file read
    -- for its own cell counts towards the total, so the startup line stays a
    -- count of files and not of cells painted.
    for name, c in pairs(cells) do
        local image = readImage(art.SPRITE_DIR .. "/" .. name .. ".png")

        if image then
            art.loaded.sprites = art.loaded.sprites + 1
        else
            local real = art.DOG_ALIAS[name:match("^dg%.(.+)$") or ""]
            image = real and readImage(art.SPRITE_DIR .. "/dg." .. real .. ".png")
        end

        if image then
            paintOver(image, c.x, c.y, CELL, CELL)
        end
    end

    lg.setCanvas()
    lg.pop()

    art.sheet = sheet

    for name, c in pairs(cells) do
        quads[name] = lg.newQuad(c.x, c.y, CELL, CELL, sheet:getDimensions())
    end

    local vw, vh = art.VIEW_W, art.VIEW_H
    local pack = art.VIEW_PACK
    local total = 0

    for _, name in ipairs(art.VIEW_ORDER) do
        total = total + art.VIEW_FRAMES[name]
    end

    local viewSheet = lg.newCanvas(vw * pack, vh * math.ceil(total / pack))
    viewSheet:setFilter("nearest", "nearest")

    lg.push("all")
    lg.setCanvas(viewSheet)
    lg.clear(0, 0, 0, 0)
    lg.setBlendMode("alpha")

    art.viewQuads = {}
    local slot = 0

    for _, name in ipairs(art.VIEW_ORDER) do
        art.viewQuads[name] = {}

        for col = 1, art.VIEW_FRAMES[name] do
            local x, y = (slot % pack) * vw, math.floor(slot / pack) * vh
            slot = slot + 1

            lg.push()
            lg.setScissor(x, y, vw, vh)
            lg.translate(x, y)
            lg.scale(VIEW_SCALE)
            views[name](col)
            lg.setScissor()
            lg.pop()

            local image = readImage(string.format("%s/%s.%d.png", art.VIEW_DIR, name, col))

            if image then
                paintOver(image, x, y, vw, vh)
                art.loaded.views = art.loaded.views + 1
            end

            art.viewQuads[name][col] = lg.newQuad(x, y, vw, vh, viewSheet:getDimensions())
        end
    end

    lg.setCanvas()
    lg.pop()

    art.views = viewSheet
    art.cellSize = CELL
    art.loaded.walls = textures.loadedCount or 0

    local n = art.loaded
    if n.sprites + n.views + n.walls > 0 then
        print(string.format("assets: %d sprites, %d weapon views, %d wall and ground textures",
            n.sprites, n.views, n.walls))
    end
end

function art.quad(name)
    return quads[name]
end

function art.viewQuad(name, frame)
    local row = art.viewQuads[name]
    if not row then
        return nil
    end

    return row[math.min(frame, art.VIEW_FRAMES[name])]
end

function art.has(name)
    return quads[name] ~= nil
end

return art
