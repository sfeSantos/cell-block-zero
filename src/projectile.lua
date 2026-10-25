-- Rockets fly straight and blow up on the first thing they touch. Grenades are
-- thrown on an arc, bounce off walls and the floor, and go off on a fuse, so
-- they can be rolled round a corner. The flash grenade is a grenade that
-- blinds instead of killing.

local Projectile = {}
Projectile.__index = Projectile

Projectile.KINDS = {
    -- A blade goes through one man and drops where he falls. It makes about
    -- as much noise as the body does.
    knife = {
        sprite = "fx.knife",
        speed = 13,
        radius = 0.1,
        size = 0.3,
        z = 0.52,
        damage = 45,
        blade = true,
        gravity = 2.2,
        noise = 2.5,
        sound = "throw",
    },
    rocket = {
        sprite = "fx.rocket",
        speed = 9.5,
        radius = 0.11,
        size = 0.45,
        z = 0.46,
        blast = 2.7,
        damage = 90,
        glow = true,
        trail = "fx.smoke",
        sound = "rocket",
    },
    grenade = {
        sprite = "fx.grenade",
        speed = 7.2,
        radius = 0.09,
        size = 0.3,
        z = 0.55,
        blast = 2.5,
        damage = 72,
        fuse = 1.6,
        lift = 2.4,
        gravity = 7.5,
        bounce = 0.42,
    },
    flash = {
        sprite = "fx.flash",
        speed = 7.0,
        radius = 0.09,
        size = 0.3,
        z = 0.55,
        blast = 6.5,
        damage = 0,
        blind = 4.5,
        fuse = 1.3,
        lift = 2.4,
        gravity = 7.5,
        bounce = 0.42,
    },
}

function Projectile.new(kind, x, y, angle, owner, reach, uses)
    local k = Projectile.KINDS[kind]
    local self = setmetatable({}, Projectile)

    self.uses = uses

    local speed = k.speed
    if k.fuse and reach then
        speed = math.max(3.5, math.min(k.speed, reach * 1.35))
    end

    self.kind = kind
    self.k = k
    self.x, self.y = x, y
    self.z = k.z
    self.vx = math.cos(angle) * speed
    self.vy = math.sin(angle) * speed
    self.vz = k.lift or 0
    self.owner = owner
    self.fuse = k.fuse
    self.life = 8
    self.dead = false
    self.trailT = 0

    return self
end

function Projectile:hitSomething(world)
    for _, e in ipairs(world.enemies) do
        if e.alive and e ~= self.owner then
            local dx, dy = e.x - self.x, e.y - self.y
            if dx * dx + dy * dy < (e.radius + self.k.radius) ^ 2 then
                return e
            end
        end
    end

    local p = world.player
    if p.alive and self.owner ~= p then
        local dx, dy = p.x - self.x, p.y - self.y
        if dx * dx + dy * dy < 0.18 then
            return p
        end
    end

    return nil
end

-- A thrown blade: one body, quietly, and then it is on the floor waiting to
-- be picked up again. The last throw in it snaps the blade instead.
function Projectile:land(world, victim)
    self.dead = true

    if victim then
        local damage = self.k.damage
        if victim.unaware and (victim:unaware() or victim:behind(self.x, self.y)) then
            -- in the back it kills a guard or a sergeant outright and leaves
            -- a riot captain on his last legs
            damage = damage * 1.7
        end

        world:spawnFx("fx.blood", victim.x, victim.y, 0.45, 0.3)
        world.audio.play("flesh", 0.35)
        victim:hurt(damage, world, self.x, self.y)
        world:noise(self.x, self.y, self.k.noise, self.owner)
    else
        world.audio.play("clink", 0.35)
    end

    if (self.uses or 0) > 0 then
        world:spawnItem("knife", self.x, self.y, self.uses)
    else
        world:message("The blade snapped")
    end
end

function Projectile:burst(world)
    if self.dead then
        return
    end

    if self.k.blade then
        return self:land(world, nil)
    end

    self.dead = true

    if self.k.blind then
        world:flashbang(self.x, self.y, self.k.blast, self.k.blind, self.owner)
    else
        world:explode(self.x, self.y, self.k.blast, self.k.damage, self.owner)
    end
end

function Projectile:update(dt, world)
    local k = self.k
    local level = world.level
    self.life = self.life - dt

    if self.fuse then
        self.fuse = self.fuse - dt
        if self.fuse <= 0 then
            self:burst(world)

            return
        end
    end

    if k.gravity then
        self.vz = self.vz - k.gravity * dt
    end

    local steps = math.max(1, math.ceil(math.sqrt(self.vx * self.vx + self.vy * self.vy) * dt / 0.12))
    local sub = dt / steps

    for _ = 1, steps do
        local nx = self.x + self.vx * sub
        local ny = self.y + self.vy * sub

        if level:blocked(nx, self.y, k.radius) then
            if k.bounce then
                self.vx = -self.vx * k.bounce
                world.audio.play("clink", 0.3)
            else
                self:burst(world)

                return
            end
        else
            self.x = nx
        end

        if level:blocked(self.x, ny, k.radius) then
            if k.bounce then
                self.vy = -self.vy * k.bounce
                world.audio.play("clink", 0.3)
            else
                self:burst(world)

                return
            end
        else
            self.y = ny
        end

        local hit = self:hitSomething(world)
        if hit then
            if k.blade then
                self.x, self.y = hit.x, hit.y
                self:land(world, hit)

                return
            elseif k.bounce then
                self.vx, self.vy = -self.vx * 0.3, -self.vy * 0.3
            else
                self:burst(world)

                return
            end
        end
    end

    self.z = self.z + self.vz * dt
    if k.blade and self.z <= 0.1 then
        self:land(world, nil)

        return
    end

    if self.z < 0.08 then
        self.z = 0.08
        self.vz = -self.vz * (k.bounce or 0)
        self.vx, self.vy = self.vx * 0.72, self.vy * 0.72
        if k.bounce and math.abs(self.vz) < 0.4 then
            self.vz = 0
        end
    elseif self.z > 0.95 then
        self.z = 0.95
        self.vz = math.min(0, self.vz)
    end

    if k.trail then
        self.trailT = self.trailT - dt
        if self.trailT <= 0 then
            self.trailT = 0.03
            world.fx:spawn{
                name = k.trail,
                x = self.x,
                y = self.y,
                z = self.z,
                size = 0.14,
                grow = 0.5,
                life = 0.4,
                drag = 2,
            }
        end
    end

    if self.life <= 0 then
        self:burst(world)
    end
end

function Projectile:sprite()
    return {
        name = self.k.sprite,
        x = self.x,
        y = self.y,
        z = self.z,
        size = self.k.size,
        glow = self.k.glow,
    }
end

return Projectile
