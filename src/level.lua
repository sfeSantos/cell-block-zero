-- A level is a plain text file. Everything above the [map] marker is a
-- "key = value" header, everything below it is the tile grid, read exactly as
-- typed: a space and a dot are both floor, so trailing blanks matter.

local Level = {}
Level.__index = Level

-- Texture slots in the wall atlas built by src/textures.lua.
local WALLS = {
    ["#"] = 1,  -- stone block
    ["="] = 2,  -- brick
    ["%"] = 3,  -- tiled cell wall
    ["&"] = 4,  -- riveted metal
    ["~"] = 5,  -- raw rock
    ["*"] = 6,  -- wall with a poster on it
}

local DOORS = {
    ["|"] = {tex = 7},
    ["+"] = {tex = 8, barred = true},
    ["r"] = {tex = 9, lock = "red"},
    ["b"] = {tex = 10, lock = "blue"},
    ["y"] = {tex = 11, lock = "yellow"},
}

local EXIT_TEX = 12
local LOCKER_TEX = 13
local LOCKER_OPEN_TEX = 14
local PANEL_BASE = 14     -- a loose panel is its wall's texture plus this
local ALARM_TEX = 21
local ALARM_USED_TEX = 22

local FACING = {
    N = -math.pi / 2,
    S = math.pi / 2,
    W = math.pi,
    E = 0,
}

local ITEMS = {
    u = "uzi",
    l = "launcher",
    g = "grenades",
    f = "flashes",
    a = "bullets",
    U = "clips",
    A = "ammobox",
    o = "rockets",
    v = "vest",
    V = "vestheavy",
    m = "medkit",
    h = "snack",
    s = "silencer",
    T = "trap",
    K = "knife",
    R = "redkey",
    B = "bluekey",
    Y = "yellowkey",
}

-- Scenery. None of it blocks anything: it is there to say what happened in
-- this cell before you turned up.
local PROPS = {
    k = "skeleton",   -- chained to the wall and long past caring
    n = "hanged",     -- found his own way out
    d = "body",       -- a prisoner face down where he fell
    c = "remains",    -- and what the riot squad left behind
    G = "deadguard",  -- the guard who walked into your cell, and did not walk out
}

-- A guard asleep in his chair. He is an ordinary guard of that tier until
-- something wakes him.
local SLEEPERS = {z = 1, Z = 2}

Level.SLEEPERS = SLEEPERS
Level.LOCKER_TEX = LOCKER_TEX
Level.ALARM_TEX = ALARM_TEX
Level.ALARM_USED_TEX = ALARM_USED_TEX
Level.PROPS = PROPS
Level.WALLS = WALLS
Level.DOORS = DOORS
Level.ITEMS = ITEMS
Level.EXIT_TEX = EXIT_TEX

local DOOR_HALF = 0.07   -- half thickness of a door slab
local DOOR_SPEED = 1.8   -- tiles per second
local DOOR_HOLD = 4.5    -- seconds a door stays open on its own

local function colour(s, fallback)
    if not s then
        return fallback
    end

    local r, g, b = s:match("([%d%.]+)%s*, %s*([%d%.]+)%s*, %s*([%d%.]+)")
    if not r then
        return fallback
    end

    return {tonumber(r), tonumber(g), tonumber(b)}
end

local function readFile(path)
    if love and love.filesystem and love.filesystem.getInfo
            and love.filesystem.getInfo(path) then
        return love.filesystem.read(path)
    end

    local f = io.open(path, "r")
    if not f then
        return nil, "cannot open " .. path
    end

    local data = f:read("*a")
    f:close()

    return data
end

