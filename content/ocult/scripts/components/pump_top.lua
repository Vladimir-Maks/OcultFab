-- Moving parts of an item pump (groups Top and Coil2 of the model, skeleton
-- skeletons/pump.json by tools/bbmodel2rig.py): buildings/pump spawns it in
-- the middle of the block; it plays the idle animation forever.
local IDLE = "ocult_pump_idle"

entity.rigidbody:set_enabled(false) -- placed by the pump, no physics

local track = animation.play(IDLE, entity.skeleton)

function on_despawn()
    track:stop()
end
