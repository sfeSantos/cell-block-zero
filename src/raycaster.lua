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

local TEX = 64

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

    drawWalls(world, player, horizon)
    drawSprites(world, player, horizon)

    love.graphics.setCanvas()
    love.graphics.pop()

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, 0, 0, 0, scale, scale)
end

return rc
