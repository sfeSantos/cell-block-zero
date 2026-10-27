-- The renderer. One ray per column of an internal low resolution canvas, then
-- the canvas is blown up to the window with nearest filtering. Walls and
-- sprites both go through sprite batches, so a frame costs a handful of draw
-- calls no matter how busy the corridor is.

local textures = require("src.textures")
local art = require("src.art")

local rc = {}

rc.fov = math.rad(68)

local canvas, iw, ih, scale
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

function rc.load()
    wallBatch = love.graphics.newSpriteBatch(textures.image, 1024)
    spriteBatch = love.graphics.newSpriteBatch(art.sheet, 2048)
    wallQuad = love.graphics.newQuad(0, 0, 1, TEX, textures.image:getDimensions())
    spriteQuad = love.graphics.newQuad(0, 0, 1, 1, art.sheet:getDimensions())
    floorMesh = gradientMesh(false)
    ceilMesh = gradientMesh(true)
end

function rc.resize(w, h)
    scale = math.max(2, math.floor(h / 240))
    iw = math.ceil(w / scale)
    ih = math.ceil(h / scale)

    if canvas then
        canvas:release()
    end

    canvas = love.graphics.newCanvas(iw, ih)
    canvas:setFilter("nearest", "nearest")
    buildFlats()
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
    local halfFov = math.tan(rc.fov * 0.5)
    local planex, planey = -diry * halfFov, dirx * halfFov
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

local function drawWalls(world, player, horizon)
    local level = world.level
    local dirx, diry = math.cos(player.angle), math.sin(player.angle)
    local halfFov = math.tan(rc.fov * 0.5)
    local planex, planey = -diry * halfFov, dirx * halfFov
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
    local halfFov = math.tan(rc.fov * 0.5)
    local planex, planey = -diry * halfFov, dirx * halfFov
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
    drawWalls(world, player, horizon)
    drawSprites(world, player, horizon)

    love.graphics.setCanvas()
    love.graphics.pop()

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, 0, 0, 0, scale, scale)
end

return rc
