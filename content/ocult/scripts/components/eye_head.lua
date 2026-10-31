-- The plant with the eye on top of an eye tower (group5 of
-- .assets/eye_tower/eye-tower.bbmodel; the eye looks along -Z). The tower
-- (buildings/eye_tower) spawns it in the middle of its block and sets `aim`
-- ({x, y, z} or nil); the head turns towards it smoothly. shoot() makes
-- it jerk (swells up and shrinks back) on every shot.
entity.rigidbody:set_enabled(false) -- placed by the tower, no physics
local tsf = entity.transform

local TURN_SMOOTHING = 8 -- higher = faster turning
local RECOIL = 0.25      -- how much bigger it gets on a shot
local RECOIL_TIME = 0.3  -- seconds to shrink back

aim = nil
local yaw = math.random() * 360
local recoil = 0

function shoot()
    recoil = RECOIL_TIME
end

function on_render(delta)
    if aim then
        local pos = tsf:get_pos()
        local target_yaw = math.deg(math.atan2(-(aim[1] - pos[1]), -(aim[3] - pos[3])))
        local diff = (target_yaw - yaw + 180) % 360 - 180
        yaw = yaw + diff * (1 - math.exp(-TURN_SMOOTHING * delta))
    end
    tsf:set_rot(mat4.rotate({0, 1, 0}, yaw))
    if recoil > 0 then
        recoil = math.max(0, recoil - delta)
        local s = 1 + RECOIL * recoil / RECOIL_TIME
        entity.skeleton:set_matrix(0, mat4.scale({s, s, s}))
    end
end
