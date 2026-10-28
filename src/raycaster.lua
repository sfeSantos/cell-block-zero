-- The renderer. One ray per column of an internal low resolution canvas, then
-- the canvas is blown up to the window with nearest filtering. Walls and
-- sprites both go through sprite batches, so a frame costs a handful of draw
-- calls no matter how busy the corridor is.

local textures = require("src.textures")
local art = require("src.art")

local rc = {}

-- How wide the camera plane is, which is what decides the field of view.
-- rc.resize works it out from the shape of the canvas rather than fixing it,
-- and rc.fov is the horizontal angle that comes out, kept for printing.
rc.fov = 0

local canvas, iw, ih, scale, plane
local decalMesh, decalBuf, decalCap
local decals = {}
local wallBatch, spriteBatch
local wallQuad, spriteQuad
local zbuffer = {}
local visible = {}
local floorMesh, ceilMesh
local flatFloor, flatCeil, flatBuf, flatQuads

local TEX = 64

-- How tall a strip of textured ground is, in pixels of the internal canvas.
-- One strip a row is the finest the canvas can do, and it is free: measured
-- at 1920 by 1080 it costs nothing above the noise, 5.70 ms a frame against
-- 5.77 in the yard, and it redraws 13% of that frame.
local FLAT_STEP = 1

-- Rows closer to the horizon than this are left to the plain gradient
-- underneath: they are a hundred tiles out, and nearly black anyway.
local FLAT_NEAR = 3

-- The ground is lit well below the walls. A corridor wants to be a dark
-- floor with light coming off the walls, not a lit stage.
local FLOOR_DIM = 0.55
local CEIL_DIM = 0.42

local function gradientMesh(flip)
    local near = flip and 0.22 or 1.35
    local far = flip and 1.35 or 0.22
    local verts = {
        {0, 0, 0, 0, far, far, far, 1},
        {1, 0, 1, 0, far, far, far, 1},
        {1, 1, 1, 1, near, near, near, 1},
        {0, 1, 0, 1, near, near, near, 1},
    }

    return love.graphics.newMesh(verts, "fan", "static")
end

-- Two meshes of horizontal strips, one for the floor and one for the ceiling.
-- Each strip is a quad with the world coordinates of its two ends as texture
-- coordinates, which is what makes the ground run away in perspective.
local function buildFlats()
    flatQuads = math.ceil(ih / FLAT_STEP) + 2
    flatBuf = {}
    local map = {}

    for i = 1, flatQuads do
        local b = (i - 1) * 4
        for k = 1, 4 do
            flatBuf[b + k] = {0, 0, 0, 0, 1, 1, 1, 1}
        end

        local m = (i - 1) * 6
        map[m + 1], map[m + 2], map[m + 3] = b + 1, b + 2, b + 3
        map[m + 4], map[m + 5], map[m + 6] = b + 1, b + 3, b + 4
    end

    if flatFloor then
        flatFloor:release()
        flatCeil:release()
    end

    flatFloor = love.graphics.newMesh(flatBuf, "triangles", "stream")
    flatFloor:setVertexMap(map)
    flatCeil = love.graphics.newMesh(flatBuf, "triangles", "stream")
    flatCeil:setVertexMap(map)
end

-- The same strips again, for the things painted into the ground rather than
-- standing on it. The floor only starts a tile away, so no one stain can
-- cover more than half the canvas, and one canvas height of strips is room
-- for every stain on screen at once.
local function buildDecals()
    decalCap = ih
    decalBuf = {}
    local map = {}

    for i = 1, decalCap do
        local b = (i - 1) * 4
        for k = 1, 4 do
            decalBuf[b + k] = {0, 0, 0, 0, 1, 1, 1, 1}
        end

        local m = (i - 1) * 6
        map[m + 1], map[m + 2], map[m + 3] = b + 1, b + 2, b + 3
        map[m + 4], map[m + 5], map[m + 6] = b + 1, b + 3, b + 4
    end

    if decalMesh then
        decalMesh:release()
    end

    decalMesh = love.graphics.newMesh(decalBuf, "triangles", "stream")
    decalMesh:setVertexMap(map)
end

