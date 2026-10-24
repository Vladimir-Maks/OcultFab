-- Pipe logistics: items travel through pipes between buildings and storages.
--
-- A storage is a building whose definition has `storage = true` (the core).
-- Routes follow connected pipes from a building's ports to the nearest
-- storage; port modes must match on both ends:
--   import: building "in" (or any)  <- storage "out" (or any)
--   export: building "out" (or any) -> storage "in" (or any)
-- Items in transit are small entities moved along the route by update(),
-- which scripts/world.lua calls every tick. They aren't saved: whatever is
-- in the pipes when the world is closed is lost.
local building = require "ocult:rts/building"
local pipes = require "ocult:pipes"
local economy = require "ocult:economy"
local drops = require "ocult:drops"

local this = {}

local ENTITY = "ocult:pipe_item"
local SPEED = 3.0     -- blocks per second
local INTERVAL = 0.25 -- seconds between items of one shipment
local LIFT = 0.25     -- item height above the floor, in the middle of a pipe

local IMPORT = {mine = {["in"] = true, [building.ANY] = true},
                storage = {out = true, [building.ANY] = true}}
local EXPORT = {mine = {out = true, [building.ANY] = true},
                storage = {["in"] = true, [building.ANY] = true}}

local DIRS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

local shipments = {} -- items waiting for their turn or travelling
local jobs = {}      -- building key -> {total, arrived}

local function key(b)
    return b.x .. "," .. b.y .. "," .. b.z
end

local function cell_key(x, z)
    return x .. "," .. z
end

-- route between building b (handle from building.instance) and the nearest
-- storage, as a list of {x, z} cells from the storage cell to b's port cell
local function find_route(b, modes)
    local y = b.y
    local prev, queue = {}, {}
    for _, p in ipairs(building.ports(b.id, b.x, b.y, b.z)) do
        local px, _, pz, dx, dz, mode = unpack(p)
        local cx, cz = px + dx, pz + dz
        if modes.mine[mode] and pipes.is_pipe(cx, y, cz) and not prev[cell_key(cx, cz)] then
            prev[cell_key(cx, cz)] = {px, pz} -- the pipe leads into our port cell
            table.insert(queue, {cx, cz})
        end
    end
    local head = 1
    while head <= #queue do
        local c = queue[head]
        head = head + 1
        for _, d in ipairs(DIRS) do
            local nx, nz = c[1] + d[1], c[2] + d[2]
            local k = cell_key(nx, nz)
            if pipes.is_pipe(nx, y, nz) then
                if not prev[k] then
                    prev[k] = c
                    table.insert(queue, {nx, nz})
                end
            else
                local id = block.get(nx, y, nz)
                local def = id > 0 and building.get_def(id)
                if def and def.storage then
                    local ox, _, oz = block.seek_origin(nx, y, nz)
                    local mode = building.port_mode(nx, y, nz, -d[1], -d[2])
                    if (ox ~= b.x or oz ~= b.z) and mode and modes.storage[mode] then
                        -- walk back: pipes ... first pipe -> our port cell
                        -- (the port cell has no prev, which ends the walk)
                        local route = {{nx, nz}}
                        local cell = c
                        while cell do
                            table.insert(route, cell)
                            cell = prev[cell_key(cell[1], cell[2])]
                        end
                        return route
                    end
                end
            end
        end
    end
    return nil
end

local function ship(name, route, y, delay, on_arrive)
    table.insert(shipments, {
        item = name, route = route, y = y, delay = delay,
        progress = 0, on_arrive = on_arrive,
    })
end

local function reversed(route)
    local r = {}
    for i = #route, 1, -1 do
        table.insert(r, route[i])
    end
    return r
end

-- true if b has a pipe route to a storage for importing
function this.can_import(b)
    return find_route(b, IMPORT) ~= nil
end

-- takes `cost` out of the nearest storage and sends it to b through the
-- pipes; on_done() once everything has arrived.
-- Returns true, or false and the reason for the player.
function this.import(b, cost, on_done)
    if jobs[key(b)] then
        return false, "Здание уже занято"
    end
    local route = find_route(b, IMPORT)
    if not route then
        return false, "Нет трубы к хранилищу"
    end
    if not economy.spend(cost) then
        return false, "Не хватает: " .. economy.cost_text(cost)
    end
    local items = {}
    for name, n in pairs(cost) do
        for _ = 1, n do
            table.insert(items, name)
        end
    end
    local job = {total = #items, arrived = 0}
    jobs[key(b)] = job
    for i, name in ipairs(items) do
        ship(name, route, b.y, (i - 1) * INTERVAL, function()
            job.arrived = job.arrived + 1
            if job.arrived == job.total then
                jobs[key(b)] = nil
                on_done()
            end
        end)
    end
    return true
end

-- sends count x item `name` from b to the nearest storage through the
-- pipes. Returns true, or false and the reason.
function this.export(b, name, count)
    local route = find_route(b, EXPORT)
    if not route then
        return false, "Нет трубы к хранилищу"
    end
    route = reversed(route)
    local last = route[#route]
    for i = 1, count do
        ship(name, route, b.y, (i - 1) * INTERVAL, function()
            if economy.add(name, 1) == 0 then
                -- storage is full: the item falls out next to it
                drops.spawn(item.index(name), 1, {last[1] + 0.5, b.y + 0.3, last[2] + 0.5})
            end
        end)
    end
    return true
end

-- {total, arrived} of the import job running for b, or nil
function this.job(b)
    return jobs[key(b)]
end

-- position along the route after `dist` blocks
local function point_at(route, y, dist)
    for i = 1, #route - 1 do
        local a, c = route[i], route[i + 1]
        if dist <= 1 then
            return {a[1] + 0.5 + (c[1] - a[1]) * dist, y + LIFT, a[2] + 0.5 + (c[2] - a[2]) * dist}
        end
        dist = dist - 1
    end
    local e = route[#route]
    return {e[1] + 0.5, y + LIFT, e[2] + 0.5}
end

function this.update(dt)
    local i = 1
    while i <= #shipments do
        local s = shipments[i]
        local done = false
        if s.delay > 0 then
            s.delay = s.delay - dt
        else
            if not s.uid then
                local pos = point_at(s.route, s.y, 0)
                s.uid = entities.spawn(ENTITY, pos, {ocult__pipe_item = {item = s.item}}):get_uid()
            end
            s.progress = s.progress + SPEED * dt
            local e = entities.get(s.uid)
            if s.progress >= #s.route - 1 or not e then
                done = true
                if e then
                    e:despawn()
                end
            else
                -- the item glides there itself every frame (pipe_item component)
                e:get_component("ocult:pipe_item").target = point_at(s.route, s.y, s.progress)
            end
        end
        if done then
            table.remove(shipments, i)
            s.on_arrive()
        else
            i = i + 1
        end
    end
end

return this
