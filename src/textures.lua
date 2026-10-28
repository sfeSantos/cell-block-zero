-- Wall art, generated pixel by pixel at load time into one atlas so the whole
-- 3D view can be drawn from a single sprite batch. Every texture is a 64 by 64
-- cell, stacked top to bottom in the order src/level.lua expects.

local textures = {}

local SIZE = 64
local COUNT = 22

local seed = 20231017

local function rnd()
    seed = (seed * 1103515245 + 12345) % 2147483648

    return seed / 2147483648
end

local function clamp(v)
    if v < 0 then
        return 0
    elseif v > 1 then
        return 1
    end

    return v
end

-- A cell is a small writer bound to one slot of the atlas.
local function cell(data, slot)
    local top = (slot - 1) * SIZE
    local c = {}

    function c.px(x, y, r, g, b)
        if x < 0 or y < 0 or x >= SIZE or y >= SIZE then
            return
        end

        data:setPixel(x, top + y, clamp(r), clamp(g), clamp(b), 1)
    end

    function c.fill(r, g, b, grain)
        for y = 0, SIZE - 1 do
            for x = 0, SIZE - 1 do
                local n = grain and (rnd() - 0.5) * grain or 0
                c.px(x, y, r + n, g + n, b + n)
            end
        end
    end

    function c.rect(x0, y0, w, h, r, g, b, grain)
        for y = y0, y0 + h - 1 do
            for x = x0, x0 + w - 1 do
                local n = grain and (rnd() - 0.5) * grain or 0
                c.px(x, y, r + n, g + n, b + n)
            end
        end
    end

    function c.hline(y, x0, x1, r, g, b)
        for x = x0, x1 do
            c.px(x, y, r, g, b)
        end
    end

    function c.vline(x, y0, y1, r, g, b)
        for y = y0, y1 do
            c.px(x, y, r, g, b)
        end
    end

    function c.shade(amount)
        for y = 0, SIZE - 1 do
            local f = 1 - (y / SIZE) * amount
            for x = 0, SIZE - 1 do
                local r, g, b = data:getPixel(x, top + y)
                c.px(x, y, r * f, g * f, b * f)
            end
        end
    end

    return c
end

local function blocks(c, base, mortar, bw, bh, stagger)
    c.fill(base[1], base[2], base[3], 0.07)

    for y = 0, SIZE - 1, bh do
        c.hline(y, 0, SIZE - 1, mortar[1], mortar[2], mortar[3])
        local row = math.floor(y / bh)
        local shift = stagger and (row % 2) * math.floor(bw / 2) or 0
        for x = 0, SIZE - 1, bw do
            local vx = (x + shift) % SIZE
            c.vline(vx, y, math.min(SIZE - 1, y + bh - 1), mortar[1], mortar[2], mortar[3])
        end

        -- a light top edge and a dark bottom edge give the blocks some relief
        for x = 0, SIZE - 1 do
            local r, g, b = base[1], base[2], base[3]
            c.px(x, y + 1, r * 1.22, g * 1.22, b * 1.22)
            c.px(x, y + bh - 1, r * 0.72, g * 0.72, b * 0.72)
        end
    end
end

local function rivets(c, step, light, dark)
    for y = step, SIZE - 1, step do
        for x = step, SIZE - 1, step do
            c.px(x, y, light, light, light * 1.05)
            c.px(x - 1, y, light * 0.8, light * 0.8, light * 0.85)
            c.px(x, y - 1, light * 0.9, light * 0.9, light * 0.95)
            c.px(x + 1, y + 1, dark, dark, dark)
        end
    end
end

local function frame(c, inset, r, g, b)
    for i = 0, inset - 1 do
        c.hline(i, 0, SIZE - 1, r, g, b)
        c.hline(SIZE - 1 - i, 0, SIZE - 1, r * 0.7, g * 0.7, b * 0.7)
        c.vline(i, 0, SIZE - 1, r, g, b)
        c.vline(SIZE - 1 - i, 0, SIZE - 1, r * 0.7, g * 0.7, b * 0.7)
    end
