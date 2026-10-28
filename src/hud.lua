-- Status bar, the weapon in the player's hands, the overlays, and the screens
-- around the game itself. Everything is drawn with primitives and the default
-- font at a few sizes.

local art = require("src.art")
local weapons = require("src.weapons")
local World = require("src.world")
local Player = require("src.player")

local hud = {}

local fonts = {}

local KEY_COLOURS = {
    red = {0.85, 0.20, 0.18},
    blue = {0.28, 0.48, 0.90},
    yellow = {0.92, 0.80, 0.18},
}

hud.menuCount = 10

function hud.load()
    fonts.small = love.graphics.newFont(12)
    fonts.text = love.graphics.newFont(16)
    fonts.big = love.graphics.newFont(26)
    fonts.huge = love.graphics.newFont(48)
    love.graphics.setFont(fonts.text)
end

local function setColor(r, g, b, a)
    love.graphics.setColor(r, g, b, a or 1)
end

local function panel(x, y, w, h, alpha)
    setColor(0.06, 0.07, 0.09, alpha or 0.88)
    love.graphics.rectangle("fill", x, y, w, h)
    setColor(0.32, 0.34, 0.38, 0.9)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
end

local function bar(x, y, w, h, frac, r, g, b)
    setColor(0.10, 0.10, 0.12, 0.9)
    love.graphics.rectangle("fill", x, y, w, h)
    setColor(r, g, b, 1)
    love.graphics.rectangle("fill", x, y, w * math.max(0, math.min(1, frac)), h)
    setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
end

local function label(text, x, y, font, r, g, b)
    love.graphics.setFont(font or fonts.small)
    setColor(r or 0.62, g or 0.64, b or 0.68)
    love.graphics.print(text, x, y)
end

-- A mugshot that gets worse as the sentence goes on.
local function mugshot(x, y, s, player, hurt)
    local hp = player.health / 100
    setColor(0.14, 0.15, 0.18)
    love.graphics.rectangle("fill", x, y, 46 * s, 46 * s)
    setColor(0.76 - (1 - hp) * 0.25, 0.58 - (1 - hp) * 0.3, 0.46 - (1 - hp) * 0.3)
    love.graphics.rectangle("fill", x + 8 * s, y + 6 * s, 30 * s, 34 * s)
    setColor(0.22, 0.20, 0.19)
    love.graphics.rectangle("fill", x + 6 * s, y + 4 * s, 34 * s, 7 * s)

    local squint = (1 - hp) * 2 * s
    setColor(0.08, 0.08, 0.1)
    love.graphics.rectangle("fill", x + 13 * s, y + 17 * s + squint, 6 * s, 5 * s - squint)
    love.graphics.rectangle("fill", x + 27 * s, y + 17 * s + squint, 6 * s, 5 * s - squint)
    love.graphics.rectangle("fill", x + 18 * s, y + 31 * s, 10 * s, 2 * s + (1 - hp) * 3 * s)

    if hp < 0.75 then
        setColor(0.55, 0.08, 0.08, 0.8)
        love.graphics.rectangle("fill", x + 10 * s, y + 24 * s, 7 * s, 2 * s)
    end

    if hp < 0.4 then
        setColor(0.55, 0.08, 0.08, 0.8)
        love.graphics.rectangle("fill", x + 28 * s, y + 13 * s, 9 * s, 3 * s)
        love.graphics.rectangle("fill", x + 30 * s, y + 16 * s, 3 * s, 8 * s)
    end

    if hurt > 0 then
        setColor(0.8, 0.1, 0.1, math.min(0.5, hurt))
        love.graphics.rectangle("fill", x, y, 46 * s, 46 * s)
    end

    setColor(0.40, 0.42, 0.46)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, 46 * s - 1, 46 * s - 1)
end

