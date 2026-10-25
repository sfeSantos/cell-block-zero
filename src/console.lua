-- A developer console, opened with F2 or the tilde key. It is the way in to
-- the cheats and to the testing commands: spawning guards, clearing them,
-- sending them back to their round, freezing them, reading damage numbers.
-- Nothing in here runs unless you open it.

local weapons = require("src.weapons")
local Enemy = require("src.enemy")

local console = {}

console.open = false
console.line = ""
console.log = {}
console.recall = {}
console.recallAt = 0

local MAX_LOG = 12

local function say(fmt, ...)
    local text = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    table.insert(console.log, text)
    while #console.log > MAX_LOG do
        table.remove(console.log, 1)
    end
end

console.say = say

local function onOff(v)
    return v and "on" or "off"
end

local function toggle(current, v)
    if v == nil then
        return not current
    end

    return v
end

local function want(args, i)
    local v = args[i]
    if v == "on" or v == "1" or v == "true" then
        return true
    elseif v == "off" or v == "0" or v == "false" then
        return false
    end

    return nil
end

local commands = {}
local order = {}

local function add(name, help, fn)
    commands[name] = {help = help, fn = fn}
    order[#order + 1] = name
end

add("help", "this list", function()
    for _, name in ipairs(order) do
        say("%-22s %s", name, commands[name].help)
    end
end)

add("god", "no damage, on or off", function(ctx, args)
    local p = ctx.world.player
    p.god = toggle(p.god, want(args, 2))
    say("god mode %s", onOff(p.god))
end)

add("invis", "the guards cannot see you", function(ctx, args)
    local p = ctx.world.player
    p.invisible = toggle(p.invisible, want(args, 2))
    say("invisibility %s", onOff(p.invisible))
end)

add("ammo", "ammunition never runs out", function(ctx, args)
    local p = ctx.world.player
    p.endlessAmmo = toggle(p.endlessAmmo, want(args, 2))
    say("endless ammunition %s", onOff(p.endlessAmmo))
end)

add("noclip", "walk through walls", function(ctx, args)
    local p = ctx.world.player
    p.noclip = toggle(p.noclip, want(args, 2))
    say("noclip %s", onOff(p.noclip))
end)

add("give", "give <weapon|ammo|keys|all>", function(ctx, args)
    local p = ctx.world.player
    local what = args[2] or "all"

    if what == "all" or what == "weapon" or what == "weapons" then
        for _, w in ipairs(weapons.list) do
            p.has[w.id] = true
        end

        p.silencer = true
    end

    if what == "all" or what == "ammo" then
        p.ammo.bullets = 150
        p.ammo.rockets = 20
        p.ammo.grenades = 9
        p.ammo.flashes = 6
        p.ammo.traps = 4
        while p:addBlade(3) do
        end
    end

    if what == "all" or what == "keys" then
        p.keys.red, p.keys.blue, p.keys.yellow = true, true, true
    end

    if what == "all" then
        p.health, p.armor = 100, p.armorMax
    end

    if weapons.byId[what] then
        p.has[what] = true
        local w = weapons.byId[what]
        if what == "knife" then
            while p:addBlade(3) do
            end
        elseif w.ammo then
            p.ammo[w.ammo] = 150
        end
    end

    say("gave %s", what)
end)

add("heal", "heal [amount], default full", function(ctx, args)
    local p = ctx.world.player
    local n = tonumber(args[2]) or 100
    p.health = math.min(100, p.health + n)
    p.alive = p.health > 0
    say("health %d", math.floor(p.health))
end)

add("armor", "armor [amount], default full", function(ctx, args)
    local p = ctx.world.player
    local n = tonumber(args[2]) or p.armorMax
    p.armor = math.min(p.armorMax, p.armor + n)
    say("vest %d%%", math.floor(p.armor))
end)

add("guard", "guard <1|2|3|4> [count] [dummy|asleep]", function(ctx, args)
    local tier = math.max(1, math.min(#Enemy.TIERS, tonumber(args[2]) or 1))
    local count = math.max(1, math.min(20, tonumber(args[3]) or 1))
    local last = args[4] or args[3]
    local dummy = last == "dummy"
    local asleep = last == "asleep"

    for i = 1, count do
        local x, y = ctx.world:openSpot(2.2 + (i - 1) * 0.5)
        local e = ctx.world:spawnGuard(tier, x, y, dummy)
        if asleep and e then
            e.asleep = true
            e.frame = "sleep"
        end
    end

    say("%d %s%s", count, Enemy.TIERS[tier].name,
        dummy and " (dummy)" or (asleep and " (asleep)" or ""))
end)

add("trap", "put [count] traps in your pocket", function(ctx, args)
    local n = math.max(1, math.min(4, tonumber(args[2]) or 4))
    local p = ctx.world.player
    for _ = 1, n do
        p:give("trap")
    end

    say("%d in the pocket", p.ammo.traps or 0)
end)

add("dog", "dog [count], the same as guard 4", function(ctx, args)
    local count = math.max(1, math.min(20, tonumber(args[2]) or 1))
    for i = 1, count do
        local x, y = ctx.world:openSpot(3 + (i - 1) * 0.6)
        ctx.world:spawnGuard(4, x, y, false)
    end

    say("%d loose", count)
end)

add("clear", "remove every guard", function(ctx)
    say("removed %d", ctx.world:clearGuards(false))
end)

add("killall", "kill every guard where he stands", function(ctx)
    say("killed %d", ctx.world:clearGuards(true))
end)

add("free", "let every prisoner on the level out of his cell", function(ctx)
    local n = 0
    for _, a in ipairs(ctx.world.allies) do
        if a.alive and not a.freed and ctx.world:freePrisoner(a) then
            n = n + 1
        end
    end

    say("%d out", n)
end)

add("mate", "put a freed prisoner in front of you", function(ctx)
    local Ally = require("src.ally")
    local x, y = ctx.world:openSpot(1.6)
    local a = Ally.new(x, y)
    table.insert(ctx.world.allies, a)
    ctx.world.totalAllies = ctx.world.totalAllies + 1
    ctx.world:freePrisoner(a)
    say("one prisoner, %d hit points", a.hp)
end)

add("distract", "every guard forgets you and goes back to his round", function(ctx)
    say("%d guards went back to the round", ctx.world:distractGuards())
end)

add("freeze", "guards stop thinking, on or off", function(ctx, args)
    ctx.world.frozen = toggle(ctx.world.frozen, want(args, 2))
    say("guards frozen %s", onOff(ctx.world.frozen))
end)

add("dmg", "print what every hit takes off", function(ctx, args)
    ctx.world.readout = toggle(ctx.world.readout, want(args, 2))
    say("damage readout %s", onOff(ctx.world.readout))
end)

add("where", "print where you are", function(ctx)
    local p = ctx.world.player
    say("x %.2f  y %.2f  tile %d,%d  facing %.0f deg", p.x, p.y,
        math.floor(p.x) + 1, math.floor(p.y) + 1, math.deg(p.angle))
end)

add("tp", "tp <x> <y>", function(ctx, args)
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not x or not y then
        say("tp needs two numbers")

        return
    end

    ctx.world.player.x, ctx.world.player.y = x, y
    say("moved to %.1f, %.1f", x, y)
end)

add("block", "block <1..3>, load a block", function(ctx, args)
    local n = tonumber(args[2])
    if not n then
        say("block needs a number")

        return
    end

    if not ctx.loadBlock(n) then
        say("no block %d", n)
    end
end)

add("range", "the shooting range", function(ctx)
    ctx.loadRange()
end)

add("restart", "start this level again", function(ctx)
    ctx.restart()
end)

function console.toggle()
    console.open = not console.open
    console.line = ""
    console.recallAt = 0

    if console.open and #console.log == 0 then
        say("developer console, type help")
    end

    return console.open
end

function console.textinput(ch)
    if ch == "`" or ch == "~" then
        return
    end

    console.line = console.line .. ch
end

function console.run(ctx)
    local line = console.line:gsub("^%s+", ""):gsub("%s+$", "")
    console.line = ""
    if line == "" then
        return
    end

    table.insert(console.recall, line)
    console.recallAt = 0
    say("> %s", line)

    local args = {}
    for word in line:gmatch("%S+") do
        args[#args + 1] = word:lower()
    end

    local cmd = commands[args[1]]
    if not cmd then
        say("no command called %s, try help", args[1])

        return
    end

    local ok, err = pcall(cmd.fn, ctx, args)
    if not ok then
        say("failed: %s", tostring(err))
    end
end

function console.keypressed(key, ctx)
    if key == "escape" then
        console.open = false
    elseif key == "return" or key == "kpenter" then
        console.run(ctx)
    elseif key == "backspace" then
        console.line = console.line:sub(1, -2)
    elseif key == "up" or key == "down" then
        local n = #console.recall
        if n > 0 then
            console.recallAt = math.max(1, math.min(n,
                console.recallAt + (key == "up" and -1 or 1)))
            if console.recallAt == 0 then
                console.recallAt = n
            end

            console.line = console.recall[console.recallAt] or ""
        end
    end
end

function console.draw(w, h, font)
    local lines = math.min(#console.log, MAX_LOG)
    local lineH = font:getHeight() + 2
    local height = (lines + 2) * lineH + 12

    love.graphics.setColor(0.03, 0.04, 0.06, 0.92)
    love.graphics.rectangle("fill", 0, 0, w, height)
    love.graphics.setColor(0.35, 0.60, 0.45, 0.8)
    love.graphics.rectangle("line", 0.5, 0.5, w - 1, height - 1)

    love.graphics.setFont(font)
    love.graphics.setColor(0.70, 0.78, 0.72)
    for i = 1, lines do
        love.graphics.print(console.log[#console.log - lines + i], 10, 8 + (i - 1) * lineH)
    end

    love.graphics.setColor(0.92, 0.90, 0.55)
    local caret = math.floor(love.timer.getTime() * 2) % 2 == 0 and "_" or ""
    love.graphics.print("> " .. console.line .. caret, 10, 8 + lines * lineH + 4)
end

return console
