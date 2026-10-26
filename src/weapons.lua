-- What the player can carry. "noise" is how far the shot carries in tiles,
-- which is the only thing that makes the hatchet worth holding: it wakes
-- nobody up.

local weapons = {}

weapons.list = {
    {
        id = "hatchet",
        name = "Hatchet",
        view = "hatchet",
        sound = "chop",
        rate = 0.44,
        damage = {22, 34},
        melee = 1.5,
        arc = 0.7,
        noise = 2.5,
        kick = 3,
    },
    {
        id = "revolver",
        name = "Revolver",
        view = "revolver",
        sound = "pistol",
        ammo = "bullets",
        clip = 6,
        reload = 1.15,
        rate = 0.50,
        damage = {17, 27},
        spread = 0.012,
        range = 28,
        noise = 8,
        kick = 7,
        silencer = true,
        quietSound = "pistolq",
        quietNoise = 4,
    },
    {
        id = "uzi",
        name = "Uzi",
        view = "uzi",
        sound = "uzi",
        ammo = "clips",
        clip = 25,
        reload = 1.55,
        rate = 0.085,
        auto = true,
        damage = {6, 11},
        spread = 0.055,
        range = 22,
        noise = 7,
        kick = 2,
        silencer = true,
        quietSound = "uziq",
        quietNoise = 5,
    },
    {
        id = "launcher",
        name = "Rocket launcher",
        view = "launcher",
        sound = "launch",
        ammo = "rockets",
        clip = 1,
        reload = 1.70,
        rate = 1.15,
        projectile = "rocket",
        noise = 12,
        kick = 13,
    },
    {
        id = "grenades",
        name = "Grenade",
        view = "grenades",
        sound = "throw",
        ammo = "grenades",
        rate = 0.80,
        projectile = "grenade",
        noise = 4,
        kick = 4,
    },
    {
        id = "flashes",
        name = "Flash grenade",
        view = "flashes",
        sound = "throw",
        ammo = "flashes",
        rate = 0.80,
        projectile = "flash",
        noise = 4,
        kick = 4,
    },
    {
        id = "knife",
        name = "Throwing knife",
        view = "knife",
        sound = "throw",
        ammo = "knives",
        rate = 0.55,
        projectile = "knife",
        noise = 2,
        kick = 3,
        quiet = true,
    },
}

weapons.byId = {}
weapons.slotOf = {}

for i, w in ipairs(weapons.list) do
    w.slot = i
    weapons.byId[w.id] = w
    weapons.slotOf[w.id] = i
end

-- A can on the barrel costs the noise and nothing else. What it buys is the
-- shot nobody is expecting: a quiet round into a man who has not seen you
-- puts him down where he stands, whatever his rank and whatever he is
-- wearing, and he goes down without the shout that brings the rest of the
-- wing. Once he has turned round it is an ordinary round again, so the can
-- is worth carrying exactly as long as nobody knows you are there. The rule
-- itself lives in World:hitscan, where it can see who was hit.

-- How long a gun is out of the fight while the magazine is changed, for one
-- that does not say otherwise.
weapons.RELOAD = 1.2

function weapons.roll(w)
    local lo, hi = w.damage[1], w.damage[2]

    return lo + love.math.random() * (hi - lo)
end

return weapons