local function drawWeaponView(world, w, h, barH)
    local player = world.player
    local kind, step = player:takedownFrame()
    local name, frame

    if kind then
        name, frame = kind, step
    elseif player.throwT > 0 and player.throwView then
        name = player.throwView
        frame = 2
    else
        local def = player:weaponDef()
        local quiet = player:silencedNow()
        local stage = player:reloadStage()
        local reload = art.RELOAD_VIEW[def.view]
        name = def.view

        if stage and reload then
            frame = (quiet and reload.quiet or reload.plain) + stage
        else
            frame = quiet and 3 or 1
            if player.fireT > 0 then
                frame = frame + 1
            end
        end
    end

    local quad = art.viewQuad(name, frame)
    if not quad then
        return
    end

    local scale = (h * (kind and 0.54 or 0.46)) / art.VIEW_H
    local sway = math.sin(player.bobT) * player:speed() * 2.4
    local rise = math.abs(math.cos(player.bobT)) * player:speed() * 1.1
    local x = w * 0.5 - art.VIEW_W * scale * 0.5 + sway + (kind and -w * 0.05 or 0)
    local y = h - barH * 0.35 - art.VIEW_H * scale + rise - player.kick * 1.1

    -- out of the line of sight while the magazine is changed: down and in
    -- towards the body, and a tilt that puts the other hand on it. A weapon
    -- with frames of its own only ducks a little, or the magazine coming out
    -- would happen below the edge of the screen.
    local dip = player:reloadDip()
    local tilt = 0

    -- and only to the gun. An execution puts the hands round his neck on
    -- screen instead, and the magazine being changed somewhere off to one
    -- side is no reason to drop those half a view down it.
    if kind then
        dip = 0
    end

    if dip > 0 then
        local own = art.RELOAD_VIEW[name] ~= nil
        y = y + art.VIEW_H * scale * (own and 0.18 or 0.52) * dip
        x = x + (own and 10 or 26) * dip
        tilt = (own and -0.12 or -0.30) * dip
    end

    setColor(1, 1, 1, 1)
    love.graphics.draw(art.views, quad, x + art.VIEW_W * scale * 0.5,
        y + art.VIEW_H * scale, tilt, scale, scale,
        art.VIEW_W * 0.5, art.VIEW_H)
end

