-- Reads the level files the way the game reads them and says whether they
-- hold together: a locked door that can be walked round is scenery, a key
-- behind the door it opens is a dead end, a pocket of floor nobody can reach
-- is wasted work. Run it from the root of the repository:
--
--     lua tools/levelcheck.lua levels/0*.txt
--
-- It prints a line per block and the counts that make up the difficulty
-- ramp, and leaves with 1 if anything is wrong.

package.path = "./?.lua;" .. package.path

local Level = require("src.level")

local COLOURS = {"red", "blue", "yellow"}
local DOOR_CHAR = {red = "r", blue = "b", yellow = "y"}

local problems = 0
local blocks = {}

local function fail(level, fmt, ...)
    problems = problems + 1
    print(string.format("  FAIL  " .. fmt, ...))
end

local function note(fmt, ...)
    print(string.format("        " .. fmt, ...))
end

local function keySet(...)
    local keys = {}
    for _, c in ipairs({...}) do
        keys[c] = true
    end

    return keys
end

local function allKeys()
    return keySet("red", "blue", "yellow")
end

local function without(colour)
    local keys = allKeys()
    keys[colour] = nil

    return keys
end

-- the tiles either side of a door, along the axis it is passable on
local function doorSides(level, door)
    local out = {}
    for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
        local cx, cy = door.x + d[1], door.y + d[2]
        local i = level:index(cx, cy)
        if i and not level.wall[i] and not level.exit[i] then
            out[#out + 1] = {x = cx, y = cy, i = i}
        end
    end

    return out
end

local function exitReached(level, reach)
    for i in pairs(level.exit) do
        local x = ((i - 1) % level.w) + 1
        local y = math.floor((i - 1) / level.w) + 1
        for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            local j = level:index(x + d[1], y + d[2])
            if j and reach[j] then
                return true
            end
        end
    end

    return false
end

local function faceable(level, cx, cy, reach)
    for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
        local j = level:index(cx + d[1], cy + d[2])
        if j and reach[j] then
            return true
        end
    end

    return false
end

-- the same rounds the game plays in World:placeKeys, without the world
local function placeable(level)
    local sx, sy = level.spawn.x, level.spawn.y
    local held, todo = {}, {}
    local order = {}

    for _, colour in ipairs(COLOURS) do
        if level.keyPlace[colour] then
            todo[#todo + 1] = colour
        end
    end

    while #todo > 0 do
        local reach = level:reachable(sx, sy, held)
        local done

        for n, colour in ipairs(todo) do
            local where = level.keyPlace[colour]
            local ok = false

            if where == "guard" then
                for _, thing in ipairs(level.things) do
                    local i = level:index(math.floor(thing.x) + 1, math.floor(thing.y) + 1)
                    if thing.kind == "enemy" and thing.tier ~= 4 and i and reach[i] then
                        ok = true
                    end
                end
            elseif where == "locker" then
                for _, box in ipairs(level.lockers) do
                    if faceable(level, box.x, box.y, reach) then
                        ok = true
                    end
                end
            elseif where == "secret" then
                for _, panel in ipairs(level.secrets) do
                    if faceable(level, panel.x, panel.y, reach) then
                        ok = true
                    end
                end
            end

            if ok then
                held[colour] = true
                order[#order + 1] = colour
                done = n

                break
            end
        end

        if not done then
            return nil, todo, order
        end

        table.remove(todo, done)
    end

    return true, {}, order
end

local function counts(level)
    local c = {t1 = 0, t2 = 0, t3 = 0, dogs = 0, asleep = 0, prisoners = 0,
        ammo = 0, armour = 0, medical = 0, items = 0}

    for _, thing in ipairs(level.things) do
        if thing.kind == "enemy" then
            if thing.tier == 4 then
                c.dogs = c.dogs + 1
            else
                c["t" .. thing.tier] = c["t" .. thing.tier] + 1
            end

            if thing.asleep then
                c.asleep = c.asleep + 1
            end
        elseif thing.kind == "prisoner" then
            c.prisoners = c.prisoners + 1
        elseif thing.kind == "item" then
            c.items = c.items + 1
            local it = thing.item
            if it == "bullets" or it == "clips" or it == "ammobox" or it == "rockets" then
                c.ammo = c.ammo + 1
            elseif it == "vest" or it == "vestheavy" then
                c.armour = c.armour + 1
            elseif it == "medkit" or it == "snack" then
                c.medical = c.medical + 1
            end
        end
    end

    return c
end

local function check(path)
    local level, err = Level.load(path)
    print("")
    print(path)

    if not level then
        problems = problems + 1
        print("  FAIL  " .. tostring(err))

        return
    end

    local sx, sy = level.spawn.x, level.spawn.y
    print(string.format("  %s, %d by %d, %d doors, %d lockers, %d panels",
        level.name, level.w, level.h, #level.doors, #level.lockers, #level.secrets))

    -- a spawn and a way out
    if not level.header.name then
        fail(level, "no name in the header")
    end

    local exits = 0
    for _ in pairs(level.exit) do
        exits = exits + 1
    end

    if exits == 0 then
        fail(level, "no exit switch")
    end

    -- sealed all the way round
    for cx = 1, level.w do
        if level:walkable(cx, 1, allKeys()) or level:walkable(cx, level.h, allKeys()) then
            fail(level, "the block leaks at column %d, top or bottom", cx)
            break
        end
    end

    for cy = 1, level.h do
        if level:walkable(1, cy, allKeys()) or level:walkable(level.w, cy, allKeys()) then
            fail(level, "the block leaks at row %d, left or right", cy)
            break
        end
    end

    -- the keys the block says it uses, against the doors it has
    local doorsBy = {}
    for _, door in ipairs(level.doors) do
        if door.lock then
            doorsBy[door.lock] = (doorsBy[door.lock] or 0) + 1
        end
    end

    for _, colour in ipairs(COLOURS) do
        local where = level.keyPlace[colour]
        if where and not doorsBy[colour] then
            fail(level, "a %s key is placed and there is no %s door (%s) to open",
                colour, colour, DOOR_CHAR[colour])
        elseif doorsBy[colour] and not where then
            fail(level, "a %s door and no %skey line in the header", colour, colour)
        elseif where and where ~= "guard" and where ~= "locker" and where ~= "secret" then
            fail(level, "%skey = %s, which is not guard, locker or secret", colour, where)
        end
    end

    -- every locked door a real gate: with every other key in hand, the two
    -- sides still have to be apart
    for _, door in ipairs(level.doors) do
        if door.lock then
            local reach = level:reachable(sx, sy, without(door.lock))
            local sides = doorSides(level, door)
            local open = 0
            for _, s in ipairs(sides) do
                if reach[s.i] then
                    open = open + 1
                end
            end

            if open == #sides and #sides > 1 then
                fail(level, "the %s door at %d,%d is scenery: both sides can be walked to without the key",
                    door.lock, door.x, door.y)
            elseif open == 0 then
                fail(level, "the %s door at %d,%d cannot be walked up to at all",
                    door.lock, door.x, door.y)
            end
        end
    end

    -- the way out has to cost something, and has to be there at the end
    local bare = level:reachable(sx, sy, {})
    local full = level:reachable(sx, sy, allKeys())

    if exits > 0 then
        if exitReached(level, bare) then
            fail(level, "the exit can be reached with no key at all")
        elseif not exitReached(level, full) then
            fail(level, "the exit cannot be reached even with every key")
        end

        local needed = {}
        for _, colour in ipairs(COLOURS) do
            if level.keyPlace[colour] then
                if not exitReached(level, level:reachable(sx, sy, without(colour))) then
                    needed[#needed + 1] = colour
                end
            end
        end

        if #needed == 0 then
            fail(level, "no key is on the way out")
        else
            note("the way out wants: %s", table.concat(needed, ", "))
        end
    end

    -- a key is never behind the door it opens
    local ok, stuck, order = placeable(level)
    if not ok then
        fail(level, "nowhere to put the %s key that is not behind its own door",
            table.concat(stuck, " or the "))
    elseif #order > 0 then
        note("keys fall in this order: %s", table.concat(order, ", "))
    end

    -- nothing walled off from the rest
    local orphans = 0
    for cy = 1, level.h do
        for cx = 1, level.w do
            local i = level:index(cx, cy)
            if level:walkable(cx, cy, allKeys()) and not full[i] then
                orphans = orphans + 1
            end
        end
    end

    if orphans > 0 then
        fail(level, "%d tiles of floor nobody can walk to", orphans)
    end

    -- and nothing standing in a wall
    for _, thing in ipairs(level.things) do
        local i = level:index(math.floor(thing.x) + 1, math.floor(thing.y) + 1)
        if i and not full[i] then
            fail(level, "a %s at %.1f,%.1f is somewhere nobody can reach",
                thing.kind, thing.x, thing.y)
        end
    end

    local c = counts(level)
    -- the total first and then the headings it breaks into, which do not
    -- cover everything: a weapon or a key is a pickup under none of them
    note("guards %d, %d, %d  dogs %d  asleep %d  prisoners %d  pickups %d  ammunition %d  armour %d  food and kit %d",
        c.t1, c.t2, c.t3, c.dogs, c.asleep, c.prisoners, c.items, c.ammo,
        c.armour, c.medical)

    -- the ! tile, so whoever edits a level next finds out it exists
    if #level.alarms > 0 then
        note("alarm panels %d, a guard who reaches one shuts the block down",
            #level.alarms)
    else
        note("no alarm panels: nobody here can do worse than shout")
    end

    blocks[#blocks + 1] = {path = path, level = level, counts = c}
end

local files = {...}
if #files == 0 then
    print("lua tools/levelcheck.lua levels/0*.txt")
    os.exit(2)
end

for _, path in ipairs(files) do
    check(path)
end

-- the chain: one block with no next, and every other one pointing at a file
-- that exists, with nothing left out of the run
if #blocks > 1 then
    print("")
    print("the chain")

    local byFile, ends = {}, 0
    for _, b in ipairs(blocks) do
        byFile[b.path:match("([^/]+)$")] = b
    end

    for _, b in ipairs(blocks) do
        local nxt = b.level.next
        if not nxt then
            ends = ends + 1
            print(string.format("  %s ends the game", b.path))
        else
            local name = nxt:match("([^/]+)$")
            if not byFile[name] then
                problems = problems + 1
                print(string.format("  FAIL  %s points at %s, which is not here", b.path, nxt))
            else
                print(string.format("  %s -> %s", b.path, name))
            end
        end
    end

    if ends ~= 1 then
        problems = problems + 1
        print(string.format("  FAIL  %d blocks with no next, there has to be exactly one", ends))
    end
end

print("")
if problems > 0 then
    print(string.format("%d problem%s", problems, problems == 1 and "" or "s"))
    os.exit(1)
end

print("all good")
