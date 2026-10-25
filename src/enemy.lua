-- The guards. Three tiers, one brain. They see with a cone and a line of sight
-- test, hear gunfire, pass the player's position to each other over the radio,
-- walk round corners with the shared navigation field, keep their own fighting
-- distance, strafe while they shoot, step out of the way of a rocket, duck
-- behind a corner when they are hurting, and throw a grenade at where they
-- think you are hiding. None of them stands still waiting to be shot.

local nav = require("src.nav")

local Enemy = {}
Enemy.__index = Enemy

-- radius is what a guard bumps into walls and each other with. hit is the
-- figure a bullet has to be pointed at, cut to the shoulders of the sprite as
-- it is drawn: a shot past him misses, however close it looked.
Enemy.TIERS = {
    {
        key = "g1",
        name = "Guard",
        hp = 28,
        speed = 1.95,
        radius = 0.32,
        hit = 0.26,
        sight = 15,
        fov = 1.05,
        hearing = 8,
        react = {0.40, 0.70},
        aimTime = 0.9,
        accuracy = 0.50,
        damage = {5, 10},
        burst = {1, 2},
        burstGap = 0.16,
        fireGap = {0.85, 1.5},
        turn = 3.4,
        prefer = 5.5,
        strafe = 0.35,
        coverAt = 0.35,
        painChance = 0.6,
        grenade = 0,
        giveUp = 11,
        sound = "shout1",
        gun = "pistol",
        drops = {{"bullets", 0.35}},
    },
    {
        key = "g2",
        name = "Sergeant",
        hp = 48,
        speed = 2.35,
        radius = 0.33,
        hit = 0.27,
        sight = 18,
        fov = 1.25,
        hearing = 10,
        react = {0.22, 0.40},
        aimTime = 0.7,
        accuracy = 0.62,
        damage = {4, 8},
        burst = {3, 5},
        burstGap = 0.10,
        fireGap = {0.75, 1.15},
        turn = 4.2,
        prefer = 7.0,
        strafe = 0.6,
        coverAt = 0.5,
        painChance = 0.35,
        grenade = 0.12,
        giveUp = 20,
        sound = "shout2",
        gun = "uzi",
        -- he is wearing the thing, so sometimes you get to wear it
        drops = {{"vest", 0.14}, {"uzi", 0.16}, {"bullets", 0.22},
            {"ammobox", 0.1}},
    },
    {
        key = "g3",
        name = "Riot captain",
        hp = 85,
        speed = 2.7,
        radius = 0.35,
        hit = 0.29,
        sight = 22,
        fov = 1.45,
        hearing = 12,
        react = {0.12, 0.24},
        aimTime = 0.45,
        accuracy = 0.76,
        damage = {9, 15},
        burst = {2, 3},
        burstGap = 0.22,
        fireGap = {0.55, 0.9},
        turn = 5.0,
        prefer = 4.5,
        strafe = 0.8,
        coverAt = 0.45,
        painChance = 0.15,
        grenade = 0.3,
        giveUp = 40,
        sound = "shout3",
        gun = "shotgun",
        drops = {{"vestheavy", 0.12}, {"rockets", 0.18}, {"grenades", 0.14},
            {"vest", 0.12}, {"ammobox", 0.08}},
    },
    -- The dogs. No gun, no radio, no patience: they run at the nearest
    -- prisoner they can see or smell and bite until one of them stops. A
    -- prisoner of yours is as good a target as you are.
    {
        key = "dg",
        name = "Dog",
        hp = 34,
        speed = 3.5,
        radius = 0.27,
        hit = 0.24,
        sight = 13,
        fov = 1.5,
        hearing = 12,
        react = {0.10, 0.20},
        aimTime = 0.2,
        accuracy = 1,
        damage = {11, 19},
        bite = 1.1,
        burst = {1, 1},
        burstGap = 0.1,
        fireGap = {0.38, 0.55},
        turn = 6.0,
        prefer = 0,
        strafe = 0,
        coverAt = 0,
        painChance = 0.1,
        grenade = 0,
        giveUp = 18,
        sound = "bark",
        gun = "bark",
        drops = {},
    },
}

local function rnd(a, b)
    return a + love.math.random() * (b - a)
end

local function pick(range)
    return rnd(range[1], range[2])
end

local function wrap(a)
    return math.atan2(math.sin(a), math.cos(a))
end

