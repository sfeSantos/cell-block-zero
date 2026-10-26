-- Cell Block Zero, a Wolfenstein shaped prison break for LOVE 11.x.
-- Levels are text files in levels/, everything else is generated at load time.

local textures = require("src.textures")
local art = require("src.art")
local rc = require("src.raycaster")
local hud = require("src.hud")
local audio = require("src.audio")
local World = require("src.world")
local progress = require("src.progress")
local save = require("src.save")
local Level = require("src.level")
local Player = require("src.player")
local console = require("src.console")

local LEVELS = {"levels/01.txt", "levels/02.txt", "levels/03.txt"}
local NAMES = {}

local state = "menu"
local cfg = {difficulty = 2, block = 1, invertY = -1, invertX = 1,
    sens = Player.SENS_DEFAULT, pointerMode = 0}
local saved = {unlocked = 1}
local world, entryCarry, entryPath
local menuSel = 1
local report, reportNext
local savedGame
local showControls = false
local showMap = false
local paused = false
local endT = 0
local stats = {time = "0:00", kills = 0, takedowns = 0}
local startTime = 0

local RANGE = "levels/range.txt"
local menuMove, menuPick, refreshExtras

local function indexOf(path)
    for i, p in ipairs(LEVELS) do
        if p == path then
            return i
        end
    end

    return nil
end

local function clock(seconds)
    return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

local mouseGrabbed = false
local skipMotion = false
local lastMouseX, lastMouseY
local pendingDx, pendingDy = 0, 0
local pointerLive = false
local moveAge = 99
local blankCursor
local mouseDebug = false
local warpAt, warpOk
local mouseInfo = {path = "none", dx = 0, dy = 0, turned = 0, angle = 0}
local turnWatch = {angle = 0, t = 0}

local function grabMouse(on)
    if on == mouseGrabbed then
        return
    end

    mouseGrabbed = on
    lastMouseX, lastMouseY = nil, nil
    pendingDx, pendingDy = 0, 0
    pointerLive = false

    -- in pointer mode the game never asks for relative mode: it drives the
    -- view from the pointer itself and turns on its own at the edges, which
    -- is the way out when a window manager claims relative mode and does
    -- nothing about it
    love.mouse.setRelativeMode(on and cfg.pointerMode ~= 1)
    love.mouse.setGrabbed(on)
    love.mouse.setVisible(not on)

    -- hiding the cursor is ignored by some window managers, so put an empty
    -- one on as well and the arrow goes away whatever they think about it
    if blankCursor then
        if on then
            love.mouse.setCursor(blankCursor)
        else
            love.mouse.setCursor()
        end
    end

    if on then
        local w, h = love.graphics.getDimensions()
        love.mouse.setPosition(math.floor(w * 0.5), math.floor(h * 0.5))
    end

    -- the pointer jumps when the mode changes, and that jump arrives as a
    -- motion event we must not read as aiming
    skipMotion = true
end

local function loadLevel(path, carry)
    local w, err = World.load(path, cfg.difficulty, carry, audio)
    if not w then
        print("level error: " .. tostring(err))
        state = "menu"

        return false
    end

    world = w
    entryPath = path
    entryCarry = carry
    endT = 0
    state = "briefing"
    hud.setExtras({})
    grabMouse(false)

    return true