local function drawCrosshair(world, w, h, horizon)
    local player = world.player
    if player.takedown then
        return
    end

    local x, y = w * 0.5, horizon
    local spread = 5 + player:speed() * 2 + player.fireT * 40
    setColor(0.85, 0.88, 0.92, 0.75)

    for _, d in ipairs({{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) do
        love.graphics.rectangle("fill", x + d[1] * spread - (d[1] == 0 and 1 or 0),
            y + d[2] * spread - (d[2] == 0 and 1 or 0),
            d[1] == 0 and 2 or 6, d[2] == 0 and 2 or 6)
    end
end

local function drawStatus(world, w, h, barH)
    local player = world.player
    local y = h - barH
    panel(0, y, w, barH, 0.92)

    local pad = math.floor(barH * 0.18)
    local s = barH / 70
    mugshot(pad, y + pad, s, player, player.hurtT)

    local col = pad + 56 * s
    local bw = math.max(90, w * 0.14)

    label("HEALTH", col, y + pad, fonts.small)
    bar(col, y + pad + 14, bw, 12, player.health / 100, 0.72, 0.18, 0.18)
    label(string.format("%d", math.floor(player.health)), col + bw + 8, y + pad + 13, fonts.text, 0.9, 0.9, 0.9)

    label("VEST", col, y + pad + 32, fonts.small)
    bar(col, y + pad + 46, bw, 12, player.armor / player.armorMax, 0.22, 0.46, 0.78)
    label(string.format("%d%%", math.floor(player.armor)), col + bw + 8, y + pad + 45, fonts.text, 0.9, 0.9, 0.9)

    local col2 = col + bw + 72
    local def = player:weaponDef()
    local quiet = player:silencedNow()

    label("WEAPON", col2, y + pad, fonts.small)
    love.graphics.setFont(fonts.text)
    setColor(0.92, 0.88, 0.70)
    love.graphics.print(def.name .. (quiet and " + can" or ""), col2, y + pad + 14)

    if def.ammo then
        label("AMMO", col2, y + pad + 38, fonts.small)
        local spare = math.floor(player.ammo[def.ammo] or 0)

        if def.clip then
            local inGun = player.mag[def.id] or 0
            local text = tostring(inGun)
            love.graphics.setFont(fonts.big)

            if inGun > 0 then
                setColor(0.94, 0.86, 0.42)
            else
                setColor(0.84, 0.36, 0.30)
            end

            love.graphics.print(text, col2 + 48, y + pad + 32)

            local tx = col2 + 54 + fonts.big:getWidth(text)
            love.graphics.setFont(fonts.small)

            if player.reloadT > 0 then
                setColor(0.90, 0.80, 0.40)
                love.graphics.print("LOADING", tx, y + pad + 44)
            else
                setColor(0.58, 0.58, 0.56)
                love.graphics.print("/ " .. spare, tx, y + pad + 44)
            end
        else
            love.graphics.setFont(fonts.big)
            setColor(0.94, 0.86, 0.42)
            love.graphics.print(tostring(spare), col2 + 48, y + pad + 32)
        end
    else
        label("no ammunition needed", col2, y + pad + 44, fonts.small)
    end

    if (player.ammo.traps or 0) > 0 then
        label(string.format("TRAPS  %d", player.ammo.traps), col2 + 110,
            y + pad + 44, fonts.small)
    end

    local col3 = w - math.max(190, w * 0.22)

    label("KEYS", col3, y + pad, fonts.small)
    local kx = col3
    for _, name in ipairs({"red", "blue", "yellow"}) do
        local c = KEY_COLOURS[name]
        if player.keys[name] then
            setColor(c[1], c[2], c[3])
        else
            setColor(0.16, 0.17, 0.19)
        end

        love.graphics.rectangle("fill", kx, y + pad + 16, 14, 14)
        setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("line", kx + 0.5, y + pad + 16.5, 13, 13)
        kx = kx + 20
    end

    label(string.format("GUARDS DOWN  %d / %d", world.killed, world.total),
        col3, y + pad + 38, fonts.small)
    label(string.format("SILENT  %d", player.takedowns), col3, y + pad + 54, fonts.small)

    if world.totalAllies > 0 then
        local standing = 0
        for _, a in ipairs(world.allies) do
            if a.alive and a.freed then
                standing = standing + 1
            end
        end

        label(string.format("FREED  %d / %d, %d up", world.freed, world.totalAllies,
            standing), col3 + 86, y + pad + 54, fonts.small)
    end

    local slots = {}
    for i, def2 in ipairs(weapons.list) do
        if player.has[def2.id] then
            slots[#slots + 1] = i
        end
    end

    local sx = col2
    love.graphics.setFont(fonts.small)
    for _, i in ipairs(slots) do
        local id = weapons.list[i].id
        if id == player.weapon then
            setColor(0.92, 0.84, 0.40)
        else
            setColor(0.34, 0.35, 0.38)
        end

        love.graphics.print(tostring(i), sx, y + pad + 62)
        sx = sx + 16
    end
end

-- F6: what the mouse is actually doing, for when turning feels wrong.
function hud.drawMouseDebug(info, w, h)
    local lines = {
        ("relative mode   %s claims it"):format(tostring(info.relative)),
        ("pointer moves   %s"):format(info.pointerLive and "yes, so it is not"
            or "no, so it is"),
        ("grabbed         %s"):format(tostring(info.grabbed)),
        ("window focus    %s"):format(tostring(info.focus)),
        ("input path      %s"):format(info.path),
        ("recentre        %s"):format(info.warp == nil and "not needed"
            or (info.warp and "works" or "refused")),
        ("last dx, dy     %+d, %+d"):format(info.dx or 0, info.dy or 0),
        ("turn setting    %s"):format(info.invertX > 0 and "normal" or "reversed"),
        ("mouse speed     %d of 9"):format(info.sens),
        ("angle           %.1f deg"):format(math.deg(info.angle)),
        ("turned this sec %+.1f deg"):format(math.deg(info.turned or 0)),
    }

    local font = fonts.small
    love.graphics.setFont(font)

    local boxW = 260
    local boxH = #lines * (font:getHeight() + 2) + 16
    local x, y = 14, math.floor(h * 0.30)

    setColor(0.03, 0.04, 0.06, 0.9)
    love.graphics.rectangle("fill", x, y, boxW, boxH)
    setColor(0.45, 0.70, 0.55, 0.8)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, boxW - 1, boxH - 1)

    setColor(0.80, 0.86, 0.80)
    for i, line in ipairs(lines) do
        love.graphics.print(line, x + 10, y + 8 + (i - 1) * (font:getHeight() + 2))
    end

    setColor(0.60, 0.62, 0.66)
    love.graphics.print("F6 hides this", x + 10, y + boxH - font:getHeight() - 6)
end

function hud.consoleFont()
    return fonts.small
end

function hud.draw(world, w, h, horizon)
    local player = world.player
    local barH = math.max(78, math.floor(h * 0.15))

    drawWeaponView(world, w, h, barH)

    if player.hurtT > 0 then
        setColor(0.65, 0.05, 0.05, math.min(0.45, player.hurtT * 0.7))
        love.graphics.rectangle("fill", 0, 0, w, h - barH)
    end

    if player.blind > 0 then
        setColor(1, 1, 1, math.min(0.92, player.blind * 0.75))
        love.graphics.rectangle("fill", 0, 0, w, h - barH)
    end

    drawCrosshair(world, w, h, horizon or (h - barH) * 0.5)

    if world.alarmT > 0 then
        -- the klaxon and the lockdown are not the same event and should not
        -- look like it: being seen flashes red, a pulled panel burns white
        local pulse = math.abs(math.sin(love.timer.getTime() * (world.lockdown and 9 or 6)))
        love.graphics.setFont(fonts.text)
        if world.lockdown then
            setColor(1, 0.86, 0.72, 0.5 + pulse * 0.5)
            love.graphics.printf("LOCKDOWN", 0, 18, w, "center")
        else
            setColor(0.9, 0.25, 0.2, 0.35 + pulse * 0.5)
            love.graphics.printf("ALARM", 0, 18, w, "center")
        end
    end

    local target = world:takedownTarget()
    if target and player:canTakedown() then
        love.graphics.setFont(fonts.text)
        setColor(0.95, 0.95, 0.8, 0.85)
        local verb = player.weapon == "hatchet" and "hatchet him" or "break his neck"
        love.graphics.printf("[fire] " .. verb, 0, h * 0.58, w, "center")
    elseif world.prisonerAhead and world:prisonerAhead() then
        love.graphics.setFont(fonts.text)
        setColor(0.85, 0.92, 0.95, 0.85)
        love.graphics.printf("[space] tell him to come with you", 0, h * 0.58, w, "center")
    elseif world.panelAhead and world:panelAhead() then
        love.graphics.setFont(fonts.text)
        setColor(0.88, 0.86, 0.72, 0.8)
        love.graphics.printf("[space] this section is loose", 0, h * 0.58, w, "center")
    end

    love.graphics.setFont(fonts.small)
    for i, m in ipairs(world.messages) do
        setColor(0.92, 0.90, 0.78, math.min(1, m.life))
        love.graphics.print(m.text, 14, 14 + (i - 1) * 16)
    end

    label(world.level.name, 14, h - barH - 22, fonts.small, 0.55, 0.57, 0.60)

    local chips = {}
    if player.god then
        chips[#chips + 1] = "GOD"
    end

    if player.invisible then
        chips[#chips + 1] = "INVISIBLE"
    end

    if player.endlessAmmo then
        chips[#chips + 1] = "ENDLESS AMMO"
    end

    if player.noclip then
        chips[#chips + 1] = "NOCLIP"
    end

    if world.frozen then
        chips[#chips + 1] = "GUARDS FROZEN"
    end

    if #chips > 0 then
        love.graphics.setFont(fonts.small)
        setColor(0.45, 0.88, 0.55, 0.9)
        love.graphics.printf(table.concat(chips, "   "), 0, h - barH - 22, w - 14, "right")
    end

    drawStatus(world, w, h, barH)
end

-- The minimap, a corner panel toggled with tab. Dead guards stay on it the way
-- the bodies stay on the floor.
function hud.drawMap(world, w, h)
    local level = world.level
    local player = world.player
    local cell = math.floor(math.min(w * 0.30 / level.w, h * 0.34 / level.h))
    cell = math.max(3, math.min(10, cell))

    local mw, mh = level.w * cell, level.h * cell
    local pad = 8
    local ox = math.floor(w - mw - pad * 2 - 10)
    local oy = 10 + pad

    setColor(0.03, 0.04, 0.05, 0.82)
    love.graphics.rectangle("fill", ox - pad, oy - pad, mw + pad * 2, mh + pad * 2)
    setColor(0.30, 0.32, 0.36, 0.7)
    love.graphics.rectangle("line", ox - pad + 0.5, oy - pad + 0.5,
        mw + pad * 2 - 1, mh + pad * 2 - 1)

    for cy = 1, level.h do
        for cx = 1, level.w do
            local i = level:index(cx, cy)
            local x, y = ox + (cx - 1) * cell, oy + (cy - 1) * cell
            if level.exit[i] then
                setColor(0.25, 0.85, 0.40, 0.95)
                love.graphics.rectangle("fill", x, y, cell, cell)
            elseif level.wall[i] then
                setColor(0.28, 0.29, 0.33, 0.95)
                love.graphics.rectangle("fill", x, y, cell, cell)
            elseif level.door[i] then
                local d = level.door[i]
                local c = d.lock and KEY_COLOURS[d.lock] or {0.58, 0.52, 0.30}
                setColor(c[1], c[2], c[3], 0.95)
                love.graphics.rectangle("fill", x, y, cell, cell)
            else
                setColor(0.11, 0.12, 0.14, 0.85)
                love.graphics.rectangle("fill", x, y, cell, cell)
            end
        end
    end

    for _, it in ipairs(world.items) do
        setColor(0.88, 0.82, 0.35, 0.9)
        love.graphics.rectangle("fill", ox + (it.x - 0.5) * cell - 1,
            oy + (it.y - 0.5) * cell - 1, 3, 3)
    end

    for _, e in ipairs(world.enemies) do
        if e.alive then
            if e.awake then
                setColor(0.92, 0.25, 0.20)
            else
                setColor(0.76, 0.56, 0.22)
            end
        else
            setColor(0.34, 0.12, 0.12)
        end

        love.graphics.circle("fill", ox + e.x * cell, oy + e.y * cell,
            math.max(1.5, cell * 0.3), 7)
    end

    setColor(0.3, 0.9, 1.0)
    local px, py = ox + player.x * cell, oy + player.y * cell
    local a = player.angle
    local r = math.max(3, cell * 0.8)
    love.graphics.polygon("fill",
        px + math.cos(a) * r, py + math.sin(a) * r,
        px + math.cos(a + 2.4) * r * 0.7, py + math.sin(a + 2.4) * r * 0.7,
        px + math.cos(a - 2.4) * r * 0.7, py + math.sin(a - 2.4) * r * 0.7)

    love.graphics.setFont(fonts.small)
    setColor(0.55, 0.57, 0.62)
    love.graphics.printf(level.name, ox - pad, oy + mh + pad - 1, mw + pad * 2, "center")
end

local MENU = {"Break out", "Block", "Difficulty", "Mouse input", "Turn",
    "Vertical look", "Mouse speed", "Shooting range", "Controls", "Quit"}

local WEB = love._os == "Web"

-- A browser tab has its own way out, and quitting there would only leave a
-- dead canvas behind, so the last line is dropped on the web build.
if WEB then
    MENU[#MENU] = nil
end

local MENU_TOP, MENU_STEP = 0.28, 34

-- Where the lines start and how far apart they sit. The menu grows lines
-- when there is a block to carry on with and a game in the save file, and
-- the window is not always a tall one, so both come out of the height: the
-- list keeps clear of the title above it and of the notes along the bottom.
local function geometry(h, count)
    local top = math.max(h * MENU_TOP, h * 0.16 + 70)
    local room = h - 92 - top

    return top, math.min(MENU_STEP, math.max(20, math.floor(room / count)))
end

hud.LINK = "github.com/sfeSantos/cell-block-zero"
hud.URL = "https://github.com/sfeSantos/cell-block-zero"

-- The menu grows lines at the top for what is going on right now: the block
-- you walked out of and left standing, and the game waiting in the save file.
-- main.lua says which ones, and in which order.
hud.extras = {}

local function items()
    local list = {}

    for _, extra in ipairs(hud.extras) do
        list[#list + 1] = extra.label
    end

    for _, item in ipairs(MENU) do
        list[#list + 1] = item
    end

    return list
end

function hud.setExtras(list)
    hud.extras = list or {}
    hud.resume = false

    for _, extra in ipairs(hud.extras) do
        if extra.id == "carryon" then
            hud.resume = true
        end
    end

    hud.menuCount = #items()
end

-- Which menu line the pointer is over, so the menu can be used with the mouse.
function hud.menuHit(mx, my, w, h)
    local list = items()
    local y0, step = geometry(h, #list)

    for i = 1, #list do
        local top = y0 + (i - 1) * step
        if my >= top - 5 and my < top + step - 5 then
            return i
        end
    end

    return nil
end

function hud.drawMenu(sel, cfg, saved, names, w, h)
    setColor(0.02, 0.02, 0.03, 0.82)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setFont(fonts.huge)
    setColor(0.90, 0.86, 0.70)
    love.graphics.printf("CELL BLOCK ZERO", 0, h * 0.16, w, "center")

    love.graphics.setFont(fonts.small)
    setColor(0.55, 0.56, 0.60)
    love.graphics.printf("a dead guard on your cell floor, and until sunrise to be gone",
        0, h * 0.16 + 56, w, "center")

    local list = items()
    local y, step = geometry(h, #list)

    for i, item in ipairs(list) do
        local text = item
        local k = i - #hud.extras

        if k == 2 then
            text = string.format("%s:  %d of %d, %s", item, cfg.block, #names,
                names[cfg.block] or "?")
        elseif k == 3 then
            text = item .. ":  " .. World.DIFFICULTY[cfg.difficulty].name
        elseif k == 4 then
            local mode = cfg.pointerMode == 1 and "pointer, edge turns" or "automatic"

            -- there is no edge turn in a browser: nothing there can move the
            -- pointer back, so the view follows it only while it is over the
            -- canvas
            if WEB and cfg.pointerMode == 1 then
                mode = "pointer, over the picture"
            end

            text = item .. ":  " .. mode
        elseif k == 5 then
            text = item .. ":  " .. (cfg.invertX > 0 and "normal" or "reversed")
        elseif k == 6 then
            local look = "normal"
            if cfg.invertY > 0 then
                look = "inverted"
            elseif cfg.invertY == 0 then
                look = "off"
            end

            text = item .. ":  " .. look
        elseif k == 7 then
            text = string.format("%s:  %d of %d", item, cfg.sens,
                #Player.SENSITIVITY)
        end

        if i == sel then
            setColor(0.95, 0.88, 0.45)
            love.graphics.setFont(fonts.big)
            love.graphics.printf("> " .. text .. " <", 0, y, w, "center")
        else
            setColor(0.60, 0.62, 0.66)
            love.graphics.setFont(fonts.text)
            love.graphics.printf(text, 0, y + 4, w, "center")
        end

        y = y + step
    end

    love.graphics.setFont(fonts.small)

    if hud.note then
        setColor(0.72, 0.78, 0.68)
        love.graphics.printf(hud.note, 0, h - 80, w, "center")
    end

    setColor(0.52, 0.48, 0.34)
    if saved.unlocked < #names then
        love.graphics.printf(string.format("blocks open: %d of %d, the next one unlocks"
            .. " when you walk out of this one", saved.unlocked, #names),
            0, h - 62, w, "center")
    else
        love.graphics.printf("every block is open", 0, h - 62, w, "center")
    end

    setColor(0.40, 0.42, 0.46)
    love.graphics.printf("arrows to choose, enter to pick, F1 for the controls",
        0, h - 44, w, "center")

    -- whose fault all this is, and where it lives
    local note = "made by Eduardo Santos      " .. hud.LINK
    local tw = fonts.small:getWidth(note)
    local tx, ty = math.floor((w - tw) * 0.5), math.floor(h - 24)
    hud.linkBox = {tx, ty, tw, 16}
    setColor(0.38, 0.40, 0.44)
    love.graphics.print(note, tx, ty)
end

-- The note at the bottom of the menu opens the repository when it is clicked.
function hud.linkHit(mx, my)
    local box = hud.linkBox
    if not box then
        return false
    end

    return mx >= box[1] and mx < box[1] + box[3]
        and my >= box[2] and my < box[2] + box[4]
end

function hud.drawBriefing(level, w, h, index, total)
    setColor(0.02, 0.02, 0.03, 0.92)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setFont(fonts.small)
    setColor(0.50, 0.52, 0.56)
    love.graphics.printf(string.format("BLOCK %d OF %d", index, total), 0, h * 0.26, w, "center")

    love.graphics.setFont(fonts.big)
    setColor(0.92, 0.88, 0.70)
    love.graphics.printf(level.name, 0, h * 0.26 + 26, w, "center")

    love.graphics.setFont(fonts.text)
    setColor(0.70, 0.72, 0.74)
    love.graphics.printf(level.brief, w * 0.2, h * 0.42, w * 0.6, "center")

    love.graphics.setFont(fonts.small)
    setColor(0.45, 0.47, 0.50)
    love.graphics.printf("press enter", 0, h * 0.74, w, "center")
end

function hud.drawDead(world, w, h)
    setColor(0.35, 0.02, 0.02, 0.55)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setFont(fonts.huge)
    setColor(0.85, 0.75, 0.70)
    love.graphics.printf("YOU DIED IN HERE", 0, h * 0.38, w, "center")

    love.graphics.setFont(fonts.text)
    setColor(0.75, 0.70, 0.68)
    love.graphics.printf(string.format("%d guards down, %d of them quietly",
        world.killed, world.player.takedowns), 0, h * 0.38 + 64, w, "center")

    love.graphics.setFont(fonts.small)
    setColor(0.55, 0.52, 0.50)
    love.graphics.printf("enter to try the block again, escape for the menu",
        0, h * 0.38 + 100, w, "center")
end

local function clock(seconds)
    return string.format("%d:%02d", math.floor(seconds / 60),
        math.floor(seconds % 60))
end

local function countOf(n, one, many)
    return string.format("%d %s", n, n == 1 and one or many)
end

-- The block, totted up. Shown on the way out of every block, before the next
-- one starts, because what you walked past matters as much as what you shot.
function hud.drawReport(r, w, h, last)
    setColor(0.02, 0.02, 0.03, 0.93)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setFont(fonts.big)
    setColor(0.90, 0.86, 0.70)
    love.graphics.printf(r.level .. " is behind you", 0, h * 0.10, w, "center")

    love.graphics.setFont(fonts.huge)
    setColor(0.95, 0.88, 0.45)
    love.graphics.printf(clock(r.time), 0, h * 0.10 + 40, w, "center")

    local rows = {}

    for _, rank in ipairs(r.ranks) do
        rows[#rows + 1] = {rank.name,
            string.format("%d of %d down", rank.killed, rank.total)}
    end

    if r.quiet > 0 or r.asleep > 0 then
        local how = countOf(r.quiet, "of them never heard it", "of them never heard it")
        if r.asleep > 0 then
            how = how .. ", " .. countOf(r.asleep, "in his sleep", "in their sleep")
        end

        rows[#rows + 1] = {"Quietly", how}
    end

    rows[#rows + 1] = {"", ""}
    rows[#rows + 1] = {"Lockers", string.format("%d of %d opened%s",
        r.lockers.open, r.lockers.total,
        r.lockers.missed > 0
            and string.format(", and %d of the ones you left were not empty",
                r.lockers.missed)
            or "")}

    if r.panels.total > 0 then
        rows[#rows + 1] = {"Loose panels",
            string.format("%d of %d pushed", r.panels.open, r.panels.total)}
    end

    rows[#rows + 1] = {"Picked up",
        string.format("%d of %d", r.items.taken, r.items.total)}

    if r.prisoners.total > 0 then
        rows[#rows + 1] = {"Prisoners",
            string.format("%d of %d let out", r.prisoners.freed, r.prisoners.total)}
    end

    rows[#rows + 1] = {"Alarm", r.alarms == 0 and "never went off"
        or countOf(r.alarms, "time", "times")}

    if r.alarmPanels and r.alarmPanels.total > 0 then
        rows[#rows + 1] = {"Alarm panels", r.alarmPanels.pulled == 0
            and "nobody reached one"
            or string.format("%d of %d pulled", r.alarmPanels.pulled,
                r.alarmPanels.total)}
    end

    rows[#rows + 1] = {"Walked out with",
        string.format("%d health and %d vest", r.health, r.vest)}

    local y = h * 0.30
    love.graphics.setFont(fonts.text)
    for _, row in ipairs(rows) do
        if row[1] ~= "" then
            setColor(0.58, 0.60, 0.64)
            love.graphics.printf(row[1], w * 0.18, y, w * 0.28, "right")
            setColor(0.86, 0.84, 0.76)
            love.graphics.print(row[2], w * 0.50, y)
        end

        y = y + 26
    end

    love.graphics.setFont(fonts.small)
    setColor(0.50, 0.52, 0.56)
    love.graphics.printf(last and "enter for the way out"
        or "enter for the next block", 0, h * 0.88, w, "center")
end

function hud.drawWin(stats, w, h)
    setColor(0.02, 0.03, 0.02, 0.88)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setFont(fonts.huge)
    setColor(0.70, 0.92, 0.75)
    love.graphics.printf("OUT", 0, h * 0.26, w, "center")

    love.graphics.setFont(fonts.text)
    setColor(0.80, 0.84, 0.80)
    love.graphics.printf("The fence is behind you and nobody is counting heads yet.",
        w * 0.15, h * 0.26 + 70, w * 0.7, "center")

    love.graphics.setFont(fonts.text)
    setColor(0.75, 0.78, 0.76)
    love.graphics.printf(string.format("time %s\nguards down %d\nsilent kills %d",
        stats.time, stats.kills, stats.takedowns), 0, h * 0.52, w, "center")

    love.graphics.setFont(fonts.small)
    setColor(0.50, 0.54, 0.52)
    love.graphics.printf("enter for the menu", 0, h * 0.78, w, "center")
end

function hud.drawPause(w, h)
    setColor(0.02, 0.02, 0.03, 0.6)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setFont(fonts.big)
    setColor(0.88, 0.86, 0.76)
    love.graphics.printf("PAUSED", 0, h * 0.44, w, "center")
    love.graphics.setFont(fonts.small)
    setColor(0.50, 0.52, 0.56)
    love.graphics.printf("P to carry on, escape for the menu, which keeps the block as it is",
        0, h * 0.44 + 40, w, "center")
end

local CONTROLS = {
    {"walk", "W and S"},
    {"step sideways", "A and D"},
    {"turn", "the mouse, the arrows, Q and E, or alt with A and D"},
    {"look up and down", "mouse, page up and page down, home to centre"},
    {"pointer stuck at the edge", "menu: Mouse input, pointer"},
    {"turning the wrong way", "menu: Turn, normal or reversed"},
    {"vertical look", "menu: inverted, normal, or off"},
    {"mouse speed", "[ and ] while playing, or the menu"},
    {"run", "shift"},
    {"fire, or execute", "left mouse button, or ctrl"},
    {"use doors and the exit", "space"},
    {"free a prisoner", "space, standing in front of him"},
    {"open a locker", "space, facing it"},
    {"push a section of wall", "space, if it is one of those"},
    {"weapons", "1 to 7, or the mouse wheel"},
    {"throw a grenade", "G"},
    {"throw a flash grenade", "F"},
    {"throw a knife", "V, without putting your gun away"},
    {"reload", "R, or pull the trigger on an empty magazine"},
    {"set a trap", "B, on the floor in front of you"},
    {"silencer on and off", "T, or the middle mouse button"},
    {"map on and off", "tab"},
    {"pause", "P, or escape for the menu and Carry on to come back"},
    {"save the block as it is", "F9, or the line in the menu"},
    {"load the saved game", "menu: Load the saved game"},
    {"developer console", "F2 or the tilde key, then help"},
    {"cheats", "F3 god, F4 invisible, F5 endless ammunition"},
    {"fullscreen", "F11"},
}

function hud.drawControls(w, h)
    setColor(0.02, 0.02, 0.03, 0.92)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setFont(fonts.big)
    setColor(0.90, 0.86, 0.70)
    love.graphics.printf("CONTROLS", 0, h * 0.12, w, "center")

    local y = h * 0.12 + 60
    love.graphics.setFont(fonts.text)
    for _, row in ipairs(CONTROLS) do
        setColor(0.60, 0.62, 0.66)
        love.graphics.printf(row[1], w * 0.1, y, w * 0.35, "right")
        setColor(0.88, 0.86, 0.76)
        love.graphics.print(row[2], w * 0.49, y)
        y = y + 26
    end

    love.graphics.setFont(fonts.small)
    setColor(0.45, 0.47, 0.50)
    love.graphics.printf("any key to go back", 0, h - 46, w, "center")
end

return hud