end

local function keyhole(c, r, g, b)
    c.rect(29, 30, 6, 6, 0.04, 0.04, 0.05)
    c.rect(31, 34, 2, 7, 0.04, 0.04, 0.05)
    c.rect(30, 31, 4, 4, r, g, b)
end

local function stoneWall(c)
    blocks(c, {0.46, 0.45, 0.44}, {0.22, 0.21, 0.21}, 32, 16, true)
    for _ = 1, 90 do
        local x, y = math.floor(rnd() * SIZE), math.floor(rnd() * SIZE)
        local d = 0.88 + rnd() * 0.2
        c.px(x, y, 0.46 * d, 0.45 * d, 0.44 * d)
    end
    c.shade(0.22)
end

local function brickWall(c)
    blocks(c, {0.42, 0.24, 0.19}, {0.26, 0.25, 0.24}, 16, 8, true)
    c.shade(0.25)
end

local function cellWall(c)
    blocks(c, {0.60, 0.62, 0.58}, {0.30, 0.32, 0.31}, 16, 16, false)
    for _ = 1, 40 do
        local x, y = math.floor(rnd() * SIZE), math.floor(rnd() * SIZE)
        c.px(x, y, 0.52, 0.50, 0.44)
    end
    -- a grubby band at waist height, every prison has one
    c.rect(0, 44, SIZE, 6, 0.44, 0.44, 0.40, 0.08)
    c.shade(0.18)
end

local function metalWall(c)
    c.fill(0.30, 0.33, 0.37, 0.05)
    c.rect(0, 30, SIZE, 3, 0.20, 0.22, 0.26)
    c.rect(0, 33, SIZE, 1, 0.42, 0.45, 0.50)
    rivets(c, 16, 0.52, 0.16)
    c.shade(0.20)
end

local function rockWall(c)
    c.fill(0.34, 0.28, 0.23, 0.22)
    for _ = 1, 14 do
        local x, y = math.floor(rnd() * SIZE), math.floor(rnd() * SIZE)
        local len = 6 + math.floor(rnd() * 20)
        for i = 0, len do
            c.px(x + math.floor(i * (rnd() - 0.5) * 0.9), y + i % SIZE, 0.18, 0.15, 0.13)
        end
    end
    c.shade(0.26)
end

local function posterWall(c)
    blocks(c, {0.42, 0.24, 0.19}, {0.26, 0.25, 0.24}, 16, 8, true)
    c.rect(16, 12, 32, 40, 0.80, 0.76, 0.66, 0.05)
    c.rect(16, 12, 32, 1, 0.55, 0.52, 0.46)
    c.rect(20, 16, 24, 10, 0.55, 0.14, 0.12)
    for y = 30, 46, 4 do
        c.hline(y, 20, 43, 0.35, 0.33, 0.30)
        c.hline(y + 1, 20, 36, 0.35, 0.33, 0.30)
    end
    c.shade(0.20)
end

-- A steel locker set into the wall, shut and then open and picked clean.
local function locker(c, open)
    c.fill(0.26, 0.28, 0.31, 0.05)
    c.rect(0, 0, SIZE, 2, 0.18, 0.19, 0.22)
    c.rect(0, SIZE - 3, SIZE, 3, 0.16, 0.17, 0.19)

    if open then
        c.rect(6, 6, 52, 52, 0.07, 0.07, 0.08)
        c.rect(6, 6, 52, 2, 0.34, 0.36, 0.40)
        c.rect(6, 6, 2, 52, 0.30, 0.32, 0.36)
        -- the door hanging off to one side
        c.rect(46, 4, 14, 56, 0.30, 0.32, 0.36, 0.04)
        c.rect(46, 4, 2, 56, 0.44, 0.46, 0.50)
        for y = 14, 46, 8 do
            c.hline(y, 10, 40, 0.12, 0.12, 0.13)
        end

        return c.shade(0.22)
    end

    c.rect(5, 4, 54, 56, 0.33, 0.35, 0.39, 0.04)
    c.rect(5, 4, 54, 2, 0.46, 0.48, 0.52)
    c.rect(5, 58, 54, 2, 0.18, 0.19, 0.21)
    c.rect(31, 4, 2, 56, 0.20, 0.21, 0.23)
    for y = 12, 52, 10 do
        c.hline(y, 9, 28, 0.24, 0.25, 0.28)
        c.hline(y, 36, 55, 0.24, 0.25, 0.28)
    end

    c.rect(26, 28, 4, 8, 0.52, 0.54, 0.58)
    c.rect(34, 28, 4, 8, 0.52, 0.54, 0.58)
    c.shade(0.22)
