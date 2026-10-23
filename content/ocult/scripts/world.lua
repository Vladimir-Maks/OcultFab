local arena = require "ocult:arena"
local building = require "ocult:rts/building"
local economy = require "ocult:economy"

-- once per world: the core in the middle of the arena + the first cultist
local MARKER = "world:data/ocult/initialized"
local CORE = "ocult:core"
local START_UNITS = 1

local pending = false

function on_world_open()
    economy.load()
    pending = not file.exists(MARKER)
end

function on_world_save()
    economy.save()
end

function on_world_tick()
    if not pending then
        return
    end
    local cx, cy, cz = arena.center()
    -- wait until the arena center chunk is generated
    if block.get(cx, cy - 1, cz) == -1 then
        return
    end
    local sx, _, sz = block.get_size(block.index(CORE))
    building.place(CORE, {cx - math.floor(sx / 2), cy, cz - math.floor(sz / 2)})
    -- a row just south of the core
    for i = 1, START_UNITS do
        entities.spawn("ocult:worker", {cx + i * 2 - START_UNITS - 0.5, cy + 0.5, cz + 3.5})
    end
    file.mkdirs("world:data/ocult")
    file.write(MARKER, "")
    pending = false
end
