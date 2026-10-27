-- One level being played: the map, the convict, the guards, what they drop and
-- what they throw at each other. Bodies are never removed, so a corridor you
-- fought through stays the way you left it until the level restarts.

local Level = require("src.level")
local Player = require("src.player")
local Ally = require("src.ally")
local Enemy = require("src.enemy")
local Projectile = require("src.projectile")
local Fx = require("src.fx")
local nav = require("src.nav")
local weapons = require("src.weapons")

local World = {}
World.__index = World

World.DIFFICULTY = {
    {name = "Easy time", damage = 0.65, accuracy = 0.78, react = 1.5, speed = 0.9,
        respond = 2},
    {name = "Hard time", damage = 1.00, accuracy = 1.00, react = 1.0, speed = 1.0,
        respond = 3},
    {name = "Death row", damage = 1.40, accuracy = 1.22, react = 0.65, speed = 1.12,
        respond = 4},
}

local FIELD_RATE = 0.2
local RADIO = 5.5    -- how far a guard's shout carries to the others

local function wrap(a)
    return math.atan2(math.sin(a), math.cos(a))
end

-- What turns up in a locker. Each line is rolled on its own, so a locker can
-- hold three things or nothing at all.
World.LOOT = {
    {"bullets", 0.50},
    {"clips", 0.26},
    {"snack", 0.30},
    {"medkit", 0.24},
    {"ammobox", 0.20},
    {"vest", 0.20},
    {"trap", 0.18},
    {"knife", 0.16},
    {"grenades", 0.16},
    {"flashes", 0.12},
    {"rockets", 0.10},
    {"uzi", 0.07},
    {"vestheavy", 0.05},
    {"silencer", 0.05},
}

local LOOT_MAX = 3
local LOOT_EMPTY = 0.22     -- how often a locker has been cleared out already