function rc.load()
    wallBatch = love.graphics.newSpriteBatch(textures.image, 1024)
    spriteBatch = love.graphics.newSpriteBatch(art.sheet, 2048)
    wallQuad = love.graphics.newQuad(0, 0, 1, TEX, textures.image:getDimensions())
    spriteQuad = love.graphics.newQuad(0, 0, 1, 1, art.sheet:getDimensions())
    floorMesh = gradientMesh(false)
    ceilMesh = gradientMesh(true)
end

-- The picture is drawn small and blown up by a whole number, which is what
-- keeps the pixels square. This is the height we aim the small one at: 1080p
-- comes out 640 by 360 blown up three times and 1440p 854 by 480 blown up
-- three, where before both were about 240 lines blown up four and six. Four
-- times the pixels costs 8 % of a frame, measured. The floor of 2 keeps a
-- small window as chunky as it has always been.
local TARGET_LINES = 420

function rc.resize(w, h)
    scale = math.max(2, math.floor(h / TARGET_LINES + 0.5))
    iw = math.ceil(w / scale)
    ih = math.ceil(h / scale)

    -- A wall one tile tall is ih / dist pixels and one tile across the view is
    -- iw / (2 * plane * dist). Taking the plane off the shape of the canvas
    -- makes those the same number, so nothing is stretched on a wide screen
    -- and one sprite cell is one tile, which is what src/art.lua says it is.
    -- The vertical angle is the fixed one, 2 * atan(0.5) or about 53 degrees,
    -- and a wider screen sees further to the sides instead of seeing the same
    -- thing stretched.
    plane = 0.5 * iw / ih
    rc.fov = 2 * math.atan(plane)

    if canvas then
        canvas:release()
    end

    canvas = love.graphics.newCanvas(iw, ih)
    canvas:setFilter("nearest", "nearest")
    buildFlats()
    buildDecals()
end

function rc.dimensions()
    return iw, ih, scale
end

local function shadeOf(dist, side, light)
    local s = 1 / (1 + dist * dist * 0.0085)
    if side == 1 then
        s = s * 0.74
    end

    if light > 0 then
        s = s + light / (1 + dist * dist * 0.5)
    end

    if s > 1 then
        s = 1
    end

    return s
end

-- The level colour says what the ground is made of in this block, the texture
-- says what it looks like. Keeping the brightness in the texture and only the
-- hue in the colour means a floor stays dark without the art going grey.
local function tintOf(colour)
    local r, g, b = colour[1], colour[2], colour[3]
    local mean = (r + g + b) / 3
    if mean < 0.01 then
        return 1, 1, 1
    end

    return r / mean, g / mean, b / mean
end

local function drawFlats(world, player, horizon)
    local flats = textures.flats
    if not flats or not flatFloor then
        return
    end

    local lv = world.level
    local dirx, diry = math.cos(player.angle), math.sin(player.angle)
    local planex, planey = -diry * plane, dirx * plane
    local lx, ly = dirx - planex, diry - planey
    local rx, ry = dirx + planex, diry + planey
    local light = player.muzzle or 0
    local eye = ih * 0.5
    local px, py = player.x, player.y

    local function strip(n, y0, y1, p0, p1, tr, tg, tb, dim)
        local d0 = eye / p0
        local d1 = eye / p1
        local b = n * 4
        local v1, v2, v3, v4 = flatBuf[b + 1], flatBuf[b + 2], flatBuf[b + 3], flatBuf[b + 4]
        local s = shadeOf((d0 + d1) * 0.5, 0, light) * dim
        local r, g, bl = s * tr, s * tg, s * tb

        v1[1], v1[2], v1[3], v1[4] = 0, y0, px + d0 * lx, py + d0 * ly
        v2[1], v2[2], v2[3], v2[4] = iw, y0, px + d0 * rx, py + d0 * ry
        v3[1], v3[2], v3[3], v3[4] = iw, y1, px + d1 * rx, py + d1 * ry
        v4[1], v4[2], v4[3], v4[4] = 0, y1, px + d1 * lx, py + d1 * ly

        v1[5], v1[6], v1[7] = r, g, bl
        v2[5], v2[6], v2[7] = r, g, bl
        v3[5], v3[6], v3[7] = r, g, bl
        v4[5], v4[6], v4[7] = r, g, bl
    end

    local tr, tg, tb = tintOf(lv.floor)
    local n, y = 0, horizon + FLAT_NEAR
    if y < 0 then
        y = 0
    end

    while y < ih and n < flatQuads do
        local y1 = math.min(ih, y + FLAT_STEP)
        strip(n, y, y1, y - horizon, y1 - horizon, tr, tg, tb, FLOOR_DIM)
        n = n + 1
        y = y1
    end

    if n > 0 then
        flatFloor:setVertices(flatBuf)
        flatFloor:setDrawRange(1, n * 6)
        flatFloor:setTexture(flats.floor)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(flatFloor)
    end

    if lv.sky then
        return
    end

    tr, tg, tb = tintOf(lv.ceiling)
    n = 0
    y = horizon - FLAT_NEAR
    if y > ih then
        y = ih
    end

    while y > 0 and n < flatQuads do
        local y1 = math.max(0, y - FLAT_STEP)
        strip(n, y, y1, horizon - y, horizon - y1, tr, tg, tb, CEIL_DIM)
        n = n + 1
        y = y1
    end

    if n > 0 then
        flatCeil:setVertices(flatBuf)
        flatCeil:setDrawRange(1, n * 6)
        flatCeil:setTexture(flats.ceiling)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(flatCeil)
    end
