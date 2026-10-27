-- The prisoners. One of them is waiting in a cell until you open it and tell
-- him to go, and from that moment he is on your side: he runs at the nearest
-- guard he can see and goes at him with his hands. He has no gun, no armour
-- and sixteen hit points, so a guard who sees him coming usually wins. One who
-- does not see him coming rarely does.

local nav = require("src.nav")

local Ally = {}
Ally.__index = Ally

Ally.HP = 16
Ally.SPEED = 2.6
Ally.SIGHT = 12
Ally.REACH = 1.05
Ally.SWING = {16, 30}     -- enough to drop a guard in two, a sergeant in four
Ally.SWING_GAP = 0.75
Ally.RADIUS = 0.28
Ally.FOLLOW = 2.4         -- how close he keeps when there is nobody to hit

local function rnd(a, b)
    return a + love.math.random() * (b - a)
end

local function wrap(a)
    return math.atan2(math.sin(a), math.cos(a))
end

function Ally.new(x, y)
    local self = setmetatable({}, Ally)

    self.x, self.y = x, y
    self.angle = love.math.random() * math.pi * 2
    self.hp = Ally.HP
    self.radius = Ally.RADIUS
    -- the same rule as a guard, from the same art: a prisoner is 31 px of
    -- the 64 px cell, so his shoulders are 0.184 of a tile from his middle
    -- and three quarters of that is the chest. See Enemy.TIERS.
    self.hit = 0.14
    self.alive = true
    self.freed = false
    self.state = "caged"
    self.target = nil
    self.swingT = rnd(0, 0.4)
    self.painT = 0
    self.hitT = 0
    self.anim = 0
    self.walkT = 0
    self.frame = "idle"
    self.moving = false
    self.path = nil
    self.kills = 0

    return self
end

function Ally:free(world)
    if self.freed or not self.alive then
        return false
    end

    self.freed = true
    self.state = "looking"
    self.huntT = 0
    world.audio.play("click", 0.5)

    return true
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

-- He keeps out of the guards' way as much as out of yours: two bodies in one
-- doorway is how both of them get shot.
local function separation(self, world)
    local sx, sy = 0, 0
    local reach = 1.3

    local function push(o)
        local dx, dy = self.x - o.x, self.y - o.y
        local d2 = dx * dx + dy * dy
        if d2 > 1e-4 and d2 < reach * reach then
            local d = math.sqrt(d2)
            local f = (reach - d) / reach
            sx = sx + dx / d * f
            sy = sy + dy / d * f
        end
    end

    for _, a in ipairs(world.allies) do
        if a ~= self and a.alive then
            push(a)
        end
    end

    for _, e in ipairs(world.enemies) do
        if e.alive and e ~= self.target then
            push(e)
        end
    end

    return sx, sy
end

function Ally:navTowards(world, tx, ty)
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

-- The nearest guard he can actually see, which is who he fights.
function Ally:pickTarget(world)
    local best, bestD

    for _, e in ipairs(world.enemies) do
        if e.alive then
            local dx, dy = e.x - self.x, e.y - self.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < Ally.SIGHT and (not bestD or d < bestD)
                    and world.level:lineOfSight(self.x, self.y, e.x, e.y) then
                best, bestD = e, d
            end
        end
    end

    self.target = best
    self.targetD = bestD

    return best
end

-- And when he cannot see one, the nearest one anywhere. He has lived in this
-- block for years and he is not waiting for anybody: the moment the door
-- opens he goes looking, and he keeps looking until there is nobody left.
function Ally:hunt(world, dt)
    self.huntT = (self.huntT or 0) - dt
    if self.hunted and not self.hunted.alive then
        self.hunted = nil
    end

    if self.hunted and self.huntT > 0 then
        return self.hunted
    end

    self.huntT = 0.8

    local best, bestD
    for _, e in ipairs(world.enemies) do
        if e.alive then
            local dx, dy = e.x - self.x, e.y - self.y
            local d = dx * dx + dy * dy
            if not bestD or d < bestD then
                best, bestD = e, d
            end
        end
    end

    self.hunted = best

    return best
end

function Ally:strike(world, guard)
    self.swingT = Ally.SWING_GAP
    self.hitT = 0.22
    world.audio.play("swish", 0.35)

    local damage = rnd(Ally.SWING[1], Ally.SWING[2])
    if guard:unaware() or guard:behind(self.x, self.y) then
        damage = damage * 2.0
    end

    local before = guard.alive
    guard:hurt(damage, world, self.x, self.y)
    world.audio.play("flesh", 0.3)

    if before and not guard.alive then
        self.kills = self.kills + 1
        world:message("A prisoner put one down")
    end