function World.load(path, difficulty, carry, audio)
    local level, err = Level.load(path)
    if not level then
        return nil, err
    end

    local self = setmetatable({}, World)
    self.level = level
    self.audio = audio
    self.difficulty = difficulty or 2
    self.scale = World.DIFFICULTY[self.difficulty]
    self.player = Player.carryOver(carry, level.spawn)
    self.enemies = {}
    self.allies = {}
    self.traps = {}
    self.props = {}
    self.items = {}
    self.shots = {}
    self.fx = Fx.new()
    self.field = nav.newField()
    self.fieldT = 0
    self.time = 0
    self.killed = 0
    self.total = 0
    self.taken = 0
    self.totalItems = 0
    self.freed = 0
    self.totalAllies = 0
    self.alarmT = 0
    self.alarms = 0
    self.census = {}
    self.tally = {}
    self.messages = {}
    self.finished = nil
    self.sprites = {}

    self.readout = level.readout
    self.dead = {}

    for _, thing in ipairs(level.things) do
        if thing.kind == "enemy" then
            local e = Enemy.new(thing.tier, thing.x, thing.y, self.scale)
            e.dummy = level.dummies
            if not e.dummy then
                e:setPatrol(level)
            end

            if thing.asleep then
                e.asleep = true
                e.frame = "sleep"
                e.patrol = "post"
                e.home = {x = thing.x, y = thing.y}
            end

            self.enemies[#self.enemies + 1] = e
            self.census[e.t.name] = (self.census[e.t.name] or 0) + 1
            if not e:isDog() then
                self.total = self.total + 1
            end
        elseif thing.kind == "prop" then
            self.props[#self.props + 1] = {prop = thing.prop, x = thing.x, y = thing.y}
        elseif thing.kind == "prisoner" then
            local a = Ally.new(thing.x, thing.y)
            a.angle = love.math.random() * math.pi * 2
            self.allies[#self.allies + 1] = a
            self.totalAllies = self.totalAllies + 1
        else
            self.items[#self.items + 1] = {item = thing.item, x = thing.x, y = thing.y}
            self.totalItems = self.totalItems + 1
        end
    end

    self:stockLockers()
    self:spreadGuards()
    self:placeKeys()
    self:scatterStains()

    nav.build(self.field, level, math.floor(self.player.x) + 1, math.floor(self.player.y) + 1)
    self:message("Space opens doors, lockers and the exit")
    self:message("[ and ] set the mouse speed")

    return self
end

-- Who went down, and how. Dogs are counted apart from the men, and a kill
-- nobody heard is worth knowing about at the end of the block.
function World:countKill(e, silent)
    local name = e.t and e.t.name or "Guard"
    self.tally[name] = (self.tally[name] or 0) + 1

    if e.asleep then
        self.tally.asleep = (self.tally.asleep or 0) + 1
    end

    if silent then
        self.tally.quiet = (self.tally.quiet or 0) + 1
    end
end

local RANKS = {"Guard", "Sergeant", "Riot captain", "Dog"}
local PLURAL = {Guard = "Guards", Sergeant = "Sergeants",
    ["Riot captain"] = "Riot captains", Dog = "Dogs"}

-- What the block came to, read out on the way to the next one.
function World:report()
    local level = self.level
    local open, missed = 0, 0

    for _, box in ipairs(level.lockers) do
        if box.opened then
            open = open + 1
        elseif box.stocked then
            missed = missed + 1
        end
    end

    local panels = 0
    for _, panel in ipairs(level.secrets) do
        if panel.opened then
            panels = panels + 1
        end
    end

    local ranks = {}
    for _, name in ipairs(RANKS) do
        local total = self.census[name] or 0
        if total > 0 then
            ranks[#ranks + 1] = {
                name = PLURAL[name] or name,
                killed = self.tally[name] or 0,
                total = total,
            }
        end
    end

    return {
        level = level.name,
        time = self.time,
        ranks = ranks,
        quiet = self.tally.quiet or 0,
        asleep = self.tally.asleep or 0,
        alarms = self.alarms,
        lockers = {open = open, total = #level.lockers, missed = missed},
        panels = {open = panels, total = #level.secrets},
        items = {taken = self.taken, total = self.totalItems},
        prisoners = {freed = self.freed, total = self.totalAllies},
        health = math.floor(self.player.health + 0.5),
        vest = math.floor((self.player.armor or 0) + 0.5),
    }
end

-- Blood on the floor, dropped on a handful of tiles rather than painted into
-- the floor art, which repeats on every tile of the block. The draw is seeded
-- off the name of the level, so a block looks the same every time you come
-- back to it and no two blocks look alike.
function World:scatterStains()
    local level = self.level
    local seed = 2166136261

    for i = 1, #level.name do
        seed = (seed * 31 + level.name:byte(i)) % 2147483647
    end

    local rng = love.math.newRandomGenerator(seed)
    local free = {}

    for cy = 1, level.h do
        for cx = 1, level.w do
            local i = level:index(cx, cy)
            if not level.wall[i] and not level.door[i] and not level.exit[i]
                and not level.locker[i] then
                free[#free + 1] = {cx, cy}
            end
        end
    end

    local used = {}
    local spawn = level:index(math.floor(level.spawn.x) + 1, math.floor(level.spawn.y) + 1)
    local want = math.min(#free, math.floor(#free / 70) + 3)
    local tries = 0

    while want > 0 and tries < 400 do
        tries = tries + 1
        local t = free[rng:random(#free)]
        local i = level:index(t[1], t[2])

        if not used[i] and i ~= spawn then
            used[i] = true
            want = want - 1
            self.props[#self.props + 1] = {
                prop = "stain",
                x = t[1] - 0.8 + rng:random() * 0.6,
                y = t[2] - 0.8 + rng:random() * 0.6,
                size = 0.55 + rng:random() * 0.5,
            }
        end
    end
end

function World:stockLockers()
    local lockers = self.level.lockers
    local armour = 0

    for _, box in ipairs(lockers) do
        box.loot = {}
        box.stocked = false
        if love.math.random() > LOOT_EMPTY then
            for _, row in ipairs(World.LOOT) do
                if #box.loot < LOOT_MAX and love.math.random() < row[2] then
                    box.loot[#box.loot + 1] = row[1]
                    if row[1] == "vest" or row[1] == "vestheavy" then
                        armour = armour + 1
                    end
                end
            end
        end
    end

    -- there is always armour in a cupboard somewhere: going a whole block
    -- without finding any is the dice being unkind, not a design
    for _, box in ipairs(lockers) do
        box.stocked = #box.loot > 0
    end

    if armour == 0 and #lockers > 0 then
        for _ = 1, 12 do
            local box = lockers[love.math.random(#lockers)]
            if #box.loot < LOOT_MAX then
                box.loot[#box.loot + 1] = "vest"
                box.stocked = true

                break
            end
        end
    end
end

-- Two guards standing on the same spot is not a patrol, it is a queue. Anyone
-- who starts the level crowded is moved to a free tile of his own area.
function World:spreadGuards()
    local level = self.level
    local CLOSE = 2.2

    local function crowd(e)
        local n = 0
        for _, o in ipairs(self.enemies) do
            if o ~= e and o.alive then
                local dx, dy = o.x - e.x, o.y - e.y
                if dx * dx + dy * dy < CLOSE * CLOSE then
                    n = n + 1
                end
            end
        end

        return n
    end

    for _, e in ipairs(self.enemies) do
        local area = level:areaOf(e.x, e.y)
        local tiles = area and level.areaTiles[area]
        local cap = (level.areaSize[area or 0] or 0) > 70 and 2 or 1

        if tiles and #tiles > 4 then
            local tries = 0
            while crowd(e) > cap and tries < 24 do
                tries = tries + 1
                local tile = tiles[love.math.random(#tiles)]
                local x, y = tile.x - 0.5, tile.y - 0.5
                if not level:blocked(x, y, e.radius) then
                    local far = true
                    for _, o in ipairs(self.enemies) do
                        if o ~= e then
                            local dx, dy = o.x - x, o.y - y
                            if dx * dx + dy * dy < CLOSE * CLOSE then
                                far = false

                                break
                            end
                        end
                    end

                    if far then
                        e.x, e.y = x, y
                        e.home = {x = x, y = y}
                        e:setPatrol(level)
                    end
                end
            end
        end
    end
end

-- Keys are never left lying about. Each one is on a guard, in a locker, or
-- behind a panel in a wall, whichever the level file asks for, and always as
-- far from the way in as it can be put.
--
-- A key is never put behind the door it opens, which is the one thing that
-- turns a block into a dead end. The reachable set is worked out with
-- nothing in hand, the keys that can be had from there are placed, and then
-- it is worked out again with those in hand, until there is nothing left to
-- place. A colour that cannot be reached at all is left unplaced and said
-- out loud, because the level file is wrong.
function World:placeKeys()
    local level = self.level
    local sx, sy = level.spawn.x, level.spawn.y

    local function farthest(list, fn)
        local best, bestD
        for _, row in ipairs(list) do
            local x, y = fn(row)
            local d = (x - sx) ^ 2 + (y - sy) ^ 2
            if not bestD or d > bestD then
                best, bestD = row, d
            end
        end

        return best
    end

    -- a wall you have to stand in front of: the locker, the panel
    local function faceable(cx, cy, open)
        for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            local j = level:index(cx + d[1], cy + d[2])
            if j and open[j] then
                return true
            end
        end

        return false
    end

    local function place(colour, where, open)
        local item = colour .. "key"

        if where == "guard" then
            local pool = {}
            for _, e in ipairs(self.enemies) do
                local i = level:index(math.floor(e.x) + 1, math.floor(e.y) + 1)
                if e.alive and not e:isDog() and not e.carries and i and open[i] then
                    pool[#pool + 1] = e
                end
            end

            local e = farthest(pool, function(g)
                return g.x, g.y
            end)

            if e then
                e.carries = item
                e.keyName = colour

                return true
            end
        elseif where == "locker" then
            local pool = {}
            for _, box in ipairs(level.lockers) do
                if not box.hasKey and faceable(box.x, box.y, open) then
                    pool[#pool + 1] = box
                end
            end

            local box = farthest(pool, function(b)
                return b.x - 0.5, b.y - 0.5
            end)

            if box then
                box.hasKey = true
                box.loot[#box.loot + 1] = item

                return true
            end
        elseif where == "secret" then
            local pool = {}
            for _, panel in ipairs(level.secrets) do
                if not panel.hasKey and faceable(panel.x, panel.y, open) then
                    pool[#pool + 1] = panel
                end
            end

            local panel = farthest(pool, function(s)
                return s.x - 0.5, s.y - 0.5
            end)

            if panel then
                panel.hasKey = true
                -- the key sits in the hidden space the panel closes off
                for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
                    local cx, cy = panel.x + d[1], panel.y + d[2]
                    local i = level:index(cx, cy)
                    if i and not level.wall[i] and not level.door[i]
                            and level:areaAt(cx, cy) ~= level:areaOf(sx, sy) then
                        self:spawnItem(item, cx - 0.5, cy - 0.5)

                        return true
                    end
                end
            end
        end

        return false
    end

    local todo = {}
    for _, colour in ipairs({"red", "blue", "yellow"}) do
        if level.keyPlace and level.keyPlace[colour] then
            todo[#todo + 1] = colour
        end
    end

    local held = {}
    while #todo > 0 do
        local open = level:reachable(sx, sy, held)
        local done

        for n, colour in ipairs(todo) do
            if place(colour, level.keyPlace[colour], open) then
                held[colour] = true
                done = n

                break
            end
        end

        if not done then
            for _, colour in ipairs(todo) do
                print(string.format("level %s: nowhere to put the %s key that is not behind the %s door",
                    level.path, colour, colour))
            end

            break
        end

        table.remove(todo, done)
    end
end

function World:openLocker(box)
    if not self.level:openLocker(box) then
        return false
    end

    self.audio.play("door", 0.45)
    self:noise(box.x - 0.5, box.y - 0.5, 4, nil)

    if #box.loot == 0 then
        self:message("The locker is empty")

        return true
    end

    local p = self.player
    for i, item in ipairs(box.loot) do
        local a = p.angle + (i - 1.5) * 0.5
        local x = p.x + math.cos(a) * 0.7
        local y = p.y + math.sin(a) * 0.7
        if self.level:blocked(x, y, 0.2) then
            x, y = p.x, p.y
        end

        self:spawnItem(item, x, y)
    end

    self:message(#box.loot == 1 and "Something in the locker"
        or "The locker is full")
    box.loot = {}

    return true
end

-- The panel you are standing in front of and looking at, for the hint on
-- screen. You have to be close and facing it: walking down a corridor does
-- not hand them to you.
function World:panelAhead()
    local p = self.player
    if not p.alive or p.takedown then
        return nil
    end

    local dirx, diry = math.cos(p.angle), math.sin(p.angle)
    for reach = 0.4, 1.3, 0.25 do
        local cx = math.floor(p.x + dirx * reach) + 1
        local cy = math.floor(p.y + diry * reach) + 1
        local panel = self.level:secretAt(cx, cy)
        if panel and not panel.opened then
            return panel
        end
    end

    return nil
end

function World:openSecret(panel)
    if not self.level:revealSecret(panel) then
        return false
    end

    self.audio.play("door", 0.6)
    self:noise(panel.x - 0.5, panel.y - 0.5, 5, nil)
    self:message("A section of wall slides back")

    return true
end

-- Everything below is for testing: the console calls it, ordinary play does
-- not.
function World:spawnGuard(tier, x, y, dummy)
    local e = Enemy.new(tier, x, y, self.scale)
    e.dummy = dummy or false
    if not e.dummy then
        e:setPatrol(self.level)
    end

    self.enemies[#self.enemies + 1] = e
    if not e:isDog() then
        self.total = self.total + 1
    end

    return e
end

function World:clearGuards(killThem)
    local n = 0
    for i = #self.enemies, 1, -1 do
        local e = self.enemies[i]
        if e.alive then
            n = n + 1
            if killThem then
                e:die(self)
            else
                table.remove(self.enemies, i)
                self.total = math.max(0, self.total - 1)
            end
        end
    end

    return n
end

function World:distractGuards()
    local n = 0
    for _, e in ipairs(self.enemies) do
        if e.alive then
            e:distract()
            n = n + 1
        end
    end

    self.alarmT = 0

    return n
end

function World:openSpot(ahead)
    local p = self.player
    local dirx, diry = math.cos(p.angle), math.sin(p.angle)
    for r = ahead, 1.0, -0.3 do
        local x, y = p.x + dirx * r, p.y + diry * r
        if not self.level:blocked(x, y, 0.4) then
            return x, y
        end
    end

    return p.x + dirx * 1.2, p.y + diry * 1.2
end

function World:message(text)
    table.insert(self.messages, 1, {text = text, life = 3.2})
    if #self.messages > 4 then
        table.remove(self.messages)
    end
end

function World:occupied(cx, cy)
    local p = self.player
    if math.floor(p.x) + 1 == cx and math.floor(p.y) + 1 == cy then
        return true
    end

    for _, e in ipairs(self.enemies) do
        if e.alive and math.floor(e.x) + 1 == cx and math.floor(e.y) + 1 == cy then
            return true
        end
    end

    for _, a in ipairs(self.allies) do
        if a.alive and math.floor(a.x) + 1 == cx and math.floor(a.y) + 1 == cy then
            return true
        end
    end

    return false
end

-- How far a guard is from the player on foot. The field is rebuilt from the
-- player's tile a few times a second, so this is what stops a shout from
-- crossing two wings of the prison through a wall.
function World:walkDist(e)
    local d = nav.distAt(self.field, self.level, math.floor(e.x) + 1, math.floor(e.y) + 1)
    if d < 0 then
        return math.huge
    end

    return d
end

-- A noise is answered by the handful of guards nearest to it on foot, never by
-- the whole block. The others, if they are close enough to have heard
-- anything, only get sharper where they stand.
function World:engaged()
    local n = 0
    for _, e in ipairs(self.enemies) do
        if e.alive and e.awake then
            n = n + 1
        end
    end

    return n
end

-- blast is for a rocket or a grenade: that goes through the whole wing and
-- everybody goes to look. A gunshot does not leave the room it was fired in.
function World:alertNear(x, y, radius, source, delay, limit, blast)
    local heard = {}
    local faint = {}
    local here = self.level:areaOf(x, y)

    for _, e in ipairs(self.enemies) do
        if e.alive and e ~= source then
            local dx, dy = e.x - x, e.y - y
            local d = math.sqrt(dx * dx + dy * dy)
            -- a blast is loud enough that how sharp his ears are stops
            -- mattering: it carries its own distance
            local reach = blast and radius or math.min(radius, e.t.hearing)
            if d < reach then
                local theirs = self.level:areaOf(e.x, e.y)
                local same = blast or not here or not theirs or theirs == here
                -- the walking distance gate is what stops a shot being
                -- heard through half the prison. A blast does not need it.
                if same and (blast or self:walkDist(e) < reach * 1.1) then
                    heard[#heard + 1] = {e = e, d = d}
                elseif not same then
                    faint[#faint + 1] = e
                end
            end
        end
    end

    -- the ones a room or two away heard something and nothing more
    for _, e in ipairs(faint) do
        e:unsettle()
    end

    table.sort(heard, function(a, b)
        return a.d < b.d
    end)

    limit = limit or self.scale.respond or 3

    -- and never more than a handful on their feet at the same time, however
    -- much shooting there has been
    local cap = (self.scale.respond or 3) + 1
    limit = math.max(0, math.min(limit, cap - self:engaged()))

    for i, row in ipairs(heard) do
        if i <= limit then
            row.e:tipOff(x, y, (delay or 0.2) + row.d * 0.06, self)
        else
            row.e:onAlarm(self)

            -- a blast is heard by everybody, and the ones who are not going
            -- to walk into it change their round instead
            if blast then
                row.e:unsettle()
            end
        end
    end

    return math.min(#heard, limit)
end

function World:noise(x, y, radius, source, blast)
    self:alertNear(x, y, radius, source, 0.2, nil, blast)
end

-- The guard who has eyes on the player tells the rest over the radio. They walk
-- in, but each of them has to see the player for himself before firing.
-- The klaxon on its own: the whole block gets sharper, nobody is told where
-- anybody is. A loose prisoner is worth this much and no more.
function World:raiseAlarm()
    if self.alarmT <= 0 then
        self.alarms = self.alarms + 1
        self.audio.play("klaxon", 0.3)
        for _, e in ipairs(self.enemies) do
            if e.alive then
                e:onAlarm(self)
            end
        end
    end

    self.alarmT = 6
end

function World:spotted(enemy)
    self:raiseAlarm()
    if enemy.radioT and enemy.radioT > self.time then
        return
    end

    enemy.radioT = self.time + 2.5

    -- the radio only reaches the guards working the same corner of the block
    local p = self.player
    self:alertNear(enemy.x, enemy.y, RADIO, enemy, 0.35, 2)
    for _, e in ipairs(self.enemies) do
        if e ~= enemy and e.alive and e.awake and not e.seeing then
            local dx, dy = e.x - enemy.x, e.y - enemy.y
            if dx * dx + dy * dy < RADIO * RADIO then
                e.lastX, e.lastY = p.x, p.y
            end
        end
    end
end

function World:spawnFx(name, x, y, z, size)
    if name == "fx.blood" then
        self.fx:blood(x, y, z, 5)

        return
    end

    self.fx:spawn{name = name, x = x, y = y, z = z or 0.4, size = size or 0.2}
end

function World:tracer(x, y, angle, dist)
    local dx, dy = math.cos(angle), math.sin(angle)
    for i = 1, 3 do
        local t = dist * (i / 4)
        self.fx:spawn{
            name = "fx.spark",
            x = x + dx * t,
            y = y + dy * t,
            z = 0.5,
            size = 0.035,
            life = 0.07,
            glow = true,
        }
    end
end

function World:impactNear(x, y, angle)
    local dx, dy = math.cos(angle), math.sin(angle)
    local d = self.level:cast(x, y, dx, dy, 4)
    local px, py = x + dx * math.min(d, 1.2), y + dy * math.min(d, 1.2)
    self.fx:sparks(px, py, 0.5, 3)
    self.audio.play("whiz", 0.3)
end

-- quiet says the shot came out of a silencer, which only matters to somebody
-- who has not noticed you yet.
function World:hitscan(x, y, angle, range, damage, owner, quiet)
    local dx, dy = math.cos(angle), math.sin(angle)
    local wall = self.level:cast(x, y, dx, dy, range)
    local limit = math.min(range, wall)
    local best, bestT

    local function consider(e)
        if not e.alive or e == owner then
            return
        end

        local ex, ey = e.x - x, e.y - y
        local t = ex * dx + ey * dy
        if t > 0.05 and t < limit then
            local ox, oy = ex - dx * t, ey - dy * t
            local r = e.hit or e.radius
            if ox * ox + oy * oy < r * r and (not bestT or t < bestT) then
                best, bestT = e, t
            end
        end
    end

    for _, a in ipairs(self.allies) do
        if a.freed then
            consider(a)
        end
    end

    for _, e in ipairs(self.enemies) do
        consider(e)
    end

    if best then
        -- the whole point of the can on the barrel: a round nobody was
        -- waiting for, into a man who has not seen you, puts him down where
        -- he stands and he goes down quietly
        local surprise = quiet and best.unaware and best:unaware()
        if surprise then
            damage = best.hp + 1
        end

        self:tracer(x, y, angle, bestT)
        best:hurt(damage, self, x, y, surprise)
        self.audio.play("flesh", 0.35)

        if surprise and not best.alive and owner == self.player then
            self.player.takedowns = self.player.takedowns + 1
        end

        return best
    end

    self:tracer(x, y, angle, limit)
    self.fx:sparks(x + dx * limit, y + dy * limit, 0.5, 3)
    self.audio.play("ping", 0.25)

    return nil
end

function World:melee(owner, angle, w)
    local best, bestD
    for _, e in ipairs(self.enemies) do
        if e.alive then
            local dx, dy = e.x - owner.x, e.y - owner.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < w.melee + e.radius then
                local off = math.abs(wrap(math.atan2(dy, dx) - angle))
                if off < w.arc and (not bestD or d < bestD) then
                    best, bestD = e, d
                end
            end
        end
    end

    if best then
        local damage = weapons.roll(w)
        if best:unaware() or best:behind(owner.x, owner.y) then
            damage = damage * 2.5
        end

        best:hurt(damage, self, owner.x, owner.y)
        self.audio.play("flesh", 0.45)

        return best
    end

    self.audio.play("swish", 0.3)

    return nil
end

function World:throw(kind, owner, angle, reach, uses)
    local dx, dy = math.cos(angle), math.sin(angle)
    local x = owner.x + dx * 0.4
    local y = owner.y + dy * 0.4
    if self.level:blocked(x, y, 0.1) then
        x, y = owner.x, owner.y
    end

    local shot = Projectile.new(kind, x, y, angle, owner, reach, uses)
    self.shots[#self.shots + 1] = shot

    if shot.k.sound then
        self.audio.play(shot.k.sound, 0.5)
    end

    return shot
end

function World:explode(x, y, radius, damage, owner)
    self.fx:boom(x, y, radius)
    self.audio.play("boom", 0.7)
    self:noise(x, y, 14, nil, true)

    for _, e in ipairs(self.enemies) do
        if e.alive then
            local dx, dy = e.x - x, e.y - y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < radius and self.level:lineOfSight(x, y, e.x, e.y) then
                local falloff = 1 - d / radius
                e:dodge(e.x - x, e.y - y)
                e:hurt(damage * falloff, self, x, y)
            end
        end
    end

    for _, a in ipairs(self.allies) do
        if a.alive and a.freed then
            local dx, dy = a.x - x, a.y - y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < radius and self.level:lineOfSight(x, y, a.x, a.y) then
                a:hurt(damage * (1 - d / radius), self, x, y)
            end
        end
    end

    local p = self.player
    if p.alive then
        local dx, dy = p.x - x, p.y - y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < radius and self.level:lineOfSight(x, y, p.x, p.y) then
            local falloff = 1 - d / radius
            p:hurt(damage * falloff * 0.8, self, x, y)
        end
    end
end

-- The prisoner you are looking at, if he is still waiting in his cell. The
-- line of sight test is what keeps a closed door between you: open it first.
function World:prisonerAt(x, y, reach)
    local p = self.player
    local best, bestD

    for _, a in ipairs(self.allies) do
        if a.alive and not a.freed then
            local dx, dy = a.x - x, a.y - y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < reach and (not bestD or d < bestD)
                    and self.level:lineOfSight(p.x, p.y, a.x, a.y) then
                best, bestD = a, d
            end
        end
    end

    return best
end

-- What the prompt on screen is about: the man in front of you, within arm's
-- reach and a bit, and roughly where you are looking.
-- A leg trap on the floor. The player never springs his own: he knows where
-- he put it. Everybody else has to look where they are going.
World.TRAP_REACH = 0.42
World.TRAP_DOG = 60
World.TRAP_GUARD = 45
World.TRAP_PIN = 2.6        -- seconds a guard spends getting his leg out

function World:placeTrap(player)
    if (player.ammo.traps or 0) <= 0 then
        self:message("No traps left")

        return false
    end

    local dirx, diry = math.cos(player.angle), math.sin(player.angle)
    local x, y = player.x + dirx * 0.8, player.y + diry * 0.8
    if self.level:blocked(x, y, 0.2) then
        x, y = player.x, player.y
    end

    for _, t in ipairs(self.traps) do
        if t.armed and (t.x - x) ^ 2 + (t.y - y) ^ 2 < 0.36 then
            self:message("There is one there already")

            return false
        end
    end

    player.ammo.traps = player.ammo.traps - 1
    self.traps[#self.traps + 1] = {x = x, y = y, armed = true, seen = {}}
    self.audio.play("clink", 0.35)
    self:message(string.format("Trap set, %d left", player.ammo.traps))

    return true
end

function World:springTrap(trap, victim)
    trap.armed = false
    self.audio.play("clink", 0.6)

    local dog = victim.isDog and victim:isDog()
    victim:hurt(dog and World.TRAP_DOG or World.TRAP_GUARD, self, trap.x, trap.y)

    if victim.alive then
        victim.pinT = World.TRAP_PIN
        victim.painT = math.max(victim.painT or 0, 0.5)
        self.audio.play(dog and "bark" or victim.t.sound, 0.5)
        -- a man with his leg in a trap is not quiet about it
        self:noise(trap.x, trap.y, dog and 5 or 9, victim)
    end

    self:spawnFx("fx.blood", trap.x, trap.y, 0.2, 0.3)
end

function World:updateTraps(dt)
    for _, trap in ipairs(self.traps) do
        if trap.armed then
            for _, e in ipairs(self.enemies) do
                if e.alive and not e.asleep then
                    local dx, dy = e.x - trap.x, e.y - trap.y
                    local d2 = dx * dx + dy * dy

                    -- an alert guard gets one look at it from a step away,
                    -- and if he sees it he is not putting his foot in it
                    if d2 < 2.25 and trap.seen[e] == nil then
                        trap.seen[e] = e.awake and not e:isDog()
                            and e.blind <= 0 and love.math.random() < 0.7
                    end

                    if d2 < World.TRAP_REACH * World.TRAP_REACH
                            and not trap.seen[e] then
                        self:springTrap(trap, e)

                        break
                    end
                end
            end
        end
    end
end

function World:prisonerAhead()
    local p = self.player
    if not p.alive or p.takedown then
        return nil
    end

    local dirx, diry = math.cos(p.angle), math.sin(p.angle)
    local man = self:prisonerAt(p.x + dirx * 0.8, p.y + diry * 0.8, 1.6)
    if not man then
        return nil
    end

    local off = math.abs(wrap(math.atan2(man.y - p.y, man.x - p.x) - p.angle))

    return off < 1.2 and man or nil
end

function World:freePrisoner(ally)
    if not ally:free(self) then
        return false
    end

    self.freed = self.freed + 1
    self:message("Prisoner out, and off after the guards")

    return true
end

function World:flashbang(x, y, radius, duration, owner)
    self.fx:pop(x, y)
    self.audio.play("flashbang", 0.6)
    self:noise(x, y, 10, nil)

    for _, e in ipairs(self.enemies) do
        if e.alive then
            local dx, dy = e.x - x, e.y - y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < radius and self.level:lineOfSight(x, y, e.x, e.y) then
                local falloff = 1 - d / radius * 0.7
                e.blind = math.max(e.blind, duration * falloff)
                e.burstLeft = 0
                e.awake = true
            end
        end
    end

    local p = self.player
    local dx, dy = p.x - x, p.y - y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < radius * 0.8 and self.level:lineOfSight(x, y, p.x, p.y) then
        p.blind = math.max(p.blind, 1.4 * (1 - d / (radius * 0.8)))
    end
end

function World:spawnItem(item, x, y, uses)
    self.items[#self.items + 1] = {item = item, x = x, y = y, uses = uses,
        dropped = true}
end

function World:takedownTarget()
    local p = self.player
    if not p.alive or p.takedown then
        return nil
    end

    local best, bestD
    for _, e in ipairs(self.enemies) do
        if e.alive and e.state ~= "held" then
            local dx, dy = e.x - p.x, e.y - p.y
            local d2 = dx * dx + dy * dy
            if d2 < 1.25 then
                local off = math.abs(wrap(math.atan2(dy, dx) - p.angle))
                local open = e:unaware() or (e:behind(p.x, p.y) and e.lostT > 0.3)
                if off < 0.95 and open and (not bestD or d2 < bestD) then
                    best, bestD = e, d2
                end
            end
        end
    end

    return best
end

function World:pickups()
    local p = self.player
    for i = #self.items, 1, -1 do
        local it = self.items[i]
        local dx, dy = it.x - p.x, it.y - p.y
        if dx * dx + dy * dy < 0.2 then
            local ok, text, kind = p:give(it.item, it.uses)
            if ok then
                table.remove(self.items, i)
                self.taken = self.taken + 1
                self:message(text)
                self.audio.play(kind == "key" and "key" or "pickup", 0.5)
            end
        end
    end
end

function World:reachExit()
    if self.finished then
        return
    end

    self.finished = self.level.next and "next" or "escaped"
    self.audio.play("exit", 0.7)
end

function World:playerDied()
    if self.finished then
        return
    end

    self.finished = "dead"
    self.audio.play("dead", 0.7)
end

function World:update(dt)
    self.time = self.time + dt
    self.alarmT = math.max(0, self.alarmT - dt)

    self.fieldT = self.fieldT - dt
    if self.fieldT <= 0 then
        self.fieldT = FIELD_RATE
        nav.build(self.field, self.level, math.floor(self.player.x) + 1,
            math.floor(self.player.y) + 1)
    end

    self.player:update(dt, self)

    for _, e in ipairs(self.enemies) do
        if not self.frozen then
            e:update(dt, self)
        end

        if e.dummy and not e.alive and self.level.respawn then
            e.respawnT = (e.respawnT or 2.5) - dt
            if e.respawnT <= 0 then
                e.alive = true
                e.hp = e.maxHp
                e.anim = 0
                e.frame = "idle"
                e.respawnT = nil
                self.killed = math.max(0, self.killed - 1)
                self.player.kills = math.max(0, self.player.kills - 1)
            end
        end
    end

    for _, a in ipairs(self.allies) do
        if not self.frozen then
            a:update(dt, self)
        end
    end

    if not self.frozen then
        self:updateTraps(dt)
    end

    for i = #self.shots, 1, -1 do
        local shot = self.shots[i]
        shot:update(dt, self)
        if shot.dead then
            table.remove(self.shots, i)
        end
    end

    self.fx:update(dt, self.level)
    self:pickups()

    self.level:updateDoors(dt, function(cx, cy)
        return self:occupied(cx, cy)
    end)

    for i = #self.messages, 1, -1 do
        local m = self.messages[i]
        m.life = m.life - dt
        if m.life <= 0 then
            table.remove(self.messages, i)
        end
    end
end

function World:alerted()
    if self.alarmT > 0 then
        return true
    end

    for _, e in ipairs(self.enemies) do
        if e.alive and e.awake then
            return true
        end
    end

    return false
end

function World:collectSprites(out)
    for i = #out, 1, -1 do
        out[i] = nil
    end

    local held = self.player.takedown and self.player.takedown.victim or nil

    for _, trap in ipairs(self.traps) do
        out[#out + 1] = {
            name = trap.armed and "item.trapset" or "item.trapsprung",
            x = trap.x,
            y = trap.y,
            z = 0,
            size = 0.5,
        }
    end

    for _, prop in ipairs(self.props) do
        out[#out + 1] = {
            name = "prop." .. prop.prop,
            x = prop.x,
            y = prop.y,
            z = 0,
            size = prop.size or 1,
        }
    end

    for _, a in ipairs(self.allies) do
        out[#out + 1] = {
            name = a:sprite(),
            x = a.x,
            y = a.y,
            z = 0,
            size = 0.95,
        }
    end

    for _, e in ipairs(self.enemies) do
        if e ~= held then
            out[#out + 1] = {
                name = e:sprite(),
                x = e.x,
                y = e.y,
                z = 0,
                size = 1,
                warm = e.blind > 0 and 1.1 or 1,
            }
        end
    end

    for _, it in ipairs(self.items) do
        out[#out + 1] = {
            name = "item." .. it.item,
            x = it.x,
            y = it.y,
            z = 0,
            size = 0.62,
        }
    end

    for _, shot in ipairs(self.shots) do
        out[#out + 1] = shot:sprite()
    end

    self.fx:collect(out)

    return out
end

return World