end

local function steelDoor(c)
    c.fill(0.34, 0.36, 0.40, 0.05)
    frame(c, 3, 0.22, 0.24, 0.28)
    c.rect(8, 8, 48, 20, 0.29, 0.31, 0.35, 0.04)
    c.rect(8, 34, 48, 22, 0.29, 0.31, 0.35, 0.04)
    -- barred hatch in the upper panel
    c.rect(20, 12, 24, 12, 0.07, 0.08, 0.09)
    for x = 22, 42, 4 do
        c.vline(x, 12, 23, 0.46, 0.48, 0.52)
    end
    c.rect(44, 30, 14, 4, 0.55, 0.56, 0.58)
    rivets(c, 20, 0.48, 0.18)
    c.shade(0.16)
end

local function barredDoor(c)
    c.fill(0.08, 0.09, 0.11, 0.03)
    for x = 4, SIZE - 5, 10 do
        c.rect(x, 0, 4, SIZE, 0.44, 0.45, 0.47, 0.05)
        c.vline(x, 0, SIZE - 1, 0.62, 0.63, 0.66)
        c.vline(x + 3, 0, SIZE - 1, 0.24, 0.25, 0.27)
    end
    c.rect(0, 28, SIZE, 5, 0.40, 0.41, 0.44, 0.05)
    c.rect(0, 28, SIZE, 1, 0.58, 0.59, 0.62)
    c.rect(26, 33, 12, 7, 0.52, 0.50, 0.42)
    c.shade(0.10)
end

local function lockedDoor(c, r, g, b)
    c.fill(0.30, 0.32, 0.36, 0.05)
    frame(c, 3, 0.20, 0.22, 0.26)
    c.rect(0, 20, SIZE, 10, r * 0.7, g * 0.7, b * 0.7, 0.04)
    c.rect(0, 20, SIZE, 1, r, g, b)
    c.rect(0, 29, SIZE, 1, r * 0.4, g * 0.4, b * 0.4)
    c.rect(10, 38, 44, 14, 0.26, 0.28, 0.32, 0.04)
    keyhole(c, r, g, b)
    rivets(c, 20, 0.46, 0.18)
    c.shade(0.16)
end

local function exitDoor(c)
    c.fill(0.26, 0.28, 0.31, 0.05)
    frame(c, 4, 0.18, 0.20, 0.23)
    c.rect(10, 10, 44, 20, 0.12, 0.30, 0.16, 0.03)
    c.rect(10, 10, 44, 1, 0.30, 0.80, 0.40)
    -- arrow pointing out
    for i = 0, 9 do
        c.rect(22 + i, 20 - i, 1, 1 + i * 2, 0.45, 0.95, 0.55)
    end
    c.rect(18, 18, 6, 5, 0.45, 0.95, 0.55)
    c.rect(14, 38, 36, 16, 0.22, 0.24, 0.27, 0.04)
    c.rect(28, 42, 8, 8, 0.70, 0.62, 0.20)
    c.rect(30, 44, 4, 10, 0.85, 0.78, 0.30)
    c.shade(0.14)
end

