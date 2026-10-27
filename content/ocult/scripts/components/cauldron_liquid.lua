-- The liquid inside a cauldron (buildings/cauldron spawns it at the block's
-- corner and keeps it in sync): the grey liquid model tinted with the liquid
-- colour. While `melting` is true it flickers brighter and darker; every
-- cauldron has its own phase.
local liquids = require "ocult:liquids"

local MELT_PERIOD = 1.2 -- seconds per brightness cycle
local MELT_SWING = 0.3  -- brightness goes 1 - swing .. 1 + swing

entity.rigidbody:set_enabled(false) -- placed by the cauldron, no physics
local rig = entity.skeleton

liquid = ARGS.liquid -- id, set by the cauldron
melting = false

local phase = math.random() * MELT_PERIOD
local time_passed = 0

function on_render(delta)
    time_passed = time_passed + delta
    local k = 1
    if melting then
        k = 1 + MELT_SWING * math.sin((time_passed + phase) / MELT_PERIOD * 2 * math.pi)
    end
    local c = liquids.color(liquid)
    rig:set_color({c[1] * k, c[2] * k, c[3] * k})
end
