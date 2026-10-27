-- One saved game. A picture of the block exactly as it stands: where
-- everybody is and what state they are in, what is still on the floor, which
-- doors are open, which lockers have been turned out and what you are
-- carrying. It goes into the save directory as a Lua table and comes back
-- through loadstring, with a version on it so a file from an older build is
-- refused rather than half applied.

local World = require("src.world")
local Enemy = require("src.enemy")
local Ally = require("src.ally")
local nav = require("src.nav")

local save = {}

save.FILE = "save.lua"
save.VERSION = 2

local function encode(v)
    local t = type(v)

    if t == "number" then
        return string.format("%.14g", v)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t ~= "table" then
        return "nil"
    end

    local parts = {}
    local n = #v

    for i = 1, n do
        parts[#parts + 1] = encode(v[i])
    end

    for k, val in pairs(v) do
        local array = type(k) == "number" and k >= 1 and k <= n and math.floor(k) == k
        if not array then
            parts[#parts + 1] = string.format("[%s]=%s", encode(k), encode(val))
        end
    end

    return "{" .. table.concat(parts, ",") .. "}"
end

local function copy(from, keys)
    local out = {}
    for _, k in ipairs(keys) do
        out[k] = from[k]
    end

    return out
end

local PLAYER_KEYS = {"x", "y", "angle", "pitch", "health", "armor", "weapon",
    "silencer", "silenced", "kills", "takedowns", "god", "invisible",
    "endlessAmmo"}

local ENEMY_KEYS = {"x", "y", "angle", "hp", "alive", "state", "frame",
    "asleep", "awake", "carries", "keyName", "patrol", "dummy"}

local ALLY_KEYS = {"x", "y", "angle", "hp", "alive", "freed", "state",
    "frame", "kills"}

local COUNTERS = {"time", "killed", "total", "taken", "totalItems", "freed",
    "totalAllies", "alarms", "alarmT"}

-- Everything worth writing down about the block as it is this second.
function save.snapshot(world, path, difficulty, elapsed)
    local level = world.level
    local p = world.player

    local data = {
        version = save.VERSION,
        level = path,
        difficulty = difficulty,
        elapsed = elapsed or 0,
        name = level.name,
        counters = copy(world, COUNTERS),
        census = world.census,
        tally = world.tally,
        player = copy(p, PLAYER_KEYS),
        enemies = {},
        allies = {},
        items = {},
        props = {},
        traps = {},
        doors = {},
        lockers = {},
        secrets = {},
    }

    data.player.ammo = copy(p.ammo, {"bullets", "clips", "rockets", "grenades",
        "flashes", "knives", "traps"})
    data.player.mag = {}
    for k, v in pairs(p.mag) do
        data.player.mag[k] = v
    end
    data.player.has = {}
    for k, v in pairs(p.has) do
        data.player.has[k] = v
    end

    data.player.keys = {}
    for k, v in pairs(p.keys) do
        data.player.keys[k] = v
    end

    data.player.blades = {}
    for i, uses in ipairs(p.blades) do
        data.player.blades[i] = uses
    end

    for _, e in ipairs(world.enemies) do
        local row = copy(e, ENEMY_KEYS)
        row.tier = e.tier
        if e.home then
            row.home = {x = e.home.x, y = e.home.y}
        end

        data.enemies[#data.enemies + 1] = row
    end

    for _, a in ipairs(world.allies) do
        data.allies[#data.allies + 1] = copy(a, ALLY_KEYS)
    end

    for _, it in ipairs(world.items) do
        data.items[#data.items + 1] = copy(it, {"item", "x", "y", "uses",
            "dropped"})
    end

    for _, prop in ipairs(world.props) do
        data.props[#data.props + 1] = copy(prop, {"prop", "x", "y", "size"})
    end

    for _, trap in ipairs(world.traps) do
        data.traps[#data.traps + 1] = copy(trap, {"x", "y", "armed"})
    end

    for i, door in ipairs(level.doors) do
        data.doors[i] = copy(door, {"state", "open", "hold"})
    end

    for i, box in ipairs(level.lockers) do
        local loot = {}
        for j, item in ipairs(box.loot) do
            loot[j] = item
        end

        data.lockers[i] = {opened = box.opened, stocked = box.stocked,
            loot = loot}
    end

    for i, panel in ipairs(level.secrets) do
        data.secrets[i] = panel.opened and true or false
    end

    return data
end

function save.write(world, path, difficulty, elapsed)
    local data = save.snapshot(world, path, difficulty, elapsed)
    local ok, err = love.filesystem.write(save.FILE,
        "return " .. encode(data) .. "\n")

    if not ok then
        print("save: " .. tostring(err))
    end

    return ok
end

function save.exists()
    return love.filesystem.getInfo ~= nil
        and love.filesystem.getInfo(save.FILE) ~= nil
end

function save.remove()
    if save.exists() then
        love.filesystem.remove(save.FILE)
    end
end

-- The file on its own, without building anything from it, so the menu can
-- say which block is waiting in there.
function save.read()
    if not save.exists() then
        return nil
    end

    local text = love.filesystem.read(save.FILE)
    if not text then
        return nil
    end

    local chunk = (loadstring or load)(text, "save")
    if not chunk then
        return nil
    end

    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" or data.version ~= save.VERSION then
        return nil
    end

    return data
end

-- Build the block again and put everything back where the file says it was.
function save.restore(data, audio)
    local world, err = World.load(data.level, data.difficulty, nil, audio)
    if not world then
        return nil, err
    end

    local level = world.level
    local p = world.player

    for _, k in ipairs(PLAYER_KEYS) do
        if data.player[k] ~= nil then
            p[k] = data.player[k]
        end
    end

    for k, v in pairs(data.player.ammo or {}) do
        p.ammo[k] = v
    end

    p.mag = {}
    for k, v in pairs(data.player.mag or {}) do
        p.mag[k] = v
    end
    p.reloadT = 0

    p.has = {}
    for k, v in pairs(data.player.has or {}) do
        p.has[k] = v
    end

    p.keys = {}
    for k, v in pairs(data.player.keys or {}) do
        p.keys[k] = v
    end

    p.blades = {}
    for i, uses in ipairs(data.player.blades or {}) do
        p.blades[i] = uses
    end
    p:syncBlades()

    world.enemies = {}
    for _, row in ipairs(data.enemies or {}) do
        local e = Enemy.new(row.tier, row.x, row.y, world.scale)
        e.dummy = row.dummy
        if not e.dummy then
            e:setPatrol(level)
        end

        for _, k in ipairs(ENEMY_KEYS) do
            if row[k] ~= nil then
                e[k] = row[k]
            end
        end

        if row.home then
            e.home = {x = row.home.x, y = row.home.y}
        end

        if not e.alive then
            e.frame = row.frame or "dead"
            e.anim = 1
        end

        world.enemies[#world.enemies + 1] = e
    end

    world.allies = {}
    for _, row in ipairs(data.allies or {}) do
        local a = Ally.new(row.x, row.y)
        for _, k in ipairs(ALLY_KEYS) do
            if row[k] ~= nil then
                a[k] = row[k]
            end
        end

        world.allies[#world.allies + 1] = a
    end

    world.items = {}
    for _, row in ipairs(data.items or {}) do
        world.items[#world.items + 1] = {item = row.item, x = row.x, y = row.y,
            uses = row.uses, dropped = row.dropped}
    end

    world.props = {}
    for _, row in ipairs(data.props or {}) do
        world.props[#world.props + 1] = {prop = row.prop, x = row.x,
            y = row.y, size = row.size}
    end

    world.traps = {}
    for _, row in ipairs(data.traps or {}) do
        world.traps[#world.traps + 1] = {x = row.x, y = row.y,
            armed = row.armed, seen = {}}
    end

    for i, door in ipairs(level.doors) do
        local row = data.doors and data.doors[i]
        if row then
            door.state = row.state or door.state
            door.open = row.open or 0
            door.hold = row.hold or 0
        end
    end

    for i, box in ipairs(level.lockers) do
        local row = data.lockers and data.lockers[i]
        if row then
            box.loot = {}
            for j, item in ipairs(row.loot or {}) do
                box.loot[j] = item
            end

            box.stocked = row.stocked
            if row.opened and not box.opened then
                level:openLocker(box)
            end
        end
    end

    for i, panel in ipairs(level.secrets) do
        if data.secrets and data.secrets[i] and not panel.opened then
            level:revealSecret(panel)
        end
    end

    for _, k in ipairs(COUNTERS) do
        if data.counters[k] ~= nil then
            world[k] = data.counters[k]
        end
    end

    world.census = data.census or world.census
    world.tally = data.tally or world.tally

    nav.build(world.field, level, math.floor(p.x) + 1, math.floor(p.y) + 1)
    world:message("Carrying on from the save")

    return world
end

return save
