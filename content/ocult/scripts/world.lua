local arena = require "ocult:arena"
local building = require "ocult:rts/building"

-- once per world: the core in the middle of the arena (+ dev test cultists).
-- Separate markers, so worlds made before the core existed get it too.
local CORE_MARKER = "world:data/ocult/core_spawned"
local UNITS_MARKER = "world:data/ocult/test_units_spawned"
local CORE = "ocult:core"
local TEST_UNITS = 3

local pending = false

function on_world_open()
    pending = not file.exists(CORE_MARKER) or not file.exists(UNITS_MARKER)
end

local function mark(path)
    file.mkdirs("world:data/ocult")
    file.write(path, "")
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
    if not file.exists(CORE_MARKER) then
        local sx, _, sz = block.get_size(block.index(CORE))
        building.place(CORE, {cx - math.floor(sx / 2), cy, cz - math.floor(sz / 2)})
        mark(CORE_MARKER)
    end
    if not file.exists(UNITS_MARKER) then
        -- a row just south of the core
        for i = 1, TEST_UNITS do
            entities.spawn("ocult:worker", {cx + i * 2 - TEST_UNITS - 0.5, cy + 0.5, cz + 3.5})
        end
        mark(UNITS_MARKER)
    end
    pending = false
end