-- The alarm panel. A plate bolted into the wall, a glass front, and the
-- handle sitting behind the glass where nobody leans on it by accident. The
-- used one has the glass out and the handle down, so from the far end of a
-- corridor you can tell whether anybody got here before you.
local function alarmPanel(c, used)
    c.fill(0.24, 0.25, 0.28, 0.05)
    frame(c, 3, 0.17, 0.18, 0.21)

    -- the plate, in the one colour nobody ever paints over
    c.rect(9, 7, 46, 50, 0.50, 0.13, 0.11, 0.04)
    c.rect(9, 7, 46, 2, 0.68, 0.21, 0.17)
    c.rect(9, 55, 46, 2, 0.25, 0.07, 0.06)
    c.vline(9, 7, 56, 0.60, 0.17, 0.14)
    c.vline(54, 7, 56, 0.27, 0.08, 0.07)
    rivets(c, 16, 0.44, 0.16)

    -- the recess, dark enough that the handle reads against it
    c.rect(15, 14, 34, 28, 0.11, 0.11, 0.13)
    c.rect(15, 14, 34, 1, 0.06, 0.06, 0.07)

    if used then
        -- handle pulled right down, and what is left of the glass round the rim
        c.rect(30, 26, 5, 13, 0.66, 0.58, 0.18, 0.03)
        c.rect(30, 37, 5, 2, 0.86, 0.78, 0.30)
        c.rect(28, 23, 9, 3, 0.40, 0.35, 0.12)

        for x = 16, 47 do
            local n = (x * 13 + 5) % 7
            if n < 4 then
                c.vline(x, 15, 15 + n, 0.60 - n * 0.04, 0.66 - n * 0.04, 0.68 - n * 0.04)
            end
        end

        for y = 17, 40 do
            local n = (y * 11 + 3) % 6
            if n < 3 then
                c.hline(y, 16, 16 + n, 0.52, 0.58, 0.60)
                c.hline(y, 47 - n, 47, 0.44, 0.49, 0.51)
            end
        end
    else
        -- handle up, and the glass still in front of it: a dull wash, one
        -- diagonal streak of light, and the lip that holds it in
        c.rect(30, 19, 5, 13, 0.70, 0.62, 0.20, 0.03)
        c.rect(30, 19, 5, 2, 0.88, 0.80, 0.32)
        c.rect(28, 31, 9, 3, 0.42, 0.37, 0.13)

        for y = 15, 40 do
            for x = 16, 47 do
                if (x + y) % 7 == 0 then
                    c.px(x, y, 0.30, 0.34, 0.36)
                end
            end
        end

        for i = 0, 25 do
            local x, y = 18 + i, 39 - i
            if x <= 47 and y >= 15 then
                c.px(x, y, 0.56, 0.62, 0.66)
                c.px(x + 1, y, 0.40, 0.45, 0.48)
            end
        end

        c.rect(15, 14, 34, 1, 0.52, 0.56, 0.58)
        c.vline(15, 14, 41, 0.46, 0.50, 0.52)
        c.vline(48, 14, 41, 0.30, 0.33, 0.35)
        c.hline(41, 15, 48, 0.24, 0.26, 0.28)
    end

    -- the stencilled strip below it, worn down to marks
    c.rect(14, 45, 36, 7, 0.10, 0.10, 0.11)
    for x = 17, 46, 5 do
        c.rect(x, 47, 3, 3, 0.74, 0.70, 0.56)
    end

    c.shade(0.18)
end

