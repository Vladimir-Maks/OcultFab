local arena = require "ocult:arena"

-- dev: spawn a few test cultists once per world
local MARKER = "world:data/ocult/test_units_spawned"
local TEST_UNITS = 3

local pending = false

function on_world_open()
    pending = not file.exists(MARKER)
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
    for i = 1, TEST_UNITS do
        entities.spawn("ocult:worker", {cx + i * 2 - TEST_UNITS - 0.5, cy + 0.5, cz + 0.5})
    end
    file.mkdirs("world:data/ocult")
    file.write(MARKER, "")
    pending = false
end
