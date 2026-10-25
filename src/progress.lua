-- How far the escape has got. Kept in the save directory so a block stays
-- locked until the one before it has been finished.

local progress = {}

local FILE = "progress.txt"

-- invertY -1 is looking up and down the usual way round, 1 is inverted and 0
-- is off. The sight only ever moves when you ask it to, so on is the default.
local DEFAULTS = {unlocked = 1, difficulty = 2, invertY = -1, invertX = 1,
    sens = 3, pointerMode = 0, version = 3}

-- Settings written by an older build are read, but anything this version
-- changed the default of is taken back to the new one, once.
local RESET_BELOW = {invertY = 3}

function progress.load()
    local data = {}
    for k, v in pairs(DEFAULTS) do
        data[k] = v
    end

    if not (love.filesystem.getInfo and love.filesystem.getInfo(FILE)) then
        return data
    end

    local text = love.filesystem.read(FILE)
    if not text then
        return data
    end

    -- a file written before this key existed counts as version zero
    local was = tonumber(text:match("version%s*=%s*(%d+)")) or 0

    for k in pairs(DEFAULTS) do
        local n = tonumber(text:match(k .. "%s*=%s*(%-?%d+)"))
        if n then
            data[k] = n
        end
    end

    data.unlocked = math.max(1, data.unlocked)
    data.version = was

    for key, need in pairs(RESET_BELOW) do
        if was < need then
            data[key] = DEFAULTS[key]
        end
    end

    if was < DEFAULTS.version then
        data.version = DEFAULTS.version
        progress.save(data)
    end

    return data
end

function progress.save(data)
    love.filesystem.write(FILE, string.format(
        "unlocked = %d\ndifficulty = %d\ninvertY = %d\ninvertX = %d\nsens = %d\n"
        .. "pointerMode = %d\nversion = %d\n",
        data.unlocked, data.difficulty or 2, data.invertY or 0, data.invertX or 1,
        data.sens or 3, data.pointerMode or 0, data.version or DEFAULTS.version))
end

-- Finishing block n opens block n + 1 and nothing further.
function progress.finished(data, n, total)
    local reached = math.min(total, n + 1)
    if reached > data.unlocked then
        data.unlocked = reached
        progress.save(data)

        return true
    end

    return false
end

return progress
