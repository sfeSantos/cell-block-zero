-- All sound is synthesised at load time, the game ships no audio files.

local audio = {}

local RATE = 22050
local sounds = {}
local ok = true

local function make(dur, fn)
    local n = math.max(1, math.floor(dur * RATE))
    local data = love.sound.newSoundData(n, RATE, 16, 1)
    for i = 0, n - 1 do
        local s = fn(i / RATE, i)
        if s > 1 then
            s = 1
        elseif s < -1 then
            s = -1
        end

        data:setSample(i, s)
    end

    return love.audio.newSource(data, "static")
end

local function noise()
    return love.math.random() * 2 - 1
end

local function sine(t, f)
    return math.sin(t * 2 * math.pi * f)
end

-- A one pole filter, kept in a closure so a muffled sound can be written as
-- plainly as a bright one.
local function lowpass(cut)
    local last = 0

    return function(v)
        last = last + (v - last) * cut

        return last
    end
end

function audio.load()
    ok = pcall(function()
        local lp

        sounds.pistol = make(0.26, function(t)
            local env = math.exp(-t * 26)

            return (noise() * 0.8 + sine(t, 140) * 0.7) * env
        end)

        lp = lowpass(0.12)
        sounds.pistolq = make(0.16, function(t)
            local env = math.exp(-t * 40)

            return (lp(noise()) * 1.6 + sine(t, 95) * 0.3) * env * 0.7
        end)

        sounds.uzi = make(0.16, function(t)
            local env = math.exp(-t * 44)

            return (noise() * 0.75 + sine(t, 210) * 0.5) * env
        end)

        lp = lowpass(0.17)
        sounds.uziq = make(0.11, function(t)
            local env = math.exp(-t * 55)

            return (lp(noise()) * 1.5 + sine(t, 150) * 0.2) * env * 0.65
        end)

        sounds.shotgun = make(0.42, function(t)
            local env = math.exp(-t * 15)

            return (noise() * 0.9 + sine(t, 78) * 0.8) * env
        end)

        sounds.swish = make(0.22, function(t)
            local env = math.sin(math.min(1, t / 0.22) * math.pi)

            return noise() * env * 0.3
        end)

        sounds.chop = make(0.3, function(t)
            local env = math.exp(-t * 18)
            local air = math.sin(math.min(1, t / 0.3) * math.pi)

            return noise() * air * 0.3 + (noise() * 0.4 + sine(t, 120) * 0.6) * env * 0.7
        end)

        sounds.flesh = make(0.22, function(t)
            local env = math.exp(-t * 30)

            return (noise() * 0.5 + sine(t, 85) * 0.7) * env
        end)

        lp = lowpass(0.3)
        sounds.cut = make(0.5, function(t)
            local env = math.exp(-t * 9)

            return (lp(noise()) * 1.2 + sine(t, 60 - t * 40) * 0.4) * env * 0.8
        end)

        sounds.grab = make(0.3, function(t)
            local env = math.sin(math.min(1, t / 0.3) * math.pi)

            return noise() * env * 0.35
        end)

        sounds.grunt = make(0.3, function(t)
            local env = math.exp(-t * 11)

            return (sine(t, 150 - t * 90) * 0.8 + noise() * 0.3) * env
        end)

        sounds.ouch = make(0.34, function(t)
            local env = math.exp(-t * 9)

            return (sine(t, 240 - t * 150) * 0.7 + noise() * 0.4) * env
        end)

        sounds.death = make(0.9, function(t)
            local env = math.exp(-t * 3.4)
            local f = 220 - t * 170

            return (sine(t, f) * 0.6 + sine(t, f * 1.5) * 0.2 + noise() * 0.35) * env
        end)

        sounds.dead = make(1.6, function(t)
            local env = math.exp(-t * 1.9)
            local f = 180 - t * 90

            return (sine(t, f) * 0.5 + sine(t, f * 0.5) * 0.4) * env
        end)

        sounds.boom = make(1.3, function(t)
            local env = math.exp(-t * 4.2)
            local rumble = math.exp(-t * 1.6)

            return (noise() * 0.8 * env + sine(t, 55 - t * 20) * 0.9 * rumble) * 0.9
        end)

        sounds.flashbang = make(1.0, function(t)
            local env = math.exp(-t * 7)
            local ring = math.exp(-t * 1.4)

            return noise() * env * 0.9 + sine(t, 2400) * ring * 0.25
        end)

        sounds.rocket = make(0.5, function(t)
            local env = math.exp(-t * 5)

            return (noise() * 0.7 + sine(t, 90 + t * 120) * 0.5) * env
        end)

        sounds.launch = make(0.45, function(t)
            local env = math.exp(-t * 9)

            return (noise() * 0.85 + sine(t, 70) * 0.8) * env
        end)

        sounds.throw = make(0.2, function(t)
            local env = math.sin(math.min(1, t / 0.2) * math.pi)

            return noise() * env * 0.25
        end)

        sounds.clink = make(0.26, function(t)
            local env = math.exp(-t * 22)

            return (sine(t, 1850) * 0.5 + sine(t, 2770) * 0.3 + noise() * 0.2) * env
        end)

        sounds.ping = make(0.3, function(t)
            local env = math.exp(-t * 17)
            local f = 2600 - t * 2600

            return (sine(t, f) * 0.5 + noise() * 0.3) * env
        end)

        sounds.whiz = make(0.18, function(t)
            local env = math.sin(math.min(1, t / 0.18) * math.pi)

            return (noise() * 0.4 + sine(t, 1400 - t * 3000) * 0.4) * env
        end)

        lp = lowpass(0.05)
        sounds.door = make(0.9, function(t)
            local env = math.min(1, t * 8) * math.exp(-t * 2.2)

            return (lp(noise()) * 3.0 + sine(t, 48) * 0.3) * env * 0.7
        end)

        sounds.locked = make(0.3, function(t)
            local env = math.exp(-t * 20) + math.exp(-math.abs(t - 0.12) * 60)

            return (noise() * 0.4 + sine(t, 110) * 0.6) * env * 0.8
        end)

        sounds.dry = make(0.1, function(t)
            local env = math.exp(-t * 70)

            return (noise() * 0.5 + sine(t, 900) * 0.4) * env
        end)

        sounds.click = make(0.09, function(t)
            local env = math.exp(-t * 80)

            return (noise() * 0.3 + sine(t, 1500) * 0.5) * env
        end)

        sounds.pickup = make(0.26, function(t)
            local env = math.exp(-t * 9)
            local f = 540 + t * 900

            return (sine(t, f) * 0.5 + sine(t, f * 2) * 0.15) * env
        end)

        sounds.key = make(0.5, function(t)
            local env = math.exp(-t * 5.5)
            local f = t < 0.12 and 880 or 1320

            return (sine(t, f) * 0.45 + sine(t, f * 2.01) * 0.12) * env
        end)

        sounds.exit = make(0.9, function(t)
            local env = math.exp(-t * 2.6)
            local step = math.floor(t / 0.16)
            local f = 440 * (1 + step * 0.26)

            return (sine(t, f) * 0.4 + sine(t, f * 2) * 0.12) * env
        end)

        sounds.klaxon = make(1.6, function(t)
            local env = math.min(1, t * 6) * math.exp(-t * 0.9)
            local sweep = 420 + 260 * math.sin(t * 2 * math.pi * 1.6)

            return (sine(t, sweep) * 0.45 + sine(t, sweep * 0.5) * 0.3) * env
        end)

        local function shout(base, dur)
            return make(dur, function(t)
                local env = math.min(1, t * 22) * math.exp(-t * 5)
                local vib = 1 + 0.06 * math.sin(t * 2 * math.pi * 11)
                local f = base * vib

                return (sine(t, f) * 0.4 + sine(t, f * 2) * 0.2
                    + sine(t, f * 3) * 0.12 + noise() * 0.12) * env
            end)
        end

        sounds.shout1 = shout(190, 0.45)
        sounds.shout2 = shout(150, 0.55)
        sounds.shout3 = shout(115, 0.7)

        -- two of them, one on top of the other, is enough to sound like a dog
        sounds.bark = make(0.3, function(t)
            local hit = t % 0.16
            local env = math.min(1, hit * 60) * math.exp(-hit * 26)
            local f = 160 * (1 - hit * 1.2)

            return (sine(t, f) * 0.45 + sine(t, f * 1.5) * 0.2
                + noise() * 0.3) * env
        end)
    end)

    if not ok then
        print("audio: synthesis failed, running silent")
    end
end

function audio.play(name, volume, pitch)
    if not ok or not sounds[name] then
        return
    end

    local s = sounds[name]:clone()
    s:setVolume(volume or 0.6)
    s:setPitch(pitch or (0.94 + love.math.random() * 0.12))
    s:play()
end

return audio
