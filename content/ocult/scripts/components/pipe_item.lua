-- An item or a portion of liquid travelling through pipes: just a visual.
-- ARGS: {item = name} or {liquid = id}. ocult:logistics sets `target`
-- every world tick; it glides there every frame.
local liquids = require "ocult:liquids"

local tsf = entity.transform
entity.rigidbody:set_enabled(false) -- no physics, the position is set directly

local SMOOTHING = 20 -- higher = follows the target more tightly

-- a portion of liquid: a box with the grey liquid texture, tinted
-- (tools/cauldron.py)
local DROP_MODEL = "ocult_liquid_drop"

local rig = entity.skeleton
if ARGS.liquid then
    rig:set_model(0, DROP_MODEL)
    rig:set_color(liquids.color(ARGS.liquid))
else
    rig:set_model(0, item.model_name(item.index(ARGS.item)))
end

target = nil -- {x, y, z}

function on_render(delta)
    if not target then
        return
    end
    local pos = tsf:get_pos()
    local t = 1 - math.exp(-SMOOTHING * delta)
    tsf:set_pos({
        pos[1] + (target[1] - pos[1]) * t,
        pos[2] + (target[2] - pos[2]) * t,
        pos[3] + (target[3] - pos[3]) * t,
    })
end