end

-- Where a row of the ground crosses an axis aligned square, as the two ends
-- of the piece that is inside it, 0 at the left edge of the screen and 1 at
-- the right. nil when the row misses the square altogether.
local function rowInside(ax, ay, bx, by, x0, y0, x1, y1)
    local dx, dy = bx - ax, by - ay
    local s0, s1 = 0, 1

    if dx ~= 0 then
        local ta, tb = (x0 - ax) / dx, (x1 - ax) / dx
        if ta > tb then
            ta, tb = tb, ta
        end

        if ta > s0 then
            s0 = ta
        end

        if tb < s1 then
            s1 = tb
        end
    elseif ax < x0 or ax > x1 then
        return nil
    end

    if dy ~= 0 then
        local ta, tb = (y0 - ay) / dy, (y1 - ay) / dy
        if ta > tb then
            ta, tb = tb, ta
        end

        if ta > s0 then
            s0 = ta
        end

        if tb < s1 then
            s1 = tb
        end
    elseif ay < y0 or ay > y1 then
        return nil
    end

    if s1 <= s0 then
        return nil
    end

    return s0, s1
end

-- Blood lies in the floor instead of standing up out of it. These are the
-- same strips the ground is made of, cut down to the square the stain covers
-- and painted with its cell of the sprite sheet. One row at a time because a
-- mesh has no w, so its texture coordinates run affinely across a triangle
-- and one big quad lying on the ground would warp; inside a single row the
-- depth is the same all the way across, so a strip is exact.
--
-- It goes down after the ground and before the walls, which is all the depth
-- sorting it needs: a wall in front of a stain is drawn over it, and so is a
-- guard standing on one.
local function drawDecals(world, player, horizon)
    local list = world:collectDecals(decals)
    rc.decalQuads = 0

    if #list == 0 or not decalMesh or not art.sheet then
        return
    end

    local dirx, diry = math.cos(player.angle), math.sin(player.angle)
    local planex, planey = -diry * plane, dirx * plane
    local lx, ly = dirx - planex, diry - planey
    local rx, ry = dirx + planex, diry + planey
    local light = player.muzzle or 0
    local eye = ih * 0.5
    local px, py = player.x, player.y
    local sheetW, sheetH = art.sheet:getDimensions()
    local n = 0

    for _, decal in ipairs(list) do
        local quad = art.quad(decal.name)

        if quad and n < decalCap then
            local qx, qy, qw, qh = quad:getViewport()
            local half = decal.size * 0.5
            local span = half * 2
            local x0, x1 = decal.x - half, decal.x + half
            local y0, y1 = decal.y - half, decal.y + half

            -- how far its four corners are along the way we are looking,
            -- which is what says which rows it lands on
            local near, far = math.huge, -math.huge
            for k = 1, 4 do
                local cx = (k == 1 or k == 4) and x0 or x1
                local cy = k < 3 and y0 or y1
                local t = (cx - px) * dirx + (cy - py) * diry
                if t < near then
                    near = t
                end

                if t > far then
                    far = t
                end
            end

            if far > 0.3 then
                local top = math.floor(horizon + eye / far)
                local bot = near > 0.3 and math.ceil(horizon + eye / near) or ih

                if top < horizon + FLAT_NEAR then
                    top = horizon + FLAT_NEAR
                end

                if bot > ih then
                    bot = ih
                end

                for y = top, bot - 1 do
                    if n >= decalCap then
                        break
                    end

                    local d0 = eye / (y - horizon)
                    local d1 = eye / (y + 1 - horizon)
                    local ax, ay = px + d0 * lx, py + d0 * ly
                    local bx, by = px + d0 * rx, py + d0 * ry
                    local cx, cy = px + d1 * lx, py + d1 * ly
                    local ex, ey = px + d1 * rx, py + d1 * ry
                    local s0, s1 = rowInside(ax, ay, bx, by, x0, y0, x1, y1)
                    local t0, t1 = rowInside(cx, cy, ex, ey, x0, y0, x1, y1)

                    if s0 and t0 then
                        local b = n * 4
                        local v1, v2 = decalBuf[b + 1], decalBuf[b + 2]
                        local v3, v4 = decalBuf[b + 3], decalBuf[b + 4]
                        local sh = shadeOf((d0 + d1) * 0.5, 0, light) * FLOOR_DIM

                        v1[1], v1[2] = s0 * iw, y
                        v2[1], v2[2] = s1 * iw, y
                        v3[1], v3[2] = t1 * iw, y + 1
                        v4[1], v4[2] = t0 * iw, y + 1

                        local w1x, w1y = ax + (bx - ax) * s0, ay + (by - ay) * s0
                        local w2x, w2y = ax + (bx - ax) * s1, ay + (by - ay) * s1
                        local w3x, w3y = cx + (ex - cx) * t1, cy + (ey - cy) * t1
                        local w4x, w4y = cx + (ex - cx) * t0, cy + (ey - cy) * t0

                        v1[3] = (qx + (w1x - x0) / span * qw) / sheetW
                        v1[4] = (qy + (w1y - y0) / span * qh) / sheetH
                        v2[3] = (qx + (w2x - x0) / span * qw) / sheetW
                        v2[4] = (qy + (w2y - y0) / span * qh) / sheetH
                        v3[3] = (qx + (w3x - x0) / span * qw) / sheetW
                        v3[4] = (qy + (w3y - y0) / span * qh) / sheetH
                        v4[3] = (qx + (w4x - x0) / span * qw) / sheetW
                        v4[4] = (qy + (w4y - y0) / span * qh) / sheetH

                        v1[5], v1[6], v1[7] = sh, sh, sh
                        v2[5], v2[6], v2[7] = sh, sh, sh
                        v3[5], v3[6], v3[7] = sh, sh, sh
                        v4[5], v4[6], v4[7] = sh, sh, sh

                        n = n + 1
                    end
                end
            end
        end
    end

    if n > 0 then
        decalMesh:setVertices(decalBuf)
        decalMesh:setDrawRange(1, n * 6)
        decalMesh:setTexture(art.sheet)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(decalMesh)
    end

    rc.decalQuads = n
