-- Navigation help for the guards: one breadth first distance field towards the
-- player, shared by everyone, plus a cover query that uses it. Rebuilding the
-- field is cheap enough to do a few times a second, and because it covers the
-- whole floor every guard can walk round corners towards the player without a
-- path of its own.

local nav = {}

local OFF = {
    {1, 0}, {-1, 0}, {0, 1}, {0, -1},
}

-- Every tile reachable from (cx, cy) within maxSteps, used once per guard at
-- level start to lay out a patrol round.
function nav.flood(level, cx, cy, maxSteps, open)
    local w, h = level.w, level.h
    local seen = {}
    local queue = {}
    local out = {}

    open = open or level.navOpen

    local start = level:index(cx, cy)
    if not start or not open(level, cx, cy) then
        return out
    end

    seen[start] = 0
    queue[1] = start

    local head, tail = 1, 1
    while head <= tail do
        local i = queue[head]
        head = head + 1

        local d = seen[i]
        local x = (i - 1) % w + 1
        local y = math.floor((i - 1) / w) + 1
        out[#out + 1] = {x = x, y = y, d = d}

        if d < maxSteps then
            for k = 1, 4 do
                local nx, ny = x + OFF[k][1], y + OFF[k][2]
                local ni = level:index(nx, ny)
                if ni and not seen[ni] and open(level, nx, ny) then
                    seen[ni] = d + 1
                    tail = tail + 1
                    queue[tail] = ni
                end
            end
        end
    end

    return out
end

function nav.newField()
    return {dist = {}, queue = {}, tx = 0, ty = 0, w = 0, h = 0}
end

function nav.build(field, level, cx, cy)
    local w, h = level.w, level.h
    local dist = field.dist
    local queue = field.queue

    field.w, field.h = w, h
    field.tx, field.ty = cx, cy

    for i = 1, w * h do
        dist[i] = -1
    end

    -- an entity standing half inside a wall would leave the field empty, so
    -- fall back to whatever open tile is next to it
    if not level:navOpen(cx, cy) then
        local fx, fy
        for dy = -1, 1 do
            for dx = -1, 1 do
                if not fx and level:navOpen(cx + dx, cy + dy) then
                    fx, fy = cx + dx, cy + dy
                end
            end
        end

        if not fx then
            return field
        end

        cx, cy = fx, fy
        field.tx, field.ty = cx, cy
    end

    local start = level:index(cx, cy)
    if not start then
        return field
    end

    dist[start] = 0
    queue[1] = start

    local head, tail = 1, 1
    while head <= tail do
        local i = queue[head]
        head = head + 1

        local d = dist[i] + 1
        local x = (i - 1) % w + 1
        local y = math.floor((i - 1) / w) + 1

        for k = 1, 4 do
            local nx, ny = x + OFF[k][1], y + OFF[k][2]
            local ni = level:index(nx, ny)
            if ni and dist[ni] < 0 and level:navOpen(nx, ny) then
                dist[ni] = d
                tail = tail + 1
                queue[tail] = ni
            end
        end
    end

    return field
end

-- A path of tile centres from (sx, sy) to (tx, ty), breadth first from the
-- target so walking it back is a slide down the numbers. This is what a guard
-- uses to reach a place he believes you are: unlike the shared field it is not
-- aimed at where you actually are.
function nav.path(level, sx, sy, tx, ty, maxSteps, out)
    out = out or {}
    for i = #out, 1, -1 do
        out[i] = nil
    end

    maxSteps = maxSteps or 70

    if not level:navOpen(tx, ty) then
        local fx, fy
        for dy = -1, 1 do
            for dx = -1, 1 do
                if not fx and level:navOpen(tx + dx, ty + dy) then
                    fx, fy = tx + dx, ty + dy
                end
            end
        end

        if not fx then
            return out
        end

        tx, ty = fx, fy
    end

    local w = level.w
    local si = level:index(sx, sy)
    local ti = level:index(tx, ty)
    if not si or not ti then
        return out
    end

    local dist = {}
    local queue = {ti}
    dist[ti] = 0

    local head, tail = 1, 1
    while head <= tail and not dist[si] do
        local i = queue[head]
        head = head + 1

        local d = dist[i] + 1
        if d > maxSteps then
            break
        end

        local x = (i - 1) % w + 1
        local y = math.floor((i - 1) / w) + 1

        for k = 1, 4 do
            local nx, ny = x + OFF[k][1], y + OFF[k][2]
            local ni = level:index(nx, ny)
            if ni and not dist[ni] and level:navOpen(nx, ny) then
                dist[ni] = d
                tail = tail + 1
                queue[tail] = ni
            end
        end
    end

    if not dist[si] then
        return out
    end

    local cx, cy = sx, sy
    for _ = 1, dist[si] do
        local bestX, bestY, best

        for dy = -1, 1 do
            for dx = -1, 1 do
                if dx ~= 0 or dy ~= 0 then
                    local nx, ny = cx + dx, cy + dy
                    local ni = level:index(nx, ny)
                    local d = ni and dist[ni]
                    if d and level:navOpen(nx, ny) then
                        local ok = true
                        if dx ~= 0 and dy ~= 0 then
                            ok = level:navOpen(cx + dx, cy) and level:navOpen(cx, cy + dy)
                        end

                        local score = d + ((dx ~= 0 and dy ~= 0) and 0.42 or 0)
                        if ok and (not best or score < best) then
                            best, bestX, bestY = score, nx, ny
                        end
                    end
                end
            end
        end

        if not bestX then
            break
        end

        out[#out + 1] = {x = bestX - 0.5, y = bestY - 0.5}
        cx, cy = bestX, bestY
        if cx == tx and cy == ty then
            break
        end
    end

    return out
end

function nav.distAt(field, level, cx, cy)
    local i = level:index(cx, cy)
    if not i then
        return -1
    end

    return field.dist[i] or -1
end

-- The neighbour tile that gets closer to the target, diagonals included when
-- both of the orthogonal tiles beside them are free.
function nav.step(field, level, cx, cy)
    local dist = field.dist
    local here = nav.distAt(field, level, cx, cy)
    local bestX, bestY, best

    if here < 0 then
        return nil
    end

    for dy = -1, 1 do
        for dx = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local nx, ny = cx + dx, cy + dy
                local ni = level:index(nx, ny)
                local d = ni and dist[ni] or -1
                if d >= 0 and level:navOpen(nx, ny) then
                    local ok = true
                    if dx ~= 0 and dy ~= 0 then
                        ok = level:navOpen(cx + dx, cy) and level:navOpen(cx, cy + dy)
                    end

                    local score = d + ((dx ~= 0 and dy ~= 0) and 0.42 or 0)
                    if ok and (not best or score < best) then
                        best, bestX, bestY = score, nx, ny
                    end
                end
            end
        end
    end

    if best and best < here + 0.5 then
        return bestX, bestY
    end

    return nil
end

-- A reachable tile near (ex, ey) that the player cannot see, used when a guard
-- wants to break line of sight to reload or to heal its nerve.
function nav.cover(level, field, ex, ey, px, py, span)
    span = span or 5

    local ecx, ecy = math.floor(ex) + 1, math.floor(ey) + 1
    local bestX, bestY, best

    for cy = ecy - span, ecy + span do
        for cx = ecx - span, ecx + span do
            local i = level:index(cx, cy)
            if i and level:navOpen(cx, cy) and not level:doorAt(cx, cy) then
                local d = field.dist[i]
                if d and d >= 0 then
                    local wx, wy = cx - 0.5, cy - 0.5
                    if not level:lineOfSight(wx, wy, px, py) then
                        local dx, dy = wx - ex, wy - ey
                        local walk = math.sqrt(dx * dx + dy * dy)
                        local score = walk + math.abs(d - 4) * 0.35
                        if not best or score < best then
                            best, bestX, bestY = score, cx, cy
                        end
                    end
                end
            end
        end
    end

    if bestX then
        return bestX - 0.5, bestY - 0.5
    end

    return nil
end

-- A tile the guard can shoot the player from, picked to one side so a pair of
-- guards spread out instead of queueing in the same doorway.
function nav.flank(level, ex, ey, px, py, side, span)
    span = span or 6

    local ax, ay = px - ex, py - ey
    local len = math.sqrt(ax * ax + ay * ay)
    if len < 1e-5 then
        return nil
    end

    ax, ay = ax / len, ay / len

    local sx, sy = -ay * side, ax * side
    local bestX, bestY, best

    for step = 2, span do
        local wx = px - ax * 3.0 + sx * step
        local wy = py - ay * 3.0 + sy * step
        local cx, cy = math.floor(wx) + 1, math.floor(wy) + 1
        if level:navOpen(cx, cy) and level:lineOfSight(cx - 0.5, cy - 0.5, px, py) then
            local score = step
            if not best or score < best then
                best, bestX, bestY = score, cx - 0.5, cy - 0.5
            end
        end
    end

    if bestX then
        return bestX, bestY
    end

    return nil
end

return nav