function Enemy.new(tier, x, y, scale)
    local t = Enemy.TIERS[tier] or Enemy.TIERS[1]
    local self = setmetatable({}, Enemy)

    self.tier = tier
    self.t = t
    self.scale = scale or {damage = 1, accuracy = 1, react = 1, speed = 1}
    self.x, self.y = x, y
    self.angle = love.math.random() * math.pi * 2
    self.hp = t.hp
    self.maxHp = t.hp
    self.radius = t.radius
    self.hit = t.hit
    self.state = "idle"
    self.stateT = 0
    self.anim = 0
    self.walkT = 0
    self.frame = "idle"
    self.seeing = false
    self.awake = false
    self.seenT = 0
    self.lostT = 99
    self.lastX, self.lastY = x, y
    self.shotT = t.bite and rnd(0, 0.2) or rnd(0, 0.6)
    self.burstLeft = 0
    self.flashT = 0
    self.painT = 0
    self.blind = 0
    self.dodgeT = 0
    self.dodgeX, self.dodgeY = 0, 0
    self.strafeDir = love.math.random() < 0.5 and -1 or 1
    self.strafeT = rnd(0.5, 1.4)
    self.dist = 99
    self.home = {x = x, y = y}
    self.wanderT = 0
    self.wx, self.wy = x, y
    self.route = nil
    self.routeAt = 1
    self.routeDir = 1
    self.pauseT = rnd(0, 2)
    self.scanAngle = self.angle
    self.patrol = "post"
    self.patrolSpeed = rnd(0.38, 0.58)
    self.alive = true
    self.everSeen = false
    self.wary = 0
    self.path = nil

    return self
end

local STYLES = {"post", "route", "sweep", "route"}

