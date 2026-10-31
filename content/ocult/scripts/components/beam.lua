-- A shot of an eye tower: a beam (model along -Z, 1 block long, glowing
-- pipe-light texture) from ARGS.from to ARGS.to, tinted with ARGS.color,
-- thinning out in LIFETIME; sparks burst where it hits.
local LIFETIME = 0.35
local SPARKS = {
    texture = "blocks:ocult_pipe_light",
    lighting = false,
    collision = false,
    lifetime = 0.45,
    lifetime_spread = 0.3,
    acceleration = {0, -4, 0},
    explosion = {3, 3, 3},
    size = {0.08, 0.08, 0.08},
    size_spread = 0.5,
    max_distance = 64,
}

entity.rigidbody:set_enabled(false)
local tsf = entity.transform
local rig = entity.skeleton

local from, to = ARGS.from, ARGS.to
local d = {to[1] - from[1], to[2] - from[2], to[3] - from[3]}
local length = vec3.length(d)
local yaw = math.deg(math.atan2(-d[1], -d[3]))
local pitch = math.deg(math.atan2(d[2], math.sqrt(d[1] * d[1] + d[3] * d[3])))

tsf:set_pos(from)
tsf:set_rot(mat4.mul(mat4.rotate({0, 1, 0}, yaw), mat4.rotate({1, 0, 0}, pitch)))
rig:set_matrix(0, mat4.scale({1, 1, length}))

local color = ARGS.color or {1, 1, 1}
local life = LIFETIME

gfx.particles.emit(to, 14, SPARKS)
gfx.particles.emit(from, 5, SPARKS, {explosion = {1, 1, 1}, lifetime = 0.25})

function on_render(delta)
    life = life - delta
    if life <= 0 then
        entity:despawn()
        return
    end
    local k = life / LIFETIME
    rig:set_color(color)
    rig:set_matrix(0, mat4.scale({k, k, length})) -- gets thinner
end
