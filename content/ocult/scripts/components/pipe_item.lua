-- An item travelling through pipes: just a visual. ocult:logistics sets
-- `target` every world tick; the item glides there every frame.
local tsf = entity.transform
entity.rigidbody:set_enabled(false) -- no physics, the position is set directly

local SMOOTHING = 20 -- higher = follows the target more tightly

local id = item.index(ARGS.item)
entity.skeleton:set_model(0, item.model_name(id))

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
