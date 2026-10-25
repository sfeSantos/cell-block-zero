-- Short lived billboards: blood, sparks, smoke, the fireball of an explosion.
-- They are plain tables so the renderer can treat them like any other sprite.

local fx = {}
fx.__index = fx

local BOOM = {"fx.boom1", "fx.boom2", "fx.boom3", "fx.boom4"}

function fx.new()
    return setmetatable({list = {}}, fx)
end

function fx:spawn(p)
    p.life = p.life or 0.4
    p.max = p.life
    p.x = p.x or 0
    p.y = p.y or 0
    p.z = p.z or 0.4
    p.vx = p.vx or 0
    p.vy = p.vy or 0
    p.vz = p.vz or 0
    p.size = p.size or 0.2
    p.grow = p.grow or 0
    p.drag = p.drag or 3
    self.list[#self.list + 1] = p

    return p
end

function fx:blood(x, y, z, amount)
    for _ = 1, amount or 4 do
        local a = love.math.random() * math.pi * 2
        local s = love.math.random() * 1.6
        self:spawn{
            name = "fx.blood",
            x = x,
            y = y,
            z = z or 0.45,
            vx = math.cos(a) * s,
            vy = math.sin(a) * s,
            vz = 0.8 + love.math.random(),
            size = 0.1 + love.math.random() * 0.1,
            life = 0.45,
            gravity = 4,
        }
    end
end

function fx:sparks(x, y, z, amount)
    for _ = 1, amount or 5 do
        local a = love.math.random() * math.pi * 2
        local s = 1 + love.math.random() * 2.5
        self:spawn{
            name = "fx.spark",
            x = x,
            y = y,
            z = z or 0.5,
            vx = math.cos(a) * s,
            vy = math.sin(a) * s,
            vz = 1 + love.math.random() * 2,
            size = 0.05 + love.math.random() * 0.07,
            life = 0.3,
            glow = true,
            gravity = 5,
        }
    end
end

function fx:boom(x, y, radius)
    self:spawn{
        name = BOOM[1],
        frames = BOOM,
        x = x,
        y = y,
        z = 0.1,
        size = radius * 0.9,
        grow = radius * 0.7,
        life = 0.45,
        glow = true,
    }

    for i = 1, 7 do
        local a = love.math.random() * math.pi * 2
        local s = radius * (0.6 + love.math.random())
        self:spawn{
            name = "fx.smoke",
            x = x + math.cos(a) * 0.2,
            y = y + math.sin(a) * 0.2,
            z = 0.2 + love.math.random() * 0.5,
            vx = math.cos(a) * s * 0.4,
            vy = math.sin(a) * s * 0.4,
            vz = 0.4,
            size = 0.3 + love.math.random() * 0.4,
            grow = 0.9,
            life = 0.7 + love.math.random() * 0.4,
            drag = 1.6,
        }
    end

    self:sparks(x, y, 0.4, 10)
end

function fx:pop(x, y)
    self:spawn{
        name = "fx.pop",
        x = x,
        y = y,
        z = 0.15,
        size = 0.8,
        grow = 3.2,
        life = 0.3,
        glow = true,
    }
end

function fx:update(dt, level)
    local list = self.list
    local n = #list

    for i = n, 1, -1 do
        local p = list[i]
        p.life = p.life - dt
        if p.life <= 0 then
            list[i] = list[n]
            list[n] = nil
            n = n - 1
        else
            local drag = math.max(0, 1 - dt * p.drag)
            p.vx = p.vx * drag
            p.vy = p.vy * drag

            if p.gravity then
                p.vz = p.vz - p.gravity * dt
            end

            local nx, ny = p.x + p.vx * dt, p.y + p.vy * dt
            if level and level:blocked(nx, ny, 0.04) then
                p.vx, p.vy = p.vx * -0.3, p.vy * -0.3
            else
                p.x, p.y = nx, ny
            end

            p.z = p.z + p.vz * dt
            if p.z < 0.03 then
                p.z = 0.03
                p.vz = 0
                p.vx, p.vy = p.vx * 0.5, p.vy * 0.5
            end

            if p.frames then
                local t = 1 - p.life / p.max
                local i2 = math.min(#p.frames, math.floor(t * #p.frames) + 1)
                p.name = p.frames[i2]
            end
        end
    end
end

function fx:collect(out)
    for _, p in ipairs(self.list) do
        local t = p.life / p.max
        out[#out + 1] = {
            name = p.name,
            x = p.x,
            y = p.y,
            z = p.z,
            size = p.size + p.grow * (1 - t),
            alpha = math.min(1, t * 2.2),
            glow = p.glow,
        }
    end
end

function fx:clear()
    self.list = {}
end

return fx