end

local function drawWalls(world, player, horizon)
    local level = world.level
    local dirx, diry = math.cos(player.angle), math.sin(player.angle)
    local planex, planey = -diry * plane, dirx * plane
    local light = player.muzzle or 0

    wallBatch:clear()

    for col = 0, iw - 1 do
        local camX = 2 * (col + 0.5) / iw - 1
        local rdx = dirx + planex * camX
        local rdy = diry + planey * camX
        local dist, tex, u, side = level:cast(player.x, player.y, rdx, rdy)

        if dist < 0.02 then
            dist = 0.02
        end

        tex = tex or 1

        zbuffer[col] = dist

        local lineH = ih / dist
        local top = horizon - lineH * 0.5
        local texX = math.floor(u * TEX)
        if texX < 0 then
            texX = 0
        elseif texX > TEX - 1 then
            texX = TEX - 1
        end

        local s = shadeOf(dist, side, light)
        wallQuad:setViewport(texX, textures.quadTop(tex), 1, TEX)
        wallBatch:setColor(s, s, s * 1.02, 1)
        wallBatch:add(wallQuad, col, top, 0, 1, lineH / TEX)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(wallBatch)
end

local function drawSprites(world, player, horizon)
    local list = world:collectSprites(visible)
    local dirx, diry = math.cos(player.angle), math.sin(player.angle)
    local planex, planey = -diry * plane, dirx * plane
    local invDet = 1 / (planex * diry - dirx * planey)
    local light = player.muzzle or 0
    local cell = art.cellSize

    for _, s in ipairs(list) do
        local sx, sy = s.x - player.x, s.y - player.y
        s.tx = invDet * (diry * sx - dirx * sy)
        s.ty = invDet * (-planey * sx + planex * sy)
    end

    table.sort(list, function(a, b)
        return a.ty > b.ty
    end)

    spriteBatch:clear()

    local drawn = 0
    for _, s in ipairs(list) do
        local ty = s.ty
        if ty > 0.12 then
            local size = s.size or 1
            local lineH = ih / ty
            local h = lineH * size
            local w = h
            local screenX = (iw * 0.5) * (1 + s.tx / ty)
            local top = horizon + lineH * (0.5 - (s.z or 0) - size)
            local left = screenX - w * 0.5
            local quad = art.quad(s.name)

            if quad and w > 0.5 then
                local c0 = math.max(0, math.floor(left))
                local c1 = math.min(iw - 1, math.ceil(left + w) - 1)
                local shade = s.glow and 1 or shadeOf(ty, 0, light)
                spriteBatch:setColor(shade, shade * (s.warm or 1), shade * (s.cool or 1), s.alpha or 1)

                local run = nil
                for col = c0, c1 do
                    local clear = ty < zbuffer[col]
                    if clear and not run then
                        run = col
                    elseif not clear and run then
                        rc.addRun(quad, run, col - 1, left, w, top, h, cell)
                        run = nil
                        drawn = drawn + 1
                    end
                end

                if run then
                    rc.addRun(quad, run, c1, left, w, top, h, cell)
                    drawn = drawn + 1
                end
            end
        end
    end

    if drawn > 0 then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(spriteBatch)
    end