-- Laid out once at level start: a post to stand at, a short round to walk, or a
-- wing to sweep at random. Picked per guard so two of them in the same corridor
-- do not move alike.
function Enemy:setPatrol(level)
    self.homeArea = level:areaAt(math.floor(self.x) + 1, math.floor(self.y) + 1)

    local tiles = nav.flood(level, math.floor(self.x) + 1, math.floor(self.y) + 1, 16,
        level.patrolOpen)
    -- the round stays inside his own area: the point of a guard is that his
    -- corner of the block is covered, not that he is somewhere
    local far = {}
    for _, tile in ipairs(tiles) do
        if tile.d >= 4 and (not self.homeArea
                or level:areaAt(tile.x, tile.y) == self.homeArea) then
            far[#far + 1] = tile
        end
    end

    self.patrol = STYLES[love.math.random(#STYLES)]
    if #far < 2 then
        self.patrol = "post"
    elseif self.t.bite then
        -- a dog is never on a post: it roams its end of the block
        self.patrol = "sweep"
        self.patrolSpeed = rnd(0.5, 0.7)
    end

    self.pool = far

    if self.patrol == "route" then
        local wanted = love.math.random(2, 4)
        local route = {}
        for _ = 1, wanted do
            local tile = far[love.math.random(#far)]
            route[#route + 1] = {x = tile.x - 0.5, y = tile.y - 0.5}
        end

        self.route = route
        self.routeAt = 1
        self.wx, self.wy = route[1].x, route[1].y
    elseif self.patrol == "sweep" then
        local tile = far[love.math.random(#far)]
        self.wx, self.wy = tile.x - 0.5, tile.y - 0.5
    end
end

-- The klaxon. Every guard in the block hears it and gets sharper, but only the
-- ones already near you have any idea where to go.
function Enemy:onAlarm(world)
    self.wary = math.max(self.wary or 0, 9)

    -- the klaxon is loud enough to get anybody out of a chair
    if self.asleep then
        self:wake(world)
    end
end

-- Something was heard a long way off, through a door or two. He has no idea
-- where it came from and he is not leaving his corner over it: he gets
-- sharper and walks a different round.
function Enemy:unsettle()
    if not self.alive or self.awake or self.asleep then
        return false
    end

    self.wary = math.max(self.wary or 0, 9)

    if self.pool and #self.pool > 1 then
        local tile = self.pool[love.math.random(#self.pool)]
        self.wx, self.wy = tile.x - 0.5, tile.y - 0.5
        self.patrol = "sweep"
        self.pauseT = rnd(0.1, 0.6)
    end

    return true
end

-- True when he would have to leave his own area to get there and he is the
-- last man in it. Somebody always stays.
function Enemy:holdArea(world, tx, ty)
    if not self.homeArea or self:isDog() then
        return false
    end

    local level = world.level
    if level:areaOf(tx, ty) == self.homeArea then
        return false
    end

    for _, e in ipairs(world.enemies) do
        if e ~= self and e.alive and not e:isDog()
                and e.homeArea == self.homeArea
                and level:areaOf(e.x, e.y) == self.homeArea then
            return false
        end
    end

    return true
end

-- Back to the round as if nothing had happened.
function Enemy:distract()
    self.awake = false
    self.everSeen = false
    self.seeing = false
    self.seenT = 0
    self.lostT = 99
    self.wary = 0
    self.state = "idle"
    self.stateT = 0
    self.burstLeft = 0
    self.path = nil
    self.pathTo = nil
    self.pauseT = 0.6
end

function Enemy:unaware()
    if self.asleep then
        return self.alive
    end

    return self.alive and not self.awake and self.state == "idle"
end

-- Shaken awake by a noise, a shout or a bullet. He is on his feet but good
-- for nothing for a moment, which is usually the moment that decides it.
function Enemy:wake(world, x, y)
    if not self.asleep or not self.alive then
        return false
    end

    self.asleep = false
    self.wakeT = 0.9
    self.awake = true
    self.state = "hunt"
    self.stateT = self.t.giveUp
    self.pauseT = 0.5
    self.lastX, self.lastY = x or self.x, y or self.y
    self.angle = math.atan2((y or self.y) - self.y, (x or self.x) - self.x)

    if world then
        world.audio.play(self.t.sound, 0.5)
    end

    return true
end

-- True when the player is somewhere behind the guard's shoulders.
function Enemy:behind(px, py)
    local off = math.abs(wrap(math.atan2(py - self.y, px - self.x) - self.angle))

    return off > 2.05
end

function Enemy:name()
    return self.t.name
end

local function moveBy(self, level, dx, dy)
    local nx, ny = self.x + dx, self.y + dy
    local moved = false

    if not level:blocked(nx, self.y, self.radius) then
        self.x = nx
        moved = true
    end

    if not level:blocked(self.x, ny, self.radius) then
        self.y = ny
        moved = true
    end

    return moved
end

-- Who the guard is dealing with: the player, or a freed prisoner when the
-- player is nowhere in sight. Everything that aims, closes or takes cover
-- reads this rather than the player directly.
function Enemy:foe(world)
    if self.threat and self.threat.alive then
        return self.threat
    end

    return world.player
end

function Enemy:isDog()
    return self.t.bite ~= nil
end

-- The nearest freed prisoner this guard can actually see.
function Enemy:seeAlly(world)
    local best, bestD

    for _, a in ipairs(world.allies or {}) do
        if a.alive and a.freed then
            local dx, dy = a.x - self.x, a.y - self.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < self.t.sight and (not bestD or d < bestD) then
                local off = math.abs(wrap(math.atan2(dy, dx) - self.angle))
                local cone = self.awake and math.min(2.5, self.t.fov * 1.7) or self.t.fov
                if (off < cone or d < 1.8)
                        and world.level:lineOfSight(self.x, self.y, a.x, a.y) then
                    best, bestD = a, d
                end
            end
        end
    end

    return best, bestD
end

function Enemy:sense(dt, world)
    local t = self.t
    local p = world.player
    local dx, dy = p.x - self.x, p.y - self.y
    local dist = math.sqrt(dx * dx + dy * dy)
    self.dist = dist

    local see = false
    local sight = t.sight * (self.wary > 0 and 1.12 or 1)
    if p.alive and not p.invisible and self.blind <= 0 and dist < sight then
        local off = math.abs(wrap(math.atan2(dy, dx) - self.angle))
        local cone = t.fov
        if self.awake then
            cone = math.min(2.5, cone * 1.7)
        elseif self.wary > 0 then
            cone = cone * 1.35
        end

        if off < cone or dist < 1.8 then
            see = world.level:lineOfSight(self.x, self.y, p.x, p.y)
        end
    end

    self.seeing = see
    self.threat = nil

    if not see and self.blind <= 0 then
        local a, ad = self:seeAlly(world)
        if a then
            self.threat = a
            self.dist = ad
            self.seeing = true
            see = false
        end
    elseif see and self:isDog() then
        -- a dog takes whoever is nearest, and a loose prisoner usually is
        local a, ad = self:seeAlly(world)
        if a and ad < dist then
            self.threat = a
            self.dist = ad
        end
    end

    if not self.seeing and self.state == "idle" then
        self.bodyT = (self.bodyT or rnd(0, 0.6)) - dt
        if self.bodyT <= 0 then
            self.bodyT = 0.5
            for _, other in ipairs(world.enemies) do
                if not other.alive then
                    local ox, oy = other.x - self.x, other.y - self.y
                    if ox * ox + oy * oy < 9
                            and world.level:lineOfSight(self.x, self.y, other.x, other.y) then
                        world.audio.play(t.sound, 0.45)
                        self:tipOff(other.x, other.y, 0.4, world)
                        break
                    end
                end
            end
        end
    end

    if see then
        self.lastX, self.lastY = p.x, p.y
        self.lostT = 0
        self.seenT = self.seenT + dt
        self.awake = true
        self.everSeen = true

        world:spotted(self)
    elseif self.threat then
        -- a prisoner out of his cell is dealt with where he stands, and none
        -- of it tells the block where the player is
        self.lastX, self.lastY = self.threat.x, self.threat.y
        self.lostT = 0
        self.seenT = self.seenT + dt
        self.awake = true

        world:raiseAlarm()
    else
        self.lostT = self.lostT + dt
        self.seenT = 0
    end
end

-- Another guard, or a loud noise, pointing this one at the player.
function Enemy:tipOff(x, y, delay, world)
    if not self.alive then
        return
    end

    if self.asleep then
        self:wake(world, x, y)

        return
    end

    -- scatter the spot a little so a pair of guards covers the room instead of
    -- walking to the same tile
    local a = love.math.random() * math.pi * 2
    local r = rnd(0.2, 1.1)
    self.lastX, self.lastY = x + math.cos(a) * r, y + math.sin(a) * r
    self.awake = true

    if self.state == "idle" or self.state == "blind" then
        self.state = "hunt"
        self.stateT = self.t.giveUp * 0.7
        self.pauseT = (delay or 0.3) * self.scale.react
    end
end

function Enemy:think(dt, world)
    local t = self.t
    self.stateT = self.stateT - dt

    if self.painT > 0 then
        return
    end

    if self.blind > 0 then
        self.state = "blind"

        return
    elseif self.state == "blind" then
        self.state = self.awake and "hunt" or "idle"
        self.stateT = 2
    end

    if self.state == "idle" then
        if self.seeing then
            self.state = "alert"
            self.stateT = pick(t.react) * self.scale.react * (self.wary > 0 and 0.6 or 1)
            world.audio.play(t.sound, 0.5)
        end
    elseif self.state == "alert" then
        if self.stateT <= 0 then
            self.state = "fight"
        end
    elseif self.state == "fight" then
        if self.lostT > 0.7 then
            self.state = "hunt"
            self.stateT = t.giveUp
        elseif self.hp < self.maxHp * t.coverAt and self.shotT > 0.2
                and love.math.random() < dt * 0.9 then
            local foe = self:foe(world)
            local cx, cy = nav.cover(world.level, world.field, self.x, self.y,
                foe.x, foe.y, 5)
            if cx then
                self.state = "cover"
                self.stateT = rnd(1.2, 2.4)
                self.wx, self.wy = cx, cy
            end
        end
    elseif self.state == "hunt" then
        if self.seeing then
            self.state = "fight"
        elseif self.stateT <= 0 or world:walkDist(self) > 30 then
            self.state = "idle"
            self.awake = false
            self.pauseT = rnd(0.5, 1.5)
        end
    elseif self.state == "cover" then
        local dx, dy = self.wx - self.x, self.wy - self.y
        if self.seeing and self.dist < 2.5 then
            self.state = "fight"
        elseif self.stateT <= 0 or dx * dx + dy * dy < 0.12 then
            if self.stateT <= -0.9 then
                self.state = self.awake and "hunt" or "idle"
                self.stateT = t.giveUp
            end
        end
    end
end

-- Guards keep out of each other's way wherever they are, not only in a fight.
local function separation(self, world, reach)
    reach = reach or 1.7
    local sx, sy = 0, 0

    for _, e in ipairs(world.enemies) do
        if e ~= self and e.alive then
            local dx, dy = self.x - e.x, self.y - e.y
            local d2 = dx * dx + dy * dy
            if d2 > 1e-4 and d2 < reach * reach then
                local d = math.sqrt(d2)
                local f = (reach - d) / reach
                sx = sx + dx / d * f
                sy = sy + dy / d * f
            end
        end
    end

    return sx, sy
end

-- And they are solid: nobody walks through a colleague.
local function unstack(self, world)
    for _, e in ipairs(world.enemies) do
        if e ~= self and e.alive then
            local dx, dy = self.x - e.x, self.y - e.y
            local d2 = dx * dx + dy * dy
            local min = self.radius + e.radius
            if d2 < min * min then
                local d = math.sqrt(d2)
                if d < 1e-4 then
                    dx, dy, d = love.math.random() - 0.5, love.math.random() - 0.5, 0.5
                end

                local push = (min - d) * 0.5
                local nx = self.x + dx / d * push
                local ny = self.y + dy / d * push
                if not world.level:blocked(nx, self.y, self.radius) then
                    self.x = nx
                end

                if not world.level:blocked(self.x, ny, self.radius) then
                    self.y = ny
                end
            end
        end
    end
end

function Enemy:bumpDoors(world, dx, dy)
    local level = world.level
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-4 then
        return
    end

    local ahead = 0.55
    local cx = math.floor(self.x + dx / len * ahead) + 1
    local cy = math.floor(self.y + dy / len * ahead) + 1
    local door = level:doorAt(cx, cy)
    if not door or door.state == "open" or door.state == "opening" then
        return
    end

    -- on a quiet round nobody rattles the cell doors, that only happens once
    -- they are looking for you
    if (door.barred or door.lock) and not self.awake then
        return
    end

    level:openDoor(door)
    world.audio.play("door", 0.35)
end

-- Walks towards a place, not towards the player. A guard who cannot see you
-- is heading for where he last had a reason to believe you were, and he keeps
-- that path until it runs out or the belief changes.
function Enemy:navTowards(world, tx, ty)
    local level = world.level
    if level:lineOfSight(self.x, self.y, tx, ty) then
        self.pathAt = nil

        return tx - self.x, ty - self.y
    end

    local moved = not self.pathTo
        or math.abs(self.pathTo.x - tx) + math.abs(self.pathTo.y - ty) > 1.5
    if moved or not self.pathAt or world.time > self.pathAt + 1.1 then
        self.path = nav.path(level, math.floor(self.x) + 1, math.floor(self.y) + 1,
            math.floor(tx) + 1, math.floor(ty) + 1, 70, self.path)
        self.pathTo = {x = tx, y = ty}
        self.pathAt = world.time
        self.pathAt0 = 1
    end

    local i = self.pathAt0 or 1
    local wp = self.path and self.path[i]
    while wp do
        local dx, dy = wp.x - self.x, wp.y - self.y
        if dx * dx + dy * dy > 0.16 then
            break
        end

        i = i + 1
        wp = self.path[i]
    end

    self.pathAt0 = i

    if not wp then
        return tx - self.x, ty - self.y
    end

    return wp.x - self.x, wp.y - self.y
end

-- The round. A guard on a post looks around and shifts his weight, one on a
-- route walks it and back, one sweeping picks a new corner of his wing each
-- time he arrives. All three stop now and then to scan.
function Enemy:patrolStep(dt, world)
    self.pauseT = self.pauseT - dt

    if self.pauseT > 0 then
        self.scanT = (self.scanT or 0) - dt
        if self.scanT <= 0 then
            self.scanT = rnd(1.1, 2.6)
            self.scanAngle = self.angle + rnd(-2.2, 2.2)
        end

        return 0, 0, 0
    end

    if self.patrol == "post" then
        local dx, dy = self.home.x - self.x, self.home.y - self.y
        if dx * dx + dy * dy > 0.3 then
            return dx, dy, self.patrolSpeed
        end

        self.pauseT = rnd(1.5, 4)
        self.scanT = 0
        local a = love.math.random() * math.pi * 2
        local r = rnd(0.6, 1.6)
        local tx, ty = self.home.x + math.cos(a) * r, self.home.y + math.sin(a) * r
        if not world.level:blocked(tx, ty, self.radius) then
            self.home.x, self.home.y = tx, ty
        end

        return 0, 0, 0
    end

    local dx, dy = self.wx - self.x, self.wy - self.y
    if dx * dx + dy * dy < 0.2 then
        self.pauseT = rnd(0.7, 2.8)
        self.scanT = 0

        if self.patrol == "route" and self.route then
            self.routeAt = self.routeAt + self.routeDir
            if self.routeAt > #self.route then
                self.routeAt = math.max(1, #self.route - 1)
                self.routeDir = -1
            elseif self.routeAt < 1 then
                self.routeAt = math.min(#self.route, 2)
                self.routeDir = 1
            end

            local wp = self.route[self.routeAt]
            self.wx, self.wy = wp.x, wp.y
        elseif self.pool and #self.pool > 0 then
            local tile = self.pool[love.math.random(#self.pool)]
            self.wx, self.wy = tile.x - 0.5, tile.y - 0.5
        end

        return 0, 0, 0
    end

    local nx, ny = self:navTowards(world, self.wx, self.wy)

    return nx, ny, self.patrolSpeed
end

function Enemy:desire(dt, world)
    local t = self.t
    local p = self:foe(world)

    if self.state == "idle" then
        return self:patrolStep(dt, world)
    end

    if self.state == "alert" then
        return 0, 0, 0
    end

    if self.pauseT > 0 and (self.state == "hunt" or self.state == "blind") then
        self.pauseT = self.pauseT - dt
        self.scanT = (self.scanT or 0) - dt
        if self.scanT <= 0 then
            self.scanT = rnd(0.7, 1.6)
            self.scanAngle = self.angle + rnd(-2.4, 2.4)
        end

        return 0, 0, 0
    end

    if self.state == "blind" then
        local dx, dy = self.x - self.lastX, self.y - self.lastY

        return dx, dy, 0.5
    end

    if self.state == "cover" then
        local dx, dy = self:navTowards(world, self.wx, self.wy)

        return dx, dy, 1
    end

    if self.state == "hunt" then
        -- the last man in an area does not walk out of it to go looking
        if self:holdArea(world, self.lastX, self.lastY) then
            self.scanAngle = math.atan2(self.lastY - self.y, self.lastX - self.x)
            self.pauseT = math.max(self.pauseT, 0.4)

            return 0, 0, 0
        end

        local dx, dy = self.lastX - self.x, self.lastY - self.y
        if dx * dx + dy * dy < 0.5 then
            -- nothing here: look around, then try the next corner along
            self.pauseT = rnd(0.7, 1.6)
            self.scanT = 0

            local best
            for _ = 1, 6 do
                local a = love.math.random() * math.pi * 2
                local r = rnd(1.5, 4.5)
                local tx, ty = self.lastX + math.cos(a) * r, self.lastY + math.sin(a) * r
                if not world.level:blocked(tx, ty, self.radius) then
                    best = {x = tx, y = ty}
                    break
                end
            end

            if best then
                self.lastX, self.lastY = best.x, best.y
            end

            return 0, 0, 0
        end

        local nx, ny = self:navTowards(world, self.lastX, self.lastY)

        return nx, ny, 0.9
    end

    -- fighting: hold the tier's range, slide sideways, and never line up with
    -- the guard next to you. Chasing him into the next room is for when
    -- somebody else is covering this one.
    if not self.seeing and self:holdArea(world, self.lastX, self.lastY) then
        self.scanAngle = math.atan2(self.lastY - self.y, self.lastX - self.x)

        return 0, 0, 0
    end

    local dx, dy = p.x - self.x, p.y - self.y
    local d = math.max(0.001, math.sqrt(dx * dx + dy * dy))
    local fx, fy = dx / d, dy / d
    local want = 0

    if not self.seeing then
        local nx, ny = self:navTowards(world, self.lastX, self.lastY)

        return nx, ny, 1
    end

    if d > t.prefer + 1.2 then
        want = 1
    elseif d < t.prefer - 1.6 then
        want = -1
    end

    self.strafeT = self.strafeT - dt
    if self.strafeT <= 0 then
        self.strafeT = rnd(0.6, 1.7)
        self.strafeDir = -self.strafeDir
    end

    local sx, sy = -fy * self.strafeDir, fx * self.strafeDir
    local mx = fx * want + sx * t.strafe
    local my = fy * want + sy * t.strafe

    return mx, my, 1
end

function Enemy:act(dt, world)
    local t = self.t
    local level = world.level
    local speed = t.speed * self.scale.speed

    if self.painT > 0 then
        self.painT = self.painT - dt

        return
    end

    local mx, my, gain = self:desire(dt, world)

    if self.dodgeT > 0 then
        self.dodgeT = self.dodgeT - dt
        mx, my = self.dodgeX, self.dodgeY
        gain = 1.35
    end

    -- everyone, in every state, drifts away from whoever is too close
    local rx, ry = separation(self, world)
    if rx ~= 0 or ry ~= 0 then
        local weight = (self.state == "fight" and 1.15 or 1.3) * math.max(0.4, gain)
        mx, my = mx + rx * weight, my + ry * weight
        if gain <= 0 then
            gain = 0.45
        end
    end

    -- one leg in a trap: he can still shout and shoot, he just is not going
    -- anywhere until he is out of it
    if self.pinT and self.pinT > 0 then
        self.pinT = self.pinT - dt
        self.moving = false

        return
    end

    local len = math.sqrt(mx * mx + my * my)
    self.moving = false
    if len > 1e-4 and gain > 0 then
        mx, my = mx / len * speed * gain, my / len * speed * gain
        self:bumpDoors(world, mx, my)

        local moved = moveBy(self, level, mx * dt, my * dt)
        self.moving = moved
        unstack(self, world)
        if not moved then
            self.strafeDir = -self.strafeDir
            self.strafeT = rnd(0.4, 0.9)
            moveBy(self, level, -my * dt * 0.8, mx * dt * 0.8)
        end

        self.walkT = self.walkT + dt * (2.5 + speed)
    end

    -- face the player when fighting, otherwise face where you walk
    local want = self.angle
    if self.seeing or self.state == "fight" or self.state == "alert" then
        local foe = self:foe(world)
        want = math.atan2(foe.y - self.y, foe.x - self.x)
    elseif len > 1e-4 then
        want = math.atan2(my, mx)
    else
        want = self.scanAngle
    end

    local off = wrap(want - self.angle)
    local maxTurn = t.turn * dt
    if off > maxTurn then
        off = maxTurn
    elseif off < -maxTurn then
        off = -maxTurn
    end

    self.angle = self.angle + off

    self:gunplay(dt, world, math.abs(wrap(want - self.angle)))
end

function Enemy:gunplay(dt, world, aimOff)
    local t = self.t
    self.shotT = math.max(0, self.shotT - dt)
    self.flashT = math.max(0, self.flashT - dt)

    if self.state ~= "fight" and self.state ~= "cover" then
        self.burstLeft = 0
    end

    if self.burstLeft > 0 then
        if not self.seeing then
            self.burstLeft = 0
            self.shotT = math.max(self.shotT, 0.3)
        elseif self.shotT <= 0 then
            self:shoot(world)
            self.burstLeft = self.burstLeft - 1
            self.shotT = t.burstGap
            if self.burstLeft <= 0 then
                self.shotT = pick(t.fireGap)
            end
        end

        return
    end

    if self.seeing and self.state == "fight" and self.shotT <= 0 and aimOff < 0.22 then
        self.burstLeft = math.floor(rnd(t.burst[1], t.burst[2] + 0.999))

        return
    end

    -- can't see him, but we know roughly where he went: lob something
    if t.grenade > 0 and not self.seeing and self.awake and self.shotT <= 0
            and self.lostT > 1.1 and self.lostT < 6 then
        local dx, dy = self.lastX - self.x, self.lastY - self.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d > 2.5 and d < 11 and love.math.random() < t.grenade * dt * 3 then
            world:throw("grenade", self, math.atan2(dy, dx), d)
            world.audio.play("throw", 0.45)
            self.shotT = rnd(3, 5)
        end
    end
end

-- Who the shot goes at. The guards are after the player, but a prisoner
-- running at them with his hands up gets dealt with first, which is the whole
-- reason a freed prisoner is worth something and also how he dies.
function Enemy:victim(world)
    if self.threat and self.threat.alive then
        local dx, dy = self.threat.x - self.x, self.threat.y - self.y

        return self.threat, math.sqrt(dx * dx + dy * dy)
    end

    local p = world.player
    local best, bestD = p, p.alive and self.dist or 1e9

    for _, a in ipairs(world.allies or {}) do
        if a.alive and a.freed then
            local dx, dy = a.x - self.x, a.y - self.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < bestD and d < self.t.sight
                    and world.level:lineOfSight(self.x, self.y, a.x, a.y) then
                best, bestD = a, d
            end
        end
    end

    return best, bestD
end

function Enemy:shoot(world)
    local t = self.t
    local p, pd = self:victim(world)
    self.flashT = 0.09

    if t.bite then
        -- teeth only: close enough or nothing happens
        if pd > t.bite + 0.35 then
            return
        end

        world.audio.play("flesh", 0.3)
        p:hurt(rnd(t.damage[1], t.damage[2]) * self.scale.damage, world, self.x, self.y)
        world:spawnFx("fx.blood", p.x, p.y, 0.3, 0.3)

        return
    end

    world.audio.play(t.gun, 0.45)
    world:noise(self.x, self.y, 8, self)
    world:tracer(self.x, self.y, self.angle, math.min(pd, t.sight))

    local aim = 0.55 + 0.45 * math.min(1, self.seenT / t.aimTime)
    local far = math.max(0.35, 1.18 - pd * 0.032)
    local move = 1 - math.min(0.3, (p.speed and p:speed() or 0) * 0.055)
    local chance = t.accuracy * self.scale.accuracy * aim * far * move

    if love.math.random() < chance then
        local dmg = rnd(t.damage[1], t.damage[2]) * self.scale.damage
        p:hurt(dmg, world, self.x, self.y)
        world:spawnFx("fx.blood", p.x, p.y, 0.25, 0.3)
    else
        local miss = self.angle + (love.math.random() - 0.5) * 0.16
        world:impactNear(p.x, p.y, miss)
    end
end

function Enemy:dodge(dx, dy)
    if self.t.grenade <= 0 and self.tier < 2 then
        return
    end

    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-4 then
        return
    end

    local side = love.math.random() < 0.5 and 1 or -1
    self.dodgeX = -dy / len * side
    self.dodgeY = dx / len * side
    self.dodgeT = 0.55
end

function Enemy:hurt(amount, world, srcX, srcY)
    if not self.alive then
        return
    end

    self.hp = self.hp - amount

    if world.readout then
        world:message(("%s took %d, %d left"):format(self.t.name,
            math.floor(amount + 0.5), math.max(0, math.floor(self.hp + 0.5))))
    end

    if self.dummy then
        world:spawnFx("fx.blood", self.x, self.y, 0.45, 0.25)
        if self.hp <= 0 then
            self:die(world)
        end

        return
    end

    if self.asleep then
        self:wake(world, srcX, srcY)
    end

    self.awake = true

    if srcX then
        self.lastX, self.lastY = srcX, srcY
    end

    world:spawnFx("fx.blood", self.x, self.y, 0.45, 0.25)

    if self.hp <= 0 then
        self:die(world)

        return
    end

    if self.state == "idle" or self.state == "alert" then
        self.state = "fight"
    end

    if love.math.random() < self.t.painChance then
        self.painT = 0.22
        self.burstLeft = 0
        self.shotT = math.max(self.shotT, 0.25)
        world.audio.play("grunt", 0.4)
    end
end

function Enemy:die(world, silent)
    self.alive = false
    self.state = "dead"
    self.anim = silent and 0.36 or 0
    self.burstLeft = 0

    if self:isDog() then
        world.audio.play("bark", 0.35, 0.6)
    else
        world.audio.play(silent and "cut" or "death", silent and 0.45 or 0.5)
    end
    world:noise(self.x, self.y, silent and 2.5 or 6, self)
    world.player.kills = world.player.kills + 1

    if not self:isDog() then
        world.killed = world.killed + 1
    end

    if self.carries then
        world:spawnItem(self.carries, self.x, self.y)
        world:message(self.t.name .. " was carrying the " ..
            (self.keyName or "") .. " key")
        self.carries = nil
    end

    -- most of them are carrying nothing worth picking up
    local roll = love.math.random()
    local acc = 0
    for _, drop in ipairs(self.t.drops) do
        acc = acc + drop[2]
        if roll <= acc then
            world:spawnItem(drop[1], self.x, self.y)
            break
        end
    end
end

-- Grabbed from behind. The guard is out of the fight from this moment, the
-- animation on the player's side decides when he drops.
function Enemy:grab()
    self.state = "held"
    self.burstLeft = 0
    self.painT = 0.3
end

function Enemy:execute(world)
    self.hp = 0
    self:die(world, true)
end

function Enemy:animate(dt)
    self.anim = self.anim + dt

    if not self.alive then
        local a = self.anim
        if a < 0.12 then
            self.frame = "die1"
        elseif a < 0.24 then
            self.frame = "die2"
        elseif a < 0.36 then
            self.frame = "die3"
        else
            self.frame = "dead"
        end

        return
    end

    if self.painT > 0 then
        self.frame = "pain"
    elseif self.flashT > 0 then
        self.frame = "fire"
    elseif self.burstLeft > 0 or (self.seeing and self.state == "fight") then
        self.frame = "aim"
    elseif self.moving then
        local step = math.floor(self.walkT % 4) + 1
        self.frame = "walk" .. step
    else
        self.frame = "idle"
    end
end

function Enemy:sprite()
    return self.t.key .. "." .. self.frame
end

function Enemy:update(dt, world)
    if not self.alive then
        self:animate(dt)

        return
    end

    -- a target on the range: it stands there and lets you measure a weapon
    if self.dummy then
        self.frame = "idle"
        self.angle = math.atan2(world.player.y - self.y, world.player.x - self.x)

        return
    end

    if self.state == "held" then
        self.frame = "pain"

        return
    end

    if self.asleep then
        self.frame = "sleep"
        self.moving = false

        return
    end

    if self.wakeT and self.wakeT > 0 then
        -- on his feet but still half asleep
        self.wakeT = self.wakeT - dt
        self.frame = "idle"
        self:sense(dt, world)

        return
    end

    self.blind = math.max(0, self.blind - dt)
    self.wary = math.max(0, self.wary - dt)
    self:sense(dt, world)
    self:think(dt, world)
    self:act(dt, world)
    self:animate(dt)
end

return Enemy