-- The tell on a loose panel. The wall itself is painted first and this goes
-- over it: a hairline down both sides where it does not quite meet the rest,
-- and the scuffed arc on the floor it has been dragged over. From down the
-- corridor it is nothing. Standing in front of it, it is obvious.
local function loose(c)
    for y = 0, SIZE - 1 do
        c.px(0, y, 0.05, 0.05, 0.06)
        c.px(1, y, 0.11, 0.11, 0.12)
        c.px(SIZE - 1, y, 0.05, 0.05, 0.06)
        c.px(SIZE - 2, y, 0.11, 0.11, 0.12)
    end

    -- dust and scrape marks along the bottom edge
    for x = 3, SIZE - 4 do
        local n = (x * 7 % 5) * 0.012
        c.px(x, SIZE - 2, 0.44 + n, 0.42 + n, 0.38 + n)
        if x % 3 ~= 0 then
            c.px(x, SIZE - 3, 0.36 + n, 0.34 + n, 0.31 + n)
        end
    end

    -- and the worn patch where hands have pushed it
    for y = 26, 38 do
        for x = 24, 40 do
            if (x + y) % 3 == 0 then
                c.px(x, y, 0.40, 0.39, 0.36)
            end
        end
    end
end

-- The floor and the ceiling. These two are not part of the atlas: they are
-- tiled across the ground by the renderer, so each one is its own image with
-- the wrap set to repeat. They are painted dark, because the level tints them
-- with its own colour on top.
local function concrete(c)
    c.fill(0.33, 0.32, 0.30, 0.06)

    -- slabs, four to a tile, with the grout between them
    for _, y in ipairs({0, 32}) do
        c.hline(y, 0, SIZE - 1, 0.21, 0.20, 0.19)
        c.hline(y + 1, 0, SIZE - 1, 0.39, 0.38, 0.36)
    end
    for _, x in ipairs({0, 32}) do
        c.vline(x, 0, SIZE - 1, 0.21, 0.20, 0.19)
        c.vline(x + 1, 0, SIZE - 1, 0.39, 0.38, 0.36)
    end

    -- chips along the edges and grit over the middle of each slab
    for _ = 1, 150 do
        local x, y = math.floor(rnd() * SIZE), math.floor(rnd() * SIZE)
        local n = 0.06 + rnd() * 0.08
        c.px(x, y, 0.33 + n, 0.32 + n, 0.30 + n)
    end
    for _ = 1, 60 do
        local x, y = math.floor(rnd() * SIZE), math.floor(rnd() * SIZE)
        c.px(x, y, 0.24, 0.23, 0.22)
    end

    -- the drain channel down the middle of the block
    c.rect(29, 0, 6, SIZE, 0.27, 0.27, 0.26, 0.04)
    c.vline(29, 0, SIZE - 1, 0.19, 0.19, 0.18)
    c.vline(34, 0, SIZE - 1, 0.19, 0.19, 0.18)
end

local function panels(c)
    c.fill(0.26, 0.26, 0.28, 0.05)

    -- a shallow coffer in the middle of the tile
    c.rect(6, 6, 52, 52, 0.30, 0.30, 0.32, 0.04)
    c.rect(6, 6, 52, 1, 0.38, 0.38, 0.41)
    c.rect(6, 57, 52, 1, 0.19, 0.19, 0.21)
    c.vline(6, 6, 57, 0.36, 0.36, 0.39)
    c.vline(57, 6, 57, 0.19, 0.19, 0.21)

    -- the beams that cross it, and their bolts
    c.rect(0, 0, SIZE, 5, 0.22, 0.22, 0.24, 0.04)
    c.rect(0, 0, 5, SIZE, 0.22, 0.22, 0.24, 0.04)
    for i = 0, SIZE - 1, 16 do
        c.px(2, i + 2, 0.40, 0.40, 0.43)
        c.px(i + 2, 2, 0.40, 0.40, 0.43)
    end

    -- and the stain where the damp gets in
    for y = 18, 40 do
        for x = 20, 44 do
            if (x * 3 + y * 5) % 11 < 2 then
                c.px(x, y, 0.22, 0.23, 0.22)
            end
        end
    end
end

local PANELS = {stoneWall, brickWall, cellWall, metalWall, rockWall, posterWall}