end

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setBackgroundColor(0.02, 0.02, 0.03)
    love.math.setRandomSeed(os.time())

    saved = progress.load()
    cfg.block = math.min(cfg.block, saved.unlocked)
    cfg.difficulty = saved.difficulty
    cfg.invertY = saved.invertY
    cfg.invertX = saved.invertX
    cfg.pointerMode = saved.pointerMode
    cfg.sens = math.max(1, math.min(#Player.SENSITIVITY, saved.sens))

    for i, path in ipairs(LEVELS) do
        local lv = Level.load(path)
        NAMES[i] = lv and lv.name or path
    end

    local blank = love.image.newImageData(2, 2)
    local ok, cursor = pcall(love.mouse.newCursor, blank, 0, 0)
    blankCursor = ok and cursor or nil

    textures.load()
    art.load()
    rc.load()
    rc.resize(love.graphics.getDimensions())
    hud.load()
    audio.load()
    refreshExtras(false)
end

local function applyMouse()
    if world then
        world.player.invertY = cfg.invertY
        world.player.invertX = cfg.invertX
        world.player.sensitivity = Player.SENSITIVITY[cfg.sens]
    end
end

local function devContext()
    return {
        world = world,
        loadBlock = function(n)
            if not LEVELS[n] then
                return false
            end

            loadLevel(LEVELS[n], nil)
            state = "play"
            grabMouse(true)

            return true
        end,
        loadRange = function()
            loadLevel(RANGE, nil)
            state = "play"
            grabMouse(true)
        end,
        restart = function()
            loadLevel(entryPath, entryCarry)
            state = "play"
            grabMouse(true)
        end,
    }
end

local function cheat(name)
    if not world then
        return
    end

    local p = world.player
    if name == "god" then
        p.god = not p.god
        world:message("God mode " .. (p.god and "on" or "off"))
    elseif name == "invis" then
        p.invisible = not p.invisible
        world:message("Invisibility " .. (p.invisible and "on" or "off"))
    elseif name == "ammo" then
        p.endlessAmmo = not p.endlessAmmo
        world:message("Endless ammunition " .. (p.endlessAmmo and "on" or "off"))
    end

    world.audio.play("click", 0.4)
end

-- The clock is only running while the block is. Standing in the menu, or
-- paused, costs nothing on the time at the end.
local pausedAt

local function holdClock()
    pausedAt = pausedAt or love.timer.getTime()
end

local function releaseClock()
    if pausedAt and startTime then
        startTime = startTime + (love.timer.getTime() - pausedAt)
    end

    pausedAt = nil
end

local function beginPlay()
    applyMouse()
    state = "play"
    paused = false
    pausedAt = nil
    startTime = love.timer.getTime()
    grabMouse(true)
end

-- The lines at the top of the menu: the block left standing, saving it, and
-- the game waiting in the save file.
function refreshExtras(keep)
    local list = {}

    if keep and world then
        list[#list + 1] = {id = "carryon", label = "Carry on"}
        list[#list + 1] = {id = "savegame", label = "Save the block as it is"}
    end

    savedGame = save.read()
    if savedGame then
        list[#list + 1] = {id = "loadgame",
            label = "Load the saved game: " .. (savedGame.name or "a block")}
    end

    hud.setExtras(list)
end

-- Out to the menu with the block left exactly as it is, and back into it from
-- the line the menu grows at the top.
local function toMenu(keep)
    state = "menu"
    grabMouse(false)
    hud.note = nil
    refreshExtras(keep)

    if keep then
        paused = true
        menuSel = 1
        holdClock()
    else
        world = nil
        paused = false
    end

    menuSel = math.min(menuSel, hud.menuCount)
end

local function saveGame(fromMenu)
    if not world or not world.player.alive then
        return false
    end

    local elapsed = love.timer.getTime() - (startTime or love.timer.getTime())
    if pausedAt then
        elapsed = pausedAt - (startTime or pausedAt)
    end

    if not save.write(world, entryPath, cfg.difficulty, elapsed) then
        return false
    end

    if fromMenu then
        hud.note = "Saved. The block waits for you in the save file."
        refreshExtras(true)
    else
        world:message("Block saved")
    end

    return true
end

local function loadSaved()
    local data = savedGame or save.read()
    if not data then
        return false
    end

    local w = save.restore(data, audio)
    if not w then
        return false
    end

    world = w
    entryPath = data.level
    entryCarry = Player.carryOver(w.player, w.level.spawn)
    endT = 0
    hud.note = nil
    hud.setExtras({})
    applyMouse()
    state = "play"
    paused = false
    pausedAt = nil
    startTime = love.timer.getTime() - (data.elapsed or 0)
    grabMouse(true)

    return true
end

local function carryOn()
    if not world then
        return
    end

    applyMouse()
    state = "play"
    paused = false
    releaseClock()
    grabMouse(true)
end

-- The way out of a block goes through the report: what it cost, what was
-- left in it, and how long it took. Enter carries on into the next one.
local function showReport(nextPath)
    report = world:report()
    reportNext = nextPath
    state = "report"
    holdClock()
    grabMouse(false)
end

local function leaveReport()
    releaseClock()

    if reportNext then
        loadLevel(reportNext, world.player)
        reportNext = nil

        return
    end

    stats.time = clock(love.timer.getTime() - startTime)
    stats.kills = world.player.kills
    stats.takedowns = world.player.takedowns
    state = "win"
end

local function finishLevel()
    local done = world.finished

    local n = indexOf(entryPath)
    if done ~= "dead" and n then
        if progress.finished(saved, n, #LEVELS) then
            cfg.block = math.max(cfg.block, math.min(#LEVELS, n + 1))
        end
    end

    if done == "next" then
        local nextPath = world.level.next
        if nextPath and not nextPath:match("^levels/") then
            nextPath = "levels/" .. nextPath
        end

        if nextPath then
            showReport(nextPath)

            return
        end

        done = "escaped"
    end

    if done == "escaped" then
        showReport(nil)

        return
    end

    state = "dead"
    grabMouse(false)
end

-- The pointer belongs to the game while a block is being played. Window
-- managers do not all agree about relative mode, about focus events, or about
-- letting a game move the pointer, so there are three layers here: relative
-- mode when it works, otherwise the distance between two readings of the
-- pointer, and on top of that a steady turn while the pointer is parked
-- against an edge, which is the only thing left when the recentre is refused
-- and the pointer has nowhere further to go.
local EDGE_BAND = 0.12
local EDGE_TURN = 2.6        -- radians a second of turn at full deflection
local EDGE_GRACE = 0.25      -- seconds of stillness before the edge lets go

local function holdMouse(dt)
    if state ~= "play" or paused or showControls or console.open or not world then
        lastMouseX, lastMouseY = nil, nil
        pendingDx, pendingDy = 0, 0

        return
    end

    local focused = love.window.hasFocus()
    if focused ~= mouseGrabbed then
        grabMouse(focused)
    end

    if not focused then
        return
    end

    -- a warp we asked for last frame that produced no movement event has
    -- nothing left to swallow
    skipMotion = false

    local w, h = love.graphics.getDimensions()
    local mx, my = love.mouse.getPosition()

    -- did last frame's recentre take? Some window managers refuse to move the
    -- pointer at all, and then the edge turn below is the only way round
    if warpAt then
        -- did it at least move towards the middle? Checking for the exact
        -- centre reads as a refusal whenever the hand is still moving, and
        -- that used to switch the recentre off for the rest of the session
        local was = math.abs(warpAt.from - warpAt.x)
        local now = math.abs(mx - warpAt.x)
        warpOk = now < math.max(8, was * 0.6)
        warpAt = nil
    end

    local dx, dy = pendingDx, pendingDy
    pendingDx, pendingDy = 0, 0

    local px, py = 0, 0
    if lastMouseX then
        px, py = mx - lastMouseX, my - lastMouseY
    end

    lastMouseX, lastMouseY = mx, my

    -- A pointer that really moves means relative mode is not doing its job,
    -- whatever it claims. Motion events are preferred when they arrive, the
    -- pointer is read when they do not, and the two are never added together.
    if cfg.pointerMode == 1 or math.abs(px) > 1 or math.abs(py) > 1 then
        pointerLive = true
    end

    if dx ~= 0 or dy ~= 0 or px ~= 0 or py ~= 0 then
        moveAge = 0
    elseif dt then
        moveAge = moveAge + dt
    end

    if dx ~= 0 or dy ~= 0 then
        mouseInfo.path = pointerLive and "pointer events" or "relative events"
        mouseInfo.dx, mouseInfo.dy = dx, dy
        world.player:look(dx, dy)
    elseif px ~= 0 or py ~= 0 then
        mouseInfo.path = "pointer reading"
        mouseInfo.dx, mouseInfo.dy = px, py
        world.player:look(px, py)
    end

    if not pointerLive then
        return
    end

    -- the pointer is loose in the window: keep turning while it is parked
    -- against an edge, and try to drag it back to the middle
    local band = math.min(w, h) * EDGE_BAND
    local pan = 0
    if mx < band then
        pan = (mx - band) / band
    elseif mx > w - band then
        pan = (mx - (w - band)) / band
    end

    -- only while the hand is still moving: a pointer parked out there is
    -- somebody who put the mouse down, not somebody pushing against the edge
    if pan ~= 0 and dt and moveAge < EDGE_GRACE then
        local step = Player.SENSITIVITY[cfg.sens] / Player.SENSITIVITY[Player.SENS_DEFAULT]
        local rate = EDGE_TURN * math.max(0.6, math.min(2, step))
        mouseInfo.path = "edge turn"
        world.player:turn(pan * rate * dt)
    end

    -- Drag the pointer back to the middle long before it can reach an edge or
    -- leave the window. This is attempted every time it strays, whatever
    -- happened last time: a window manager that ignores it costs us nothing.
    local cx, cy = math.floor(w * 0.5), math.floor(h * 0.5)
    local slack = (cfg.pointerMode == 1 and 0.15 or 0.25)
    if math.abs(mx - cx) > w * slack or math.abs(my - cy) > h * slack then
        warpAt = {x = cx, y = cy, from = mx}
        love.mouse.setPosition(cx, cy)

        -- read it back rather than assume: a warp that was ignored leaves the
        -- pointer where it was, and assuming otherwise invents a movement the
        -- size of the window every single frame
        lastMouseX, lastMouseY = love.mouse.getPosition()
        skipMotion = true
    end
end

function love.update(dt)
    if dt > 0.05 then
        dt = 0.05
    end

    holdMouse(dt)

    if state ~= "play" or paused or showControls or console.open then
        return
    end

    if mouseDebug then
        local a = world.player.angle
        turnWatch.t = turnWatch.t + dt
        local d = math.atan2(math.sin(a - turnWatch.angle), math.cos(a - turnWatch.angle))
        turnWatch.sum = (turnWatch.sum or 0) + d
        turnWatch.angle = a
        if turnWatch.t >= 1 then
            mouseInfo.turned = turnWatch.sum
            turnWatch.sum, turnWatch.t = 0, 0
        end
    end

    world:update(dt)

    if world.finished then
        endT = endT + dt
        local wait = world.finished == "dead" and 1.7 or 0.7
        if endT >= wait then
            finishLevel()
        end
    end
end

function love.draw()
    local w, h = love.graphics.getDimensions()

    if world and (state == "play" or state == "dead" or state == "report") then
        rc.draw(world, world.player, w, h)

        if state ~= "report" then
            hud.draw(world, w, h, rc.sightAt(world.player))
        end

        if showMap and state ~= "report" then
            hud.drawMap(world, w, h)
        end

        if mouseDebug then
            mouseInfo.relative = love.mouse.getRelativeMode()
            mouseInfo.grabbed = mouseGrabbed
            mouseInfo.focus = love.window.hasFocus()
            mouseInfo.invertX = cfg.invertX
            mouseInfo.sens = cfg.sens
            mouseInfo.warp = warpOk
            mouseInfo.pointerLive = pointerLive
            mouseInfo.angle = world.player.angle
            hud.drawMouseDebug(mouseInfo, w, h)
        end

        if paused then
            hud.drawPause(w, h)
        end

        if state == "dead" then
            hud.drawDead(world, w, h)
        elseif state == "report" then
            hud.drawReport(report, w, h, reportNext == nil)
        end
    elseif state == "briefing" then
        hud.drawBriefing(world.level, w, h, indexOf(entryPath) or 0, #LEVELS)
    elseif state == "win" then
        hud.drawWin(stats, w, h)
    else
        hud.drawMenu(menuSel, cfg, saved, NAMES, w, h)
    end

    if showControls then
        hud.drawControls(w, h)
    end

    if console.open then
        console.draw(w, h, hud.consoleFont())
    end
end

function love.resize(w, h)
    rc.resize(w, h)
end

function love.mousemoved(x, y, dx, dy)
    if state == "menu" and not showControls then
        local w, h = love.graphics.getDimensions()
        menuSel = hud.menuHit(x, y, w, h) or menuSel
    end

    -- our own warp back to the middle arrives here as a movement, and it is
    -- the only one worth throwing away
    if skipMotion then
        skipMotion = false

        return
    end

    if state == "play" and not paused and not showControls and world then
        pendingDx = pendingDx + dx
        pendingDy = pendingDy + dy
    end
end

function love.wheelmoved(_, y)
    if state == "menu" then
        menuSel = (menuSel - 1 + (y > 0 and -1 or 1)) % hud.menuCount + 1

        return
    end

    if state == "play" and not paused and not console.open and world then
        world.player:cycle(y > 0 and 1 or -1)
    end
end

function love.mousepressed(x, y, button)
    if showControls then
        showControls = false

        return
    end

    if console.open then
        return
    end

    if state == "menu" then
        if button == 1 then
            local w, h = love.graphics.getDimensions()
            local hit = hud.menuHit(x, y, w, h)

            if hit then
                menuSel = hit
                menuPick()
            elseif hud.linkHit(x, y) and love.system then
                love.system.openURL(hud.URL)
            end
        end

        return
    end

    if state == "briefing" then
        if button == 1 then
            beginPlay()
        end

        return
    end

    if state == "report" then
        if button == 1 then
            leaveReport()
        end

        return
    end

    if state == "win" then
        if button == 1 then
            toMenu(false)
        end

        return
    end

    if state == "dead" then
        if button == 1 then
            loadLevel(entryPath, entryCarry)
        end

        return
    end

    if state ~= "play" or paused or not world then
        return
    end

    if not mouseGrabbed then
        grabMouse(true)

        return
    end

    if button == 2 then
        world.player:quickThrow("grenades", world)
    elseif button == 3 then
        world.player:toggleSilencer(world)
    end
end

local MENU_ACTIONS = {"start", "block", "difficulty", "pointer", "turn",
    "vertical", "sens", "range", "controls", "quit"}

local function menuAction(i)
    local extras = hud.extras or {}
    if i <= #extras then
        return extras[i].id
    end

    return MENU_ACTIONS[i - #extras]
end

function menuMove(d)
    local what = menuAction(menuSel)

    if what == "block" then
        cfg.block = (cfg.block - 1 + d) % saved.unlocked + 1
    elseif what == "difficulty" then
        cfg.difficulty = (cfg.difficulty - 1 + d) % #World.DIFFICULTY + 1
    elseif what == "pointer" then
        cfg.pointerMode = cfg.pointerMode == 1 and 0 or 1
    elseif what == "turn" then
        cfg.invertX = -cfg.invertX
    elseif what == "vertical" then
        local order = {[1] = -1, [-1] = 0, [0] = 1}
        cfg.invertY = order[cfg.invertY] or 1
    elseif what == "sens" then
        cfg.sens = math.max(1, math.min(#Player.SENSITIVITY, cfg.sens + d))
    end

    saved.difficulty = cfg.difficulty
    saved.invertY = cfg.invertY
    saved.invertX = cfg.invertX
    saved.pointerMode = cfg.pointerMode
    saved.sens = cfg.sens
    progress.save(saved)
    applyMouse()
end

function menuPick()
    local what = menuAction(menuSel)

    if what == "carryon" then
        carryOn()
    elseif what == "savegame" then
        saveGame(true)
    elseif what == "loadgame" then
        loadSaved()
    elseif what == "start" then
        loadLevel(LEVELS[math.min(cfg.block, saved.unlocked)], nil)
    elseif what == "range" then
        loadLevel(RANGE, nil)
    elseif what == "controls" then
        showControls = true
    elseif what == "quit" then
        love.event.quit()
    else
        menuMove(1)
    end
end

function love.textinput(text)
    if console.open then
        console.textinput(text)
    end
end

function love.keypressed(key)
    if key == "f2" or key == "`" then
        if world then
            console.toggle()
            grabMouse(not console.open and state == "play" and not paused)
        end

        return
    end

    if console.open then
        console.keypressed(key, devContext())
        if not console.open then
            grabMouse(state == "play" and not paused)
        end

        return
    end

    if key == "f3" then
        cheat("god")

        return
    end

    if key == "f6" then
        mouseDebug = not mouseDebug

        return
    end

    if key == "f4" then
        cheat("invis")

        return
    end

    if key == "f5" then
        cheat("ammo")

        return
    end

    if key == "f11" then
        love.window.setFullscreen(not love.window.getFullscreen())

        return
    end

    if showControls then
        showControls = false

        return
    end

    if key == "f1" then
        showControls = true

        return
    end

    if state == "menu" then
        if key == "up" then
            menuSel = (menuSel - 2) % hud.menuCount + 1
        elseif key == "down" then
            menuSel = menuSel % hud.menuCount + 1
        elseif key == "left" then
            menuMove(-1)
        elseif key == "right" then
            menuMove(1)
        elseif key == "return" or key == "kpenter" or key == "space" then
            menuPick()
        elseif key == "escape" then
            if hud.resume then
                carryOn()
            else
                love.event.quit()
            end
        end

        return
    end

    if state == "briefing" then
        if key == "return" or key == "kpenter" or key == "space" then
            beginPlay()
        elseif key == "escape" then
            state = "menu"
        end

        return
    end

    if state == "report" then
        if key == "return" or key == "kpenter" or key == "space" then
            leaveReport()
        elseif key == "escape" then
            toMenu(false)
        end

        return
    end

    if state == "win" then
        if key == "return" or key == "kpenter" or key == "escape" then
            toMenu(false)
        end

        return
    end

    if state == "dead" then
        if key == "return" or key == "kpenter" then
            loadLevel(entryPath, entryCarry)
        elseif key == "escape" then
            toMenu(false)
        end

        return
    end

    if key == "escape" then
        toMenu(true)

        return
    end

    if key == "f9" then
        saveGame(false)

        return
    end

    if key == "p" then
        paused = not paused
        grabMouse(not paused)

        if paused then
            holdClock()
        else
            releaseClock()
        end

        return
    end

    if paused then
        return
    end

    local player = world.player

    if key == "space" then
        player:use(world)
    elseif key == "g" then
        player:quickThrow("grenades", world)
    elseif key == "f" then
        player:quickThrow("flashes", world)
    elseif key == "r" then
        player:quickThrow("knife", world)
    elseif key == "b" then
        world:placeTrap(player)
    elseif key == "t" then
        player:toggleSilencer(world)
    elseif key == "[" or key == "]" then
        cfg.sens = math.max(1, math.min(#Player.SENSITIVITY,
            cfg.sens + (key == "]" and 1 or -1)))
        saved.sens = cfg.sens
        progress.save(saved)
        applyMouse()
        world:message(string.format("Mouse speed %d of %d", cfg.sens,
            #Player.SENSITIVITY))
    elseif key == "tab" then
        showMap = not showMap
    elseif key >= "1" and key <= "7" then
        player:select(tonumber(key))
    end
end

-- The pointer wandering out of the window takes the mouse with it, so take it
-- back as soon as it is noticed.
function love.mousefocus(inside)
    if not inside and state == "play" and not paused and not console.open and world then
        love.mouse.setGrabbed(true)
        local w, h = love.graphics.getDimensions()
        love.mouse.setPosition(math.floor(w * 0.5), math.floor(h * 0.5))
        lastMouseX, lastMouseY = nil, nil
        skipMotion = true
    end
end

function love.focus(focused)
    if state == "play" and not paused then
        grabMouse(focused)
    end
end

function love.visible(visible)
    if not visible then
        grabMouse(false)
    end
end