end

-- One quad per visible stretch of a sprite, so a guard half behind a corner
-- still costs only a couple of entries in the batch.
function rc.addRun(quad, c0, c1, left, w, top, h, cell)
    local vx, vy = quad:getViewport()
    local u0 = (c0 - left) / w
    local u1 = (c1 + 1 - left) / w
    local tx0 = vx + u0 * cell
    local tw = (u1 - u0) * cell
    if tw < 0.001 then
        return
    end

    spriteQuad:setViewport(tx0, vy, tw, cell)
    spriteBatch:add(spriteQuad, c0, top, 0, (c1 - c0 + 1) / tw, h / cell)
end

function rc.horizonAt(player)
    if not ih then
        return 0
    end

    return math.floor(ih * 0.5 + (player.viewZ or 0) + (player.pitch or 0) * ih * 0.38) * (scale or 1)
end

-- Where the sight goes. The same line as the horizon but without the walk
-- and the recoil in it: the sight sits in the middle of the screen and only
-- leaves it when you look up or down on purpose.
function rc.sightAt(player)
    if not ih then
        return 0
    end

    return math.floor(ih * 0.5 + (player.pitch or 0) * ih * 0.38) * (scale or 1)
end

function rc.draw(world, player, w, h)
    if not canvas then
        rc.resize(w, h)
    end

    local horizon = math.floor(ih * 0.5 + (player.viewZ or 0)
        + (player.pitch or 0) * ih * 0.38)

    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)

    local lv = world.level
    love.graphics.setColor(lv.ceiling)
    love.graphics.draw(ceilMesh, 0, 0, 0, iw, math.max(1, horizon))
    love.graphics.setColor(lv.floor)
    love.graphics.draw(floorMesh, 0, horizon, 0, iw, math.max(1, ih - horizon))

    drawFlats(world, player, horizon)
    drawDecals(world, player, horizon)
    drawWalls(world, player, horizon)
    drawSprites(world, player, horizon)

    love.graphics.setCanvas()
    love.graphics.pop()

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, 0, 0, 0, scale, scale)
end

return rc