function Level.load(path)
    local data, err = readFile(path)
    if not data then
        return nil, err or ("cannot read " .. path)
    end

    local self = setmetatable({}, Level)
    self.path = path
    self.header = {}
    self.things = {}
    self.locker = {}
    self.lockers = {}
    self.secret = {}
    self.secrets = {}
    self.alarm = {}
    self.alarms = {}
    self.wall = {}
    self.door = {}
    self.exit = {}
    self.tile = {}
    self.doors = {}

    local rows = {}
    local inMap = false
    for line in (data .. "\n"):gmatch("(.-)\r?\n") do
        if inMap then
            if line:match("^%s*%[end%]") then
                break
            end

            rows[#rows + 1] = line
        elseif line:match("^%s*%[map%]") then
            inMap = true
        elseif not (line:match("^%s*;") or line:match("^%s*$")) then
            local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if k then
                self.header[k] = v
            end
        end
    end

    if #rows == 0 then
        return nil, path .. ": no [map] section"
    end

    local w = 0
    for _, row in ipairs(rows) do
        w = math.max(w, #row)
    end

    self.w, self.h = w, #rows
    self.name = self.header.name or path
    self.next = self.header.next
    if self.next == "" then
        self.next = nil
    end
    self.brief = self.header.brief or ""
    self.par = self.header.par
    self.keyPlace = {
        red = self.header.redkey,
        blue = self.header.bluekey,
        yellow = self.header.yellowkey,
    }
    self.dummies = self.header.dummies == "true"
    self.respawn = self.header.respawn == "true"
    self.readout = self.header.readout == "true"
    -- out of doors: no ceiling tiles over the yard, only the night
    self.sky = self.header.sky == "true"
    self.ceiling = colour(self.header.ceiling, {0.11, 0.12, 0.15})
    self.floor = colour(self.header.floor, {0.19, 0.17, 0.15})

    for cy = 1, self.h do
        local row = rows[cy]
        for cx = 1, w do
            local c = row:sub(cx, cx)
            if c == "" then
                c = " "
            end

            local i = (cy - 1) * w + cx
            self.tile[i] = c

            if c == "L" then
                -- a steel locker set into the wall: solid, and it opens
                self.wall[i] = LOCKER_TEX
                local box = {x = cx, y = cy, opened = false, loot = {}}
                self.locker[i] = box
                self.lockers[#self.lockers + 1] = box
            elseif c == "/" then
                -- a section of wall that slides back, drawn as the wall it
                -- sits in with the marks of having been pushed before
                self.wall[i] = PANEL_BASE + 1
                local panel = {x = cx, y = cy, opened = false}
                self.secret[i] = panel
                self.secrets[#self.secrets + 1] = panel
            elseif c == "!" then
                -- an alarm panel: solid, and a guard who reaches it puts the
                -- block into lockdown. Breaking the glass is the only use it
                -- has, so it is either untouched or finished with.
                self.wall[i] = ALARM_TEX
                local panel = {x = cx, y = cy, used = false}
                self.alarm[i] = panel
                self.alarms[#self.alarms + 1] = panel
            elseif WALLS[c] then
                self.wall[i] = WALLS[c]
            elseif c == "X" then
                self.wall[i] = EXIT_TEX
                self.exit[i] = true
            elseif DOORS[c] then
                local d = DOORS[c]
                local door = {
                    x = cx,
                    y = cy,
                    tex = d.tex,
                    lock = d.lock,
                    barred = d.barred,
                    open = 0,
                    state = "closed",
                    hold = 0,
                    axis = "x",
                }
                self.door[i] = door
                self.doors[#self.doors + 1] = door
            elseif c == "N" or c == "S" or c == "W" or c == "E" then
                self.spawn = {x = cx - 0.5, y = cy - 0.5, angle = FACING[c]}
            elseif c >= "1" and c <= "4" then
                self.things[#self.things + 1] = {
                    kind = "enemy",
                    tier = tonumber(c),
                    x = cx - 0.5,
                    y = cy - 0.5,
                }
            elseif SLEEPERS[c] then
                self.things[#self.things + 1] = {
                    kind = "enemy",
                    tier = SLEEPERS[c],
                    asleep = true,
                    x = cx - 0.5,
                    y = cy - 0.5,
                }
            elseif ITEMS[c] then
                self.things[#self.things + 1] = {
                    kind = "item",
                    item = ITEMS[c],
                    x = cx - 0.5,
                    y = cy - 0.5,
                }
            elseif PROPS[c] then
                self.things[#self.things + 1] = {
                    kind = "prop",
                    prop = PROPS[c],
                    x = cx - 0.5,
                    y = cy - 0.5,
                }
            elseif c == "p" then
                self.things[#self.things + 1] = {
                    kind = "prisoner",
                    x = cx - 0.5,
                    y = cy - 0.5,
                }
            end
        end
    end

    -- a panel wears the same wall as its neighbours, with the hairline and
    -- the scuff marks of something that has been pushed before
    for _, panel in ipairs(self.secrets) do
        for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            local j = self:index(panel.x + d[1], panel.y + d[2])
            local tex = j and self.wall[j]
            if tex and tex >= 1 and tex <= 6 then
                self.wall[self:index(panel.x, panel.y)] = PANEL_BASE + tex
                panel.tex = PANEL_BASE + tex

                break
            end
        end
    end

    -- A door slides into the wall it is flush with, so its axis follows the
    -- side the solid neighbours are on.
    for _, door in ipairs(self.doors) do
        local sideways = self:isWall(door.x - 1, door.y) and self:isWall(door.x + 1, door.y)
        door.axis = sideways and "x" or "y"
    end

    self.spawn = self.spawn or {x = 1.5, y = 1.5, angle = 0}
    self:buildAreas()

    return self
end

-- The block, cut into areas. A door is a boundary, so an area is a room or a
-- stretch of corridor between doors. Gunfire is heard inside one area and no
-- further; a guard belongs to the area he starts in and does not abandon it.
function Level:buildAreas()
    self.area = {}
    self.areaSize = {}
    self.areaTiles = {}

    local n = 0
    local queue = {}

    for cy = 1, self.h do
        for cx = 1, self.w do
            local i = self:index(cx, cy)
            if not self.area[i] and not self.wall[i] and not self.door[i] then
                n = n + 1
                local size = 0
                local head = 1
                queue[1] = {cx, cy}
                self.area[i] = n
                self.areaTiles[n] = {}

                while head <= #queue do
                    local t = queue[head]
                    head = head + 1
                    size = size + 1
                    self.areaTiles[n][size] = {x = t[1], y = t[2]}

                    for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
                        local nx, ny = t[1] + d[1], t[2] + d[2]
                        local j = self:index(nx, ny)
                        if j and not self.area[j] and not self.wall[j]
                                and not self.door[j] then
                            self.area[j] = n
                            queue[#queue + 1] = {nx, ny}
                        end
                    end
                end

                self.areaSize[n] = size
                for k = #queue, 1, -1 do
                    queue[k] = nil
                end
            end
        end
    end

    -- a door belongs to the area on either side of it, whichever is first:
    -- standing in a doorway you are in both rooms as far as hearing goes
    for _, door in ipairs(self.doors) do
        local i = self:index(door.x, door.y)
        for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            local j = self:index(door.x + d[1], door.y + d[2])
            if j and self.area[j] then
                self.area[i] = self.area[j]
                door.area = self.area[j]
                break
            end
        end
    end

    self.areas = n

    return n
end

function Level:lockerAt(cx, cy)
    local i = self:index(cx, cy)

    return i and self.locker[i] or nil
end

function Level:secretAt(cx, cy)
    local i = self:index(cx, cy)

    return i and self.secret[i] or nil
end

function Level:alarmAt(cx, cy)
    local i = self:index(cx, cy)

    return i and self.alarm[i] or nil
end

function Level:openLocker(box)
    if box.opened then
        return false
    end

    box.opened = true
    self.wall[self:index(box.x, box.y)] = LOCKER_OPEN_TEX

    return true
end

-- The glass goes and the handle comes down. The tile stays solid either way:
-- what changes is that from across the room you can see this one has been
-- pulled already.
function Level:useAlarm(panel)
    if panel.used then
        return false
    end

    panel.used = true
    self.wall[self:index(panel.x, panel.y)] = ALARM_USED_TEX

    return true
end

-- The panel slides back and what was behind it becomes part of the room you
-- are standing in, areas included, so the guards treat it as one place.
function Level:revealSecret(panel)
    if panel.opened then
        return false
    end

    panel.opened = true
    local i = self:index(panel.x, panel.y)
    self.wall[i] = nil

    local mine, theirs
    for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
        local a = self:areaAt(panel.x + d[1], panel.y + d[2])
        if a then
            if not mine then
                mine = a
            elseif a ~= mine then
                theirs = a
            end
        end
    end

    self.area[i] = mine

    if theirs and self.areaTiles[theirs] then
        for _, tile in ipairs(self.areaTiles[theirs]) do
            self.area[self:index(tile.x, tile.y)] = mine
        end

        for _, tile in ipairs(self.areaTiles[theirs]) do
            self.areaTiles[mine][#self.areaTiles[mine] + 1] = tile
        end

        self.areaSize[mine] = (self.areaSize[mine] or 0) + (self.areaSize[theirs] or 0)
        self.areaTiles[theirs] = {}
        self.areaSize[theirs] = 0
    end

    return true, mine, theirs
end

function Level:areaAt(cx, cy)
    local i = self:index(cx, cy)

    return i and self.area and self.area[i] or nil
end

function Level:areaOf(x, y)
    return self:areaAt(math.floor(x) + 1, math.floor(y) + 1)
end

function Level:index(cx, cy)
    if cx < 1 or cy < 1 or cx > self.w or cy > self.h then
        return nil
    end

    return (cy - 1) * self.w + cx
end

function Level:isWall(cx, cy)
    local i = self:index(cx, cy)
    if not i then
        return true
    end

    return self.wall[i] ~= nil
end

function Level:isExit(cx, cy)
    local i = self:index(cx, cy)

    return i ~= nil and self.exit[i] == true
end

function Level:doorAt(cx, cy)
    local i = self:index(cx, cy)

    return i and self.door[i] or nil
end

function Level:tileAt(cx, cy)
    local i = self:index(cx, cy)

    return i and self.tile[i] or "#"
end

-- Blocks sight and bullets: a wall, or a door that has not slid far enough.
function Level:blocksSight(cx, cy)
    local i = self:index(cx, cy)
    if not i then
        return true
    end

    if self.wall[i] then
        return true
    end

    local d = self.door[i]

    return d ~= nil and d.open < 0.75
end

-- Walkable for the navigation field. Doors count as open because everyone in
-- here knows how to work a door handle.
function Level:navOpen(cx, cy)
    local i = self:index(cx, cy)
    if not i then
        return false
    end

    return self.wall[i] == nil
end

-- Walkable by the player carrying the keys in `keys`. A locked door he has no
-- key for is a wall; a panel in a wall is not, because he can push it from
-- either side. Lockers and the exit switch are solid: you stand in front of
-- them, you do not walk through them.
function Level:walkable(cx, cy, keys)
    local i = self:index(cx, cy)
    if not i or self.exit[i] then
        return false
    end

    if self.secret[i] then
        return true
    end

    if self.wall[i] then
        return false
    end

    local d = self.door[i]
    if d and d.lock then
        return keys ~= nil and keys[d.lock] == true
    end

    return true
end

-- Every tile reachable on foot from a spot with a given bunch of keys, as a
-- set of tile indices. The key placing uses it so a key is never put behind
-- the door it opens, and tools/levelcheck.lua uses it to say whether a locked
-- door is a gate or scenery.
function Level:reachable(x, y, keys)
    local seen = {}
    local cx, cy = math.floor(x) + 1, math.floor(y) + 1
    if not self:walkable(cx, cy, keys) then
        return seen
    end

    local queue = {{cx, cy}}
    seen[self:index(cx, cy)] = true

    local head = 1
    while head <= #queue do
        local t = queue[head]
        head = head + 1

        for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            local nx, ny = t[1] + d[1], t[2] + d[2]
            local j = self:index(nx, ny)
            if j and not seen[j] and self:walkable(nx, ny, keys) then
                seen[j] = true
                queue[#queue + 1] = {nx, ny}
            end
        end
    end

    return seen
end

-- Walkable while walking a round. A guard with nothing to worry about does not
-- unlock cells or go through barred doors, he stays in the corridors.
function Level:patrolOpen(cx, cy)
    local i = self:index(cx, cy)
    if not i or self.wall[i] then
        return false
    end

    local d = self.door[i]

    return d == nil or not (d.barred or d.lock)
end

local function circleHitsRect(px, py, r, x0, y0, x1, y1)
    local cx = px < x0 and x0 or (px > x1 and x1 or px)
    local cy = py < y0 and y0 or (py > y1 and y1 or py)
    local dx, dy = px - cx, py - cy

    return dx * dx + dy * dy < r * r
end

-- The slab's rectangle. `open` says how far it has slid, 0 shut and 1 away,
-- and defaults to where the slab actually is; pass it to ask for the rect the
-- slab would have at some other position.
function Level:doorRect(door, open)
    open = open or door.open

    local x0, y0 = door.x - 1, door.y - 1
    if door.axis == "x" then
        return x0 + open, y0 + 0.5 - DOOR_HALF, x0 + 1, y0 + 0.5 + DOOR_HALF
    end

    return x0 + 0.5 - DOOR_HALF, y0 + open, x0 + 0.5 + DOOR_HALF, y0 + 1
end

-- True when a disc of radius r centred on (x, y) overlaps anything solid.
-- `keys` is optional and says who is moving. Pass it and a locked door the
-- mover has no key for stays solid however far its slab has slid, so a guard
-- holding the red door open is not a way through it. Leave it out and only
-- the slab counts, which is what the guards, the allies and the bullets want.
function Level:blocked(x, y, r, keys)
    local cx0 = math.floor(x - r) + 1
    local cx1 = math.floor(x + r) + 1
    local cy0 = math.floor(y - r) + 1
    local cy1 = math.floor(y + r) + 1

    for cy = cy0, cy1 do
        for cx = cx0, cx1 do
            local i = self:index(cx, cy)
            if not i then
                if circleHitsRect(x, y, r, cx - 1, cy - 1, cx, cy) then
                    return true
                end
            elseif self.wall[i] then
                if circleHitsRect(x, y, r, cx - 1, cy - 1, cx, cy) then
                    return true
                end
            else
                local d = self.door[i]
                if d and d.lock and keys and keys[d.lock] ~= true then
                    -- the slab as it is when shut, not the whole tile, so he
                    -- can still walk up and stand against it from either side
                    local x0, y0, x1, y1 = self:doorRect(d, 0)
                    if circleHitsRect(x, y, r, x0, y0, x1, y1) then
                        return true
                    end
                elseif d and d.open < 0.98 then
                    local x0, y0, x1, y1 = self:doorRect(d)
                    if circleHitsRect(x, y, r, x0, y0, x1, y1) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

-- Walks the grid from a to b and reports whether nothing solid is in between.
function Level:lineOfSight(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1e-6 then
        return true
    end

    dx, dy = dx / dist, dy / dist

    local cx, cy = math.floor(ax) + 1, math.floor(ay) + 1
    local tx, ty = math.floor(bx) + 1, math.floor(by) + 1

    local here = self:index(cx, cy)
    local inside = here and self.door[here]
    if inside then
        local t = self:doorHit(inside, ax, ay, dx, dy)
        if t and t <= dist then
            return false
        end
    end
    local stepX = dx > 0 and 1 or -1
    local stepY = dy > 0 and 1 or -1
    local invX = dx ~= 0 and math.abs(1 / dx) or math.huge
    local invY = dy ~= 0 and math.abs(1 / dy) or math.huge
    local nextX = dx > 0 and (cx - ax) or (ax - cx + 1)
    local nextY = dy > 0 and (cy - ay) or (ay - cy + 1)
    local sideX = dx ~= 0 and nextX * invX or math.huge
    local sideY = dy ~= 0 and nextY * invY or math.huge

    for _ = 1, 512 do
        if cx == tx and cy == ty then
            return true
        end

        if sideX < sideY then
            if sideX > dist then
                return true
            end

            cx = cx + stepX
            sideX = sideX + invX
        else
            if sideY > dist then
                return true
            end

            cy = cy + stepY
            sideY = sideY + invY
        end

        if self:blocksSight(cx, cy) then
            return false
        end
    end

    return false
end

-- Where a ray crosses the slab of a door, as a ray parameter, plus the spot on
-- the door texture. Returns nothing when the ray misses the slab, which is
-- what happens once the door has slid far enough open.
function Level:doorHit(door, px, py, rdx, rdy)
    local t, u

    if door.axis == "x" then
        if rdy == 0 then
            return nil
        end

        t = ((door.y - 0.5) - py) / rdy
        if t < 0 then
            return nil
        end

        u = px + rdx * t - (door.x - 1)
    else
        if rdx == 0 then
            return nil
        end

        t = ((door.x - 0.5) - px) / rdx
        if t < 0 then
            return nil
        end

        u = py + rdy * t - (door.y - 1)
    end

    if u < door.open or u > 1 then
        return nil
    end

    return t, u - door.open
end

-- Casts one ray and reports what it hits: distance, texture slot, the
-- horizontal spot on that texture, and which face was struck. Doors are thin
-- slabs in the middle of their tile, so a half open door really does let the
-- view, and the bullets, through the gap.
function Level:cast(px, py, rdx, rdy, maxDist)
    maxDist = maxDist or 128

    local cx, cy = math.floor(px) + 1, math.floor(py) + 1
    local stepX = rdx >= 0 and 1 or -1
    local stepY = rdy >= 0 and 1 or -1
    local dX = rdx == 0 and math.huge or math.abs(1 / rdx)
    local dY = rdy == 0 and math.huge or math.abs(1 / rdy)
    local sideX = rdx >= 0 and (cx - px) * dX or (px - cx + 1) * dX
    local sideY = rdy >= 0 and (cy - py) * dY or (py - cy + 1) * dY
    local dist, side = 0, 0

    -- the door of the tile the ray starts in: standing against a closed door
    -- used to let the view, and the bullets, straight through it
    local here = self:index(cx, cy)
    local inside = here and self.door[here]
    if inside then
        local t, u = self:doorHit(inside, px, py, rdx, rdy)
        if t and t <= maxDist then
            return t, inside.tex, u, inside.axis == "x" and 1 or 0, cx, cy
        end
    end

    for _ = 1, 512 do
        if sideX < sideY then
            dist = sideX
            cx = cx + stepX
            sideX = sideX + dX
            side = 0
        else
            dist = sideY
            cy = cy + stepY
            sideY = sideY + dY
            side = 1
        end

        if dist > maxDist then
            return maxDist, nil, 0, side, cx, cy
        end

        local i = self:index(cx, cy)
        if not i then
            return dist, 1, 0, side, cx, cy
        end

        local tex = self.wall[i]
        if tex then
            local u
            if side == 0 then
                u = py + rdy * dist - (cy - 1)
                if rdx > 0 then
                    u = 1 - u
                end
            else
                u = px + rdx * dist - (cx - 1)
                if rdy < 0 then
                    u = 1 - u
                end
            end

            return dist, tex, u, side, cx, cy
        end

        local door = self.door[i]
        if door then
            local t, u = self:doorHit(door, px, py, rdx, rdy)
            if t then
                return t, door.tex, u, door.axis == "x" and 1 or 0, cx, cy
            end
        end
    end

    return maxDist, nil, 0, side, cx, cy
end

function Level:openDoor(door)
    if door.state ~= "open" then
        door.state = "opening"
    end

    door.hold = DOOR_HOLD
end

function Level:updateDoors(dt, occupied)
    for _, door in ipairs(self.doors) do
        if door.state == "opening" then
            door.open = math.min(1, door.open + dt * DOOR_SPEED)
            if door.open >= 1 then
                door.state = "open"
            end
        elseif door.state == "open" then
            door.hold = door.hold - dt
            if door.hold <= 0 and not occupied(door.x, door.y) then
                door.state = "closing"
            end
        elseif door.state == "closing" then
            if occupied(door.x, door.y) then
                door.state = "opening"
            else
                door.open = math.max(0, door.open - dt * DOOR_SPEED * 0.7)
                if door.open <= 0 then
                    door.state = "closed"
                end
            end
        end
    end
end

return Level
