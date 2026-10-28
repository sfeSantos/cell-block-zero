-- The convict. Starts with a hatchet, a revolver and a vest at half strength,
-- which is exactly what the guard who walked into his cell was carrying.

local weapons = require("src.weapons")

local Player = {}
Player.__index = Player

local RADIUS = 0.26
local WALK = 2.5
local RUN = 4.1
local TURN = 2.7
-- bullets are what the revolver takes, clips are the 9mm the uzi eats. One
-- will not go in the other, which is the point of carrying both.
local MAX = {bullets = 90, clips = 200, rockets = 20, grenades = 9, flashes = 6,
    knives = 12, traps = 4}
local BLADE_USES = 3      -- throws in a blade before it is scrap
local BLADES = 4          -- how many of them you can carry

-- Radians of turn per pixel of mouse travel, picked by step in the menu.
Player.SENSITIVITY = {0.00025, 0.0004, 0.0006, 0.0009, 0.0012, 0.0016, 0.0021,
    0.0028, 0.0038}
Player.SENS_DEFAULT = 3

local PITCH_RATE = 0.30   -- vertical look is gentler than the turn
local PITCH_LIMIT = 0.28

-- The sight sits on the horizon, because that is where the shot goes. A view
-- left tilted therefore puts the sight somewhere the player is not looking,
-- and nothing in a corridor tells you how far off level you are, so the view
-- eases itself back once nobody is asking for a vertical look.
local PITCH_HOLD = 1.1    -- seconds it keeps the height you looked at
local PITCH_HOME = 7.0    -- and then it comes home quickly, so it reads as a
                          -- snap back and not as the sight drifting
local SPIKE = 180         -- pixels of mouse travel in one event, past this it
                          -- is the pointer being warped, not an aim

-- The mouse turns and so do the arrows, and two controls on one axis fight
-- each other. The mouse wins: while it is aiming the turn keys stand down,
-- and they come back shortly after the hand stops.
local MOUSE_OWN = 0.18    -- seconds the mouse keeps the view to itself
local MOUSE_FADE = 0.28   -- and how long the keys take to come back after that
local LOOK_FLOOR = 2      -- pixels, below this it is sensor noise, not an aim

function Player.new(spawn)
    local self = setmetatable({}, Player)

    self.x, self.y = spawn.x, spawn.y
    self.angle = spawn.angle
    self.vx, self.vy = 0, 0
    self.health = 100
    self.armor = 50
    self.armorMax = 100
    self.ammo = {bullets = 24, clips = 0, rockets = 0, grenades = 0,
        flashes = 0, knives = 0, traps = 0}
    self.mag = {}
    self.reloadT = 0
    self.reloadMax = 0
    self.has = {hatchet = true, revolver = true}
    self.blades = {}
    self.keys = {}
    self.weapon = "revolver"
    self.pending = nil
    self.cooldown = 0
    self.fireT = 0
    self.throwT = 0
    self.throwView = nil
    self.muzzle = 0
    self.viewZ = 0
    self.bobT = 0
    self.kick = 0
    self.hurtT = 0
    self.hurtDir = 0
    self.blind = 0
    self.lookDelta = 0
    self.lookAge = 99
    self.pitch = 0
    self.pitchDelta = 0
    self.pitchAge = 99
    self.silencer = false
    self.silenced = false
    self.takedown = nil
    self.takedowns = 0
    self.alive = true
    self.kills = 0
    self.god = false
    self.invisible = false
    self.endlessAmmo = false
    self.sensitivity = Player.SENSITIVITY[Player.SENS_DEFAULT]
    self.invertY = -1
    self.invertX = 1

    -- the knife off the guard's belt, three throws in it. addBlade is what
    -- sets has.knife and keeps ammo.knives, which is only the total shown on
    -- the bar, in step with the blades themselves
    self:addBlade()

    return self
end