-- The wall slots, by name, so a file in assets/walls can say which one it
-- replaces without anybody counting rows.
textures.NAMES = {
    "stone", "brick", "cell", "metal", "rock", "poster",
    "door-steel", "door-bars", "door-red", "door-blue", "door-yellow",
    "exit", "locker", "locker-open",
    "panel-stone", "panel-brick", "panel-cell", "panel-metal", "panel-rock",
    "panel-poster",
    "alarm", "alarm-used",
}

textures.DIR = "assets/walls"
textures.FLAT_DIR = "assets/flats"
textures.loadedCount = 0

-- A file of any size is sampled into the 64 by 64 slot, nearest neighbour,
-- so art can be supplied at whatever resolution it was drawn at.
local function overlay(data, slot, file)
    local ok, image = pcall(love.image.newImageData, file)
    if not ok then
        print("textures: could not read " .. file)

        return false
    end

    local iw, ih = image:getDimensions()
    local top = (slot - 1) * SIZE
    for y = 0, SIZE - 1 do
        for x = 0, SIZE - 1 do
            local sx = math.min(iw - 1, math.floor(x * iw / SIZE))
            local sy = math.min(ih - 1, math.floor(y * ih / SIZE))
            local r, g, b = image:getPixel(sx, sy)
            data:setPixel(x, top + y, r, g, b, 1)
        end
    end

    return true
end

-- A flat is tiled across the ground rather than stretched over one wall, so
-- it stays its own image and keeps its own size when it comes from a file.
local function flat(paint, name)
    local file = textures.FLAT_DIR .. "/" .. name .. ".png"
    local image

    if love.filesystem.getInfo and love.filesystem.getInfo(file) then
        local ok, got = pcall(love.graphics.newImage, file)
        if ok then
            image = got
            textures.loadedCount = textures.loadedCount + 1
        else
            print("textures: could not read " .. file)
        end
    end

    if not image then
        local data = love.image.newImageData(SIZE, SIZE)
        paint(cell(data, 1))
        image = love.graphics.newImage(data)
    end

    image:setFilter("nearest", "nearest")
    image:setWrap("repeat", "repeat")

    return image
end

function textures.load()
    local data = love.image.newImageData(SIZE, SIZE * COUNT)

    stoneWall(cell(data, 1))
    brickWall(cell(data, 2))
    cellWall(cell(data, 3))
    metalWall(cell(data, 4))
    rockWall(cell(data, 5))
    posterWall(cell(data, 6))
    steelDoor(cell(data, 7))
    barredDoor(cell(data, 8))
    lockedDoor(cell(data, 9), 0.85, 0.18, 0.18)
    lockedDoor(cell(data, 10), 0.22, 0.42, 0.90)
    lockedDoor(cell(data, 11), 0.92, 0.78, 0.16)
    exitDoor(cell(data, 12))
    locker(cell(data, 13), false)
    locker(cell(data, 14), true)

    -- one loose panel for each kind of wall, slots 15 to 20
    for i, paint in ipairs(PANELS) do
        local c = cell(data, 14 + i)
        paint(c)
        loose(c)
    end

    alarmPanel(cell(data, 21), false)
    alarmPanel(cell(data, 22), true)

    -- and whatever the player has put in assets/walls, over the top
    textures.loadedCount = 0
    for slot, name in ipairs(textures.NAMES) do
        local file = textures.DIR .. "/" .. name .. ".png"
        if love.filesystem.getInfo and love.filesystem.getInfo(file) then
            if overlay(data, slot, file) then
                textures.loadedCount = textures.loadedCount + 1
            end
        end
    end

    textures.flats = {
        floor = flat(concrete, "floor"),
        ceiling = flat(panels, "ceiling"),
    }

    textures.image = love.graphics.newImage(data)
    textures.image:setFilter("nearest", "nearest")
    textures.image:setWrap("clamp", "clamp")
    textures.size = SIZE
    textures.count = COUNT
    textures.PANEL_BASE = 14

    return textures.image
end

function textures.quadTop(id)
    return (id - 1) * SIZE
end

return textures
