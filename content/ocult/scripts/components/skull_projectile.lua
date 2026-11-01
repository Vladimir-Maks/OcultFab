-- A skull shot by a "ПЛОХИЕ КОСТИ" altar: flies in an arc from ARGS.from to
-- ARGS.to at ARGS.speed blocks/s, spinning; where it lands every enemy in a
-- square of ARGS.splash blocks takes ARGS.damage.
local combat = require "ocult:combat"

local ARC = 0.25 -- arc height per block of distance
local SPIN = 540 -- degrees per second
local BURST = {
    texture = "blocks:ocult_skull_altar",
    random_sub_uv = 0.2,
    lighting = true,
    collision = false,
    lifetime = 0.6,
    lifetime_spread = 0.3,
    acceleration = {0, -10, 0},
    explosion = {4, 4, 4},
    size = {0.12, 0.12, 0.12},
    size_spread = 0.5,
    max_distance = 64,
}

entity.rigidbody:set_enabled(false)
local tsf = entity.transform

local from, to = ARGS.from, ARGS.to
local distance = vec3.distance(from, to)
local duration = math.max(0.1, distance / ARGS.speed)
local t = 0

local function land()
    local half = ARGS.splash / 2
    for _, enemy in ipairs(combat.enemies()) do
        if math.abs(enemy.pos[1] - to[1]) <= half and math.abs(enemy.pos[3] - to[3]) <= half
                and enemy.comp.take_damage then
            enemy.comp.take_damage(ARGS.damage)
        end
    end
    gfx.particles.emit(to, 24, BURST)
    entity:despawn()
end

function on_render(delta)
    t = t + delta
    local k = math.min(1, t / duration)
    local h = 4 * ARC * distance * k * (1 - k)
    tsf:set_pos({
        from[1] + (to[1] - from[1]) * k,
        from[2] + (to[2] - from[2]) * k + h,
        from[3] + (to[3] - from[3]) * k,
    })
    tsf:set_rot(mat4.rotate({1, 0, 0}, t * SPIN))
    if k >= 1 then
        land()
    end
end