function Player.carryOver(from, spawn)
    local self = Player.new(spawn)
    if not from then
        return self
    end

    self.health = from.health
    self.armor = from.armor
    self.invertY = from.invertY
    self.invertX = from.invertX
    self.god = from.god
    self.invisible = from.invisible
    self.endlessAmmo = from.endlessAmmo
    self.sensitivity = from.sensitivity
    self.weapon = from.weapon
    self.kills = from.kills
    self.takedowns = from.takedowns
    self.silencer = from.silencer
    self.silenced = from.silenced
    for k, v in pairs(from.has) do
        self.has[k] = v
    end

    for k, v in pairs(from.ammo) do
        self.ammo[k] = v
    end

    for k, v in pairs(from.mag or {}) do
        self.mag[k] = v
    end

    -- the blades come through with the wear they have on them, and only
    -- those: the one the block started with is not handed out again
    self.blades = {}
    for i, uses in ipairs(from.blades or {}) do
        self.blades[i] = uses
    end

    self:syncBlades()

    return self
end

-- invertX is 1 for the usual thing and -1 for mice, or window managers, that
-- hand us the horizontal the other way round. invertY is 1 for pushing the
-- mouse forward to look down, -1 for the other way round, 0 for no vertical
-- look at all.
function Player:look(dx, dy)
    dy = dy or 0

    if dx > SPIKE then
        dx = SPIKE
    elseif dx < -SPIKE then
        dx = -SPIKE
    end

    if dy > SPIKE then
        dy = SPIKE
    elseif dy < -SPIKE then
        dy = -SPIKE
    end

    self.lookDelta = self.lookDelta + dx * self.sensitivity * self.invertX
    self.pitchDelta = self.pitchDelta + dy * self.sensitivity * PITCH_RATE * self.invertY

    if math.abs(dx) >= LOOK_FLOOR then
        self.lookAge = 0
    end

    if self.invertY ~= 0 and math.abs(dy) >= LOOK_FLOOR then
        self.pitchAge = 0
    end
end

-- A turn in radians, for the edge of the screen rather than for a mouse
-- movement: it follows the same direction setting but not the mouse speed.
function Player:turn(radians)
    self.lookDelta = self.lookDelta + radians * self.invertX

    if radians ~= 0 then
        self.lookAge = 0
    end
end

-- How much of the key turn gets through: none while the mouse is aiming, all
-- of it once the hand has been still for a moment.
function Player:keyTurnShare()
    if self.lookAge < MOUSE_OWN then
        return 0
    end

    if self.lookAge < MOUSE_OWN + MOUSE_FADE then
        return (self.lookAge - MOUSE_OWN) / MOUSE_FADE
    end

    return 1
end

-- Knives are counted one blade at a time: each has its own throws left, and
-- ammo.knives is only the total, for the bar to show.
function Player:syncBlades()
    local total = 0
    for _, uses in ipairs(self.blades) do
        total = total + uses
    end

    self.ammo.knives = total
end

