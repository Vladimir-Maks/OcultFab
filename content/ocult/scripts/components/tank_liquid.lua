-- The liquid inside a tank (buildings/tank spawns it at the block's origin
-- corner and keeps it in sync): the liquid cube of the tank model
-- (tools/tank.py) tinted with the liquid colour. It keeps its size and sinks
-- by `sink` blocks to show how full the tank is.
-- Only the model sinks (bone matrix), the entity stays put: the engine
-- lights the whole model by the light at the entity position, which would
-- be inside the floor block otherwise.
local liquids = require "ocult:liquids"

entity.rigidbody:set_enabled(false) -- placed by the tank, no physics
local rig = entity.skeleton

liquid = ARGS.liquid -- id, set by the tank
sink = 0

local shown_sink = 0

function on_render(delta)
    rig:set_color(liquids.color(liquid))
    if sink ~= shown_sink then
        shown_sink = sink
        rig:set_matrix(0, mat4.translate({0, -sink, 0}))
    end
end