end

function Ally:hurt(amount, world, srcX, srcY)
    if not self.alive then
        return
    end

    self.hp = self.hp - amount
    self.painT = 0.22
    world:spawnFx("fx.blood", self.x, self.y, 0.25, 0.3)

    if srcX and self.state ~= "fight" then
        self.angle = math.atan2(srcY - self.y, srcX - self.x)
    end

    if self.hp <= 0 then
        self:die(world)
    end
end

function Ally:die(world)
    self.alive = false
    self.state = "dead"
    self.anim = 0
    world.audio.play("death", 0.4)
    world:message("A prisoner is down")
end

function Ally:animate(dt)
    self.anim = self.anim + dt

    if not self.alive then
        self.frame = self.anim < 0.18 and "die1" or "dead"

        return
    end

    if self.painT > 0 then
        self.frame = "pain"
    elseif self.hitT > 0 then
        self.frame = "hit"
    elseif self.moving then
        self.frame = (math.floor(self.walkT) % 2 == 0) and "walk1" or "walk2"
    else
        self.frame = "idle"
    end
end

function Ally:sprite()
    return "con." .. self.frame
end

function Ally:update(dt, world)
    if not self.alive then
        self:animate(dt)

        return
    end

    self.painT = math.max(0, self.painT - dt)
    self.hitT = math.max(0, self.hitT - dt)
    self.swingT = math.max(0, self.swingT - dt)
    self.moving = false

    if not self.freed then
        -- still shut in. He turns to whoever walks up, which is the only way
        -- to tell him from the scenery.
        local p = world.player
        local dx, dy = p.x - self.x, p.y - self.y
        if dx * dx + dy * dy < 16 then
            local want = math.atan2(dy, dx)
            self.angle = self.angle + wrap(want - self.angle) * math.min(1, dt * 4)
        end

        self:animate(dt)

        return
    end

    local guard = self:pickTarget(world)
    local tx, ty, closeTo

    if guard then
        self.state = self.targetD < Ally.REACH + guard.radius and "fight" or "charge"
        tx, ty = guard.x, guard.y
        closeTo = Ally.REACH + guard.radius - 0.15
    else
        local hunted = self:hunt(world, dt)
        if hunted then
            self.state = "looking"
            tx, ty = hunted.x, hunted.y
            closeTo = Ally.REACH + hunted.radius - 0.15
        else
            -- nobody left on the block: he sticks with you
            self.state = "follow"
            local p = world.player
            tx, ty = p.x, p.y
            closeTo = Ally.FOLLOW
        end
    end

    local dx, dy = self:navTowards(world, tx, ty)
    local len = math.sqrt(dx * dx + dy * dy)
    local gap = math.sqrt((tx - self.x) ^ 2 + (ty - self.y) ^ 2)

    -- Doors, bars included: the man has just been let out of a cell and the
    -- bars hold nobody who is on this side of them. Only a key stops him.
    -- This runs whether he is moving or not, because a shut door is exactly
    -- what stops him moving.
    if len > 1e-4 then
        local level = world.level
        for reach = 0.45, 1.15, 0.35 do
            local door = level:doorAt(
                math.floor(self.x + dx / len * reach) + 1,
                math.floor(self.y + dy / len * reach) + 1)
            if door and not door.lock then
                level:openDoor(door)

                break
            end
        end
    end

    if len > 1e-4 and gap > closeTo then
        local sx, sy = separation(self, world)
        local mx = dx / len + sx * 0.6
        local my = dy / len + sy * 0.6
        local ml = math.sqrt(mx * mx + my * my)
        if ml > 1e-4 then
            local step = Ally.SPEED * dt
            self.moving = moveBy(self, world.level, mx / ml * step, my / ml * step)
            self.walkT = self.walkT + dt * 6
        end
    end

    if len > 1e-4 then
        local want = math.atan2(dy, dx)
        self.angle = self.angle + wrap(want - self.angle) * math.min(1, dt * 9)
    end

    if guard and self.state == "fight" and self.swingT <= 0 then
        self:strike(world, guard)
    end

    self:animate(dt)
end

return Ally