function Player:addBlade(uses)
    if #self.blades >= BLADES then
        return false
    end

    self.blades[#self.blades + 1] = math.min(BLADE_USES, uses or BLADE_USES)
    self.has.knife = true
    self:syncBlades()

    return true
end

-- The most worn blade goes first: no sense throwing a fresh one while a
-- one throw blade is still in your belt.
function Player:takeBlade()
    local worst
    for i, uses in ipairs(self.blades) do
        if uses > 0 and (not worst or uses < self.blades[worst]) then
            worst = i
        end
    end

    if not worst then
        return nil
    end

    local left = self.blades[worst] - 1
    table.remove(self.blades, worst)
    self:syncBlades()

    return left
end

function Player:speed()
    return math.sqrt(self.vx * self.vx + self.vy * self.vy)
end

function Player:weaponDef()
    return weapons.byId[self.weapon]
end

-- What is in the gun, as against what is in your pockets. A gun that has
-- never been fired comes loaded, off the rounds you are carrying: doing it
-- here means one picked up off the floor, carried into the next block or
-- read back out of a save all arrive with a magazine in them.
function Player:magOf(w)
    if not w.clip then
        return nil
    end

    if not self.mag[w.id] then
        local spare = self.ammo[w.ammo] or 0
        local take = math.min(w.clip, spare)
        self.mag[w.id] = take
        self.ammo[w.ammo] = spare - take
    end

    return self.mag[w.id]
end

-- The magazine comes out, a full one goes in, and the gun is no use to
-- anybody in between. It makes no noise worth hearing.
function Player:reload(world)
    local w = self:weaponDef()
    if not w.clip or self.reloadT > 0 or not self.alive or self.takedown then
        return false
    end

    if self.endlessAmmo or (self:magOf(w) >= w.clip)
            or (self.ammo[w.ammo] or 0) <= 0 then
        return false
    end

    self.reloadT = w.reload or weapons.RELOAD
    self.reloadMax = self.reloadT
    world.audio.play("click", 0.45, 0.8)

    return true
end

function Player:finishReload(world)
    local w = self:weaponDef()
    self.reloadT = 0

    if not w.clip then
        return
    end

    local room = w.clip - self:magOf(w)
    local take = math.min(room, self.ammo[w.ammo] or 0)
    self.mag[w.id] = self.mag[w.id] + take
    self.ammo[w.ammo] = (self.ammo[w.ammo] or 0) - take
    world.audio.play("clink", 0.4, 0.7)
end

-- How far the gun has dropped out of sight while the magazine is changed,
-- 0 when it is up and 1 at the bottom of the swing. Down fast, a beat with
-- both hands on it, then back up.
function Player:reloadDip()
    if self.reloadT <= 0 or self.reloadMax <= 0 then
        return 0
    end

    local t = 1 - self.reloadT / self.reloadMax

    if t < 0.22 then
        return t / 0.22
    elseif t > 0.78 then
        return (1 - t) / 0.22
    end

    return 1
end

-- Which third of the reload we are in, for the weapons that have frames of
-- their own: 0 while the magazine comes out, 1 while the new one goes in, 2
-- while the gun comes back up. nil when nothing is being reloaded. It reads
-- the same clock as the dip, so the weapon's own reload time still decides
-- how long each one is on screen.
function Player:reloadStage()
    if self.reloadT <= 0 or self.reloadMax <= 0 then
        return nil
    end

    local t = 1 - self.reloadT / self.reloadMax

    return math.max(0, math.min(2, math.floor(t * 3)))
end

function Player:canHold(id)
    if not self.has[id] then
        return false
    end

    local w = weapons.byId[id]
    if w.projectile == "grenade" or w.projectile == "flash" or w.id == "knife" then
        return self.endlessAmmo or (self.ammo[w.ammo] or 0) > 0
    end

    if w.clip and not self.endlessAmmo then
        return self:magOf(w) > 0 or (self.ammo[w.ammo] or 0) > 0
    end

    return true
end

function Player:silencedNow()
    local w = self:weaponDef()

    return self.silenced and w.silencer == true
end

function Player:toggleSilencer(world)
    if not self.silencer then
        world:message("No silencer")

        return
    end

    self.silenced = not self.silenced
    world.audio.play("click", 0.4)
    world:message(self.silenced and "Silencer fitted" or "Silencer off")
end

function Player:select(slot)
    local w = weapons.list[slot]
    if not w or w.id == self.weapon then
        return
    end

    if self:canHold(w.id) then
        self.weapon = w.id
        self.reloadT = 0
        self.cooldown = math.max(self.cooldown, 0.18)
    end
end

function Player:cycle(dir)
    local slot = weapons.slotOf[self.weapon]
    for _ = 1, #weapons.list do
        slot = (slot - 1 + dir) % #weapons.list + 1
        if self:canHold(weapons.list[slot].id) then
            self:select(slot)

            return
        end
    end
end

local function tryMove(self, level, nx, ny)
    if self.noclip then
        self.x, self.y = nx, ny

        return
    end

    if not level:blocked(nx, self.y, RADIUS, self.keys) then
        self.x = nx
    else
        self.vx = 0
    end

    if not level:blocked(self.x, ny, RADIUS, self.keys) then
        self.y = ny
    else
        self.vy = 0
    end
end

function Player:update(dt, world)
    self.cooldown = math.max(0, self.cooldown - dt)

    if self.reloadT > 0 then
        self.reloadT = self.reloadT - dt

        if self.reloadT <= 0 then
            self:finishReload(world)
        end
    end

    -- so the bar can read the magazine without filling it on the way past
    self:magOf(self:weaponDef())

    self.fireT = math.max(0, self.fireT - dt)
    self.throwT = math.max(0, self.throwT - dt)
    self.muzzle = math.max(0, self.muzzle - dt * 6)
    self.hurtT = math.max(0, self.hurtT - dt)
    self.blind = math.max(0, self.blind - dt)
    self.kick = self.kick * math.max(0, 1 - dt * 9)

    if not self.alive then
        self.viewZ = math.min(40, self.viewZ + dt * 70)
        self.lookDelta = 0
        self.pitchDelta = 0
        self.pitch = self.pitch * math.max(0, 1 - dt * 2)

        return
    end

    self.pitch = math.max(-PITCH_LIMIT, math.min(PITCH_LIMIT, self.pitch + self.pitchDelta))
    self.pitchDelta = 0
    self.pitchAge = self.pitchAge + dt

    if self.takedown then
        self:advanceTakedown(dt, world)

        return
    end

    local kb = love.keyboard

    -- The mouse turns; the keyboard keeps the arrows and Q and E for it, for
    -- anyone playing without a mouse.
    local turn = 0
    if kb.isDown("left") or kb.isDown("q") then
        turn = turn - 1
    end

    if kb.isDown("right") or kb.isDown("e") then
        turn = turn + 1
    end

    -- A and D step sideways. Holding alt turns with them instead, which is
    -- the old way round and the way to spin without a mouse.
    local swap = kb.isDown("lalt") or kb.isDown("ralt")
    local side = 0

    if kb.isDown("a") then
        if swap then
            turn = turn - 1
        else
            side = side - 1
        end
    end

    if kb.isDown("d") then
        if swap then
            turn = turn + 1
        else
            side = side + 1
        end
    end

    local tilt = 0
    if kb.isDown("pageup") then
        tilt = tilt + 1
    end

    if kb.isDown("pagedown") then
        tilt = tilt - 1
    end

    if tilt ~= 0 then
        self.pitch = math.max(-PITCH_LIMIT,
            math.min(PITCH_LIMIT, self.pitch + tilt * dt * 0.6))
        self.pitchAge = 0
    elseif kb.isDown("home") then
        self.pitch = 0
    elseif self.pitchAge > PITCH_HOLD then
        self.pitch = self.pitch * math.max(0, 1 - dt * PITCH_HOME)
    end

    local running = kb.isDown("lshift") or kb.isDown("rshift")
    local turnRate = TURN * (running and 1.35 or 1) * self:keyTurnShare()
    self.angle = (self.angle + turn * turnRate * dt + self.lookDelta) % (math.pi * 2)
    self.lookDelta = 0
    self.lookAge = self.lookAge + dt

    local fwd = 0
    if kb.isDown("w") or kb.isDown("up") then
        fwd = fwd + 1
    end

    if kb.isDown("s") or kb.isDown("down") then
        fwd = fwd - 1
    end

    local top = running and RUN or WALK
    local dirx, diry = math.cos(self.angle), math.sin(self.angle)
    local tx = (dirx * fwd - diry * side) * top
    local ty = (diry * fwd + dirx * side) * top
    local len = math.sqrt(tx * tx + ty * ty)
    if len > top then
        tx, ty = tx / len * top, ty / len * top
    end

    local blend = math.min(1, dt * 11)
    self.vx = self.vx + (tx - self.vx) * blend
    self.vy = self.vy + (ty - self.vy) * blend

    tryMove(self, world.level, self.x + self.vx * dt, self.y + self.vy * dt)

    local speed = self:speed()
    self.bobT = self.bobT + dt * (5 + speed * 2.2)
    self.viewZ = math.sin(self.bobT) * math.min(speed, RUN) * 0.45 + self.kick

    local wantFire = love.mouse.isDown(1) or kb.isDown("lctrl") or kb.isDown("rctrl")
    local def = self:weaponDef()
    local victim = world:takedownTarget()

    if wantFire and not self.fireHeld and victim and self:canTakedown() then
        self:beginTakedown(victim, world)
        self.fireHeld = true

        return
    end

    if wantFire and (def.auto or not self.fireHeld) then
        self:fire(world)
    end

    self.fireHeld = wantFire

    if self.pending and self.cooldown <= 0 then
        self.weapon = self.pending
        self.pending = nil
    end
end

function Player:fire(world)
    if self.cooldown > 0 or self.reloadT > 0 or not self.alive then
        return
    end

    local w = self:weaponDef()
    local bladeLeft
    if w.id == "knife" then
        if self.endlessAmmo then
            bladeLeft = BLADE_USES - 1
        else
            bladeLeft = self:takeBlade()
            if not bladeLeft then
                self.cooldown = 0.35
                world.audio.play("dry", 0.4)
                world:message("No knife left")

                return
            end
        end
    elseif w.clip and not self.endlessAmmo then
        if self:magOf(w) <= 0 then
            -- an empty gun loads itself rather than clicking at the man in
            -- front of you, which is what the hand would do anyway
            if not self:reload(world) then
                self.cooldown = 0.35
                world.audio.play("dry", 0.4)
                world:message("No ammunition")
            end

            return
        end

        self.mag[w.id] = self.mag[w.id] - 1
    elseif w.ammo and not self.endlessAmmo then
        local left = self.ammo[w.ammo] or 0
        if left <= 0 then
            self.cooldown = 0.35
            world.audio.play("dry", 0.4)
            world:message("No ammunition")

            return
        end

        self.ammo[w.ammo] = left - 1
    end

    local quiet = self:silencedNow()
    self.cooldown = w.rate
    self.fireT = 0.1
    self.kick = self.kick + w.kick * (quiet and 0.75 or 1)
    world.audio.play(quiet and w.quietSound or w.sound, quiet and 0.4 or 0.55)

    if w.melee then
        world:melee(self, self.angle, w)
    elseif w.projectile then
        world:throw(w.projectile, self, self.angle, nil, bladeLeft)
        self.throwT = 0.3
        self.throwView = w.view
        if not self:canHold(w.id) then
            self.pending = "revolver"
        end
    else
        self.muzzle = quiet and 0.12 or 0.55
        local spread = w.spread * (1 + self:speed() * 0.22)
        local a = self.angle + (love.math.random() - 0.5) * spread * 2
        world:hitscan(self.x, self.y, a, w.range, weapons.roll(w), self, quiet)
    end

    -- the shot carries after the round has landed, not before it. The other
    -- way round the man in front of the barrel heard the bang in time to
    -- turn, which took the surprise off every silenced round ever fired.
    world:noise(self.x, self.y, quiet and w.quietNoise or w.noise, nil)
end

function Player:quickThrow(kind, world)
    if self.cooldown > 0 or not self.alive then
        return
    end

    local w = weapons.byId[kind]
    if not self.has[kind] or (self.ammo[w.ammo] or 0) <= 0 then
        world:message("Nothing to throw")

        return
    end

    local blade
    if kind == "knife" then
        blade = self.endlessAmmo and BLADE_USES - 1 or self:takeBlade()
        if not blade then
            world:message("Nothing to throw")

            return
        end
    else
        self.ammo[w.ammo] = self.ammo[w.ammo] - 1
    end

    self.cooldown = w.rate
    self.kick = self.kick + w.kick
    self.throwT = 0.3
    self.throwView = w.view
    world.audio.play(w.sound, 0.5)
    world:noise(self.x, self.y, w.noise, nil)
    world:throw(w.projectile, self, self.angle, nil, blade)
end

function Player:use(world)
    local level = world.level
    local dirx, diry = math.cos(self.angle), math.sin(self.angle)

    local man = world.prisonerAhead and world:prisonerAhead()
    if man and world:freePrisoner(man) then
        return
    end

    for reach = 0.3, 1.3, 0.25 do
        local cx = math.floor(self.x + dirx * reach) + 1
        local cy = math.floor(self.y + diry * reach) + 1

        if level:isExit(cx, cy) then
            world:reachExit()

            return
        end

        local box = level:lockerAt(cx, cy)
        if box then
            if box.opened then
                world:message("Already been through this one")
            else
                world:openLocker(box)
            end

            return
        end

        local panel = level:secretAt(cx, cy)
        if panel and not panel.opened then
            world:openSecret(panel)

            return
        end

        local door = level:doorAt(cx, cy)
        if door then
            -- the lock first, and whatever the slab is doing: a door a guard
            -- is holding open is still locked, and saying so is better than
            -- "nothing to use here"
            if door.lock and not self.keys[door.lock] then
                world:message(door.lock:upper() .. " key needed")
                world.audio.play("locked", 0.5)

                return
            end

            if door.state ~= "open" then
                level:openDoor(door)
                world.audio.play("door", 0.5)
                world:noise(cx - 0.5, cy - 0.5, 6, nil)

                return
            end
        end
    end

    world:message("Nothing to use here")
end

-- Executions. With the hatchet in hand it is the throat or the back of the
-- head, bare handed it is the neck. All three are silent and always lethal,
-- which is the only way the first corridors are survivable.
function Player:canTakedown()
    return self.alive and not self.takedown and self.cooldown <= 0
end

function Player:beginTakedown(victim, world)
    local kind
    if self.weapon == "hatchet" then
        kind = love.math.random() < 0.5 and "throat" or "head"
    else
        kind = "neck"
    end

    self.takedown = {
        kind = kind,
        victim = victim,
        t = 0,
        dur = kind == "neck" and 1.05 or 0.95,
        done = false,
    }
    self.vx, self.vy = 0, 0
    self.cooldown = self.takedown.dur + 0.15
    victim:grab()
    world.audio.play("grab", 0.45)
end

function Player:advanceTakedown(dt, world)
    local td = self.takedown
    local v = td.victim
    td.t = td.t + dt

    local a = math.atan2(v.y - self.y, v.x - self.x)
    local off = math.atan2(math.sin(a - self.angle), math.cos(a - self.angle))
    self.angle = self.angle + off * math.min(1, dt * 14)

    local dx, dy = v.x - self.x, v.y - self.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > 0.62 then
        local step = math.min(d - 0.62, dt * 1.6)
        self.x = self.x + dx / d * step
        self.y = self.y + dy / d * step
    end

    self.viewZ = math.sin(td.t * 11) * 2.2
    self.bobT = self.bobT + dt * 3

    if not td.done and td.t >= td.dur * 0.55 then
        td.done = true
        self.takedowns = self.takedowns + 1
        v:execute(world)
        world:spawnFx("fx.blood", v.x, v.y, 0.5, 0.5)
    end

    if td.t >= td.dur then
        self.takedown = nil
    end
end

function Player:takedownFrame()
    local td = self.takedown
    if not td then
        return nil, 1
    end

    local step = math.min(4, math.floor(td.t / td.dur * 4) + 1)

    return td.kind, step
end

function Player:hurt(amount, world, srcX, srcY)
    if not self.alive or self.god then
        return
    end

    if self.armor > 0 then
        local soak = math.min(self.armor, amount * 0.55)
        self.armor = self.armor - soak
        amount = amount - soak
    end

    self.health = self.health - amount
    self.hurtT = math.min(0.6, self.hurtT + 0.3 + amount * 0.01)

    if srcX then
        local a = math.atan2(srcY - self.y, srcX - self.x) - self.angle
        self.hurtDir = math.atan2(math.sin(a), math.cos(a))
    end

    world.audio.play("ouch", 0.45)

    if self.health <= 0 then
        self.health = 0
        self.alive = false
        world:playerDied()
    end
end

local GIVE = {}

GIVE.trap = function(self)
    if (self.ammo.traps or 0) >= MAX.traps then
        return false
    end

    self.ammo.traps = (self.ammo.traps or 0) + 1

    return true, "Leg trap"
end

GIVE.knife = function(self, uses)
    local fresh = not self.has.knife
    if not self:addBlade(uses) then
        return false
    end

    return true, fresh and "Throwing knife!" or "Knife back", "knife"
end

GIVE.uzi = function(self)
    local fresh = not self.has.uzi
    self.has.uzi = true
    self.ammo.clips = math.min(MAX.clips, self.ammo.clips + 50)

    return true, fresh and "Uzi!" or "Uzi ammunition"
end

GIVE.clips = function(self)
    if self.ammo.clips >= MAX.clips then
        return false
    end

    self.ammo.clips = math.min(MAX.clips, self.ammo.clips + 50)

    return true, "9mm, two magazines"
end

GIVE.launcher = function(self)
    local fresh = not self.has.launcher
    self.has.launcher = true
    self.ammo.rockets = math.min(MAX.rockets, self.ammo.rockets + 2)

    return true, fresh and "Rocket launcher!" or "Rockets"
end

GIVE.grenades = function(self)
    if self.ammo.grenades >= MAX.grenades then
        return false
    end

    self.has.grenades = true
    self.ammo.grenades = math.min(MAX.grenades, self.ammo.grenades + 2)

    return true, "Grenades"
end

GIVE.flashes = function(self)
    if self.ammo.flashes >= MAX.flashes then
        return false
    end

    self.has.flashes = true
    self.ammo.flashes = math.min(MAX.flashes, self.ammo.flashes + 2)

    return true, "Flash grenades"
end

GIVE.bullets = function(self)
    if self.ammo.bullets >= MAX.bullets then
        return false
    end

    self.ammo.bullets = math.min(MAX.bullets, self.ammo.bullets + 12)

    return true, "Revolver rounds"
end

-- The box off the armoury shelf has both calibres in it, which is the only
-- thing that fills the revolver and the uzi in one go.
GIVE.ammobox = function(self)
    if self.ammo.bullets >= MAX.bullets and self.ammo.clips >= MAX.clips then
        return false
    end

    self.ammo.bullets = math.min(MAX.bullets, self.ammo.bullets + 24)
    self.ammo.clips = math.min(MAX.clips, self.ammo.clips + 50)

    return true, "Box of ammunition"
end

GIVE.rockets = function(self)
    if self.ammo.rockets >= MAX.rockets then
        return false
    end

    self.ammo.rockets = math.min(MAX.rockets, self.ammo.rockets + 2)

    return true, "Rockets"
end

GIVE.vest = function(self)
    if self.armor >= self.armorMax then
        return false
    end

    self.armor = math.min(self.armorMax, self.armor + 25)

    return true, "Vest patched up"
end

GIVE.vestheavy = function(self)
    if self.armor >= self.armorMax then
        return false
    end

    self.armor = math.min(self.armorMax, self.armor + 50)

    return true, "Riot vest"
end

GIVE.medkit = function(self)
    if self.health >= 100 then
        return false
    end

    self.health = math.min(100, self.health + 25)

    return true, "First aid"
end

GIVE.snack = function(self)
    if self.health >= 100 then
        return false
    end

    self.health = math.min(100, self.health + 10)

    return true, "Cold food"
end

GIVE.silencer = function(self)
    if self.silencer then
        return false
    end

    self.silencer = true
    self.silenced = true

    return true, "Silencer"
end

local KEYS = {redkey = "red", bluekey = "blue", yellowkey = "yellow"}

function Player:give(item, uses)
    local key = KEYS[item]
    if key then
        if self.keys[key] then
            return false
        end

        self.keys[key] = true

        return true, key:upper() .. " key", "key"
    end

    local fn = GIVE[item]
    if not fn then
        return false
    end

    local ok, text = fn(self, uses)

    return ok, text, item
end

return Player
