-- Ray from the mouse cursor through the current camera into the world.
-- Used to pick blocks/ground under the cursor (units, buildings).

local this = {}

local MAX_DISTANCE = 500

local function normalize(v)
    local len = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
    return {v[1] / len, v[2] / len, v[3] / len}
end

-- returns origin, direction of the ray under the screen point (defaults to cursor)
function this.get_ray(cam, screen_pos)
    local w, h = unpack(gui.get_viewport())
    local mx, my = unpack(screen_pos or input.get_mouse_pos())
    local nx = mx / w * 2 - 1
    local ny = 1 - my / h * 2

    local tan_half = math.tan(math.rad(cam:get_fov()) / 2)
    local sx = nx * tan_half * (w / h)
    local sy = ny * tan_half

    local f, r, u = cam:get_front(), cam:get_right(), cam:get_up()
    local dir = normalize({
        f[1] + r[1] * sx + u[1] * sy,
        f[2] + r[2] * sx + u[2] * sy,
        f[3] + r[3] * sx + u[3] * sy,
    })
    return cam:get_pos(), dir
end

-- screen position {x, y} of a world point, or nil if it's behind the camera
function this.world_to_screen(cam, point)
    local w, h = unpack(gui.get_viewport())
    local p = cam:get_pos()
    local v = {point[1] - p[1], point[2] - p[2], point[3] - p[3]}
    local f, r, u = cam:get_front(), cam:get_right(), cam:get_up()
    local depth = v[1] * f[1] + v[2] * f[2] + v[3] * f[3]
    if depth <= 0 then
        return nil
    end
    local tan_half = math.tan(math.rad(cam:get_fov()) / 2)
    local nx = (v[1] * r[1] + v[2] * r[2] + v[3] * r[3]) / (depth * tan_half * (w / h))
    local ny = (v[1] * u[1] + v[2] * u[2] + v[3] * u[3]) / (depth * tan_half)
    return {(nx + 1) / 2 * w, (1 - ny) / 2 * h}
end

-- block.raycast result ({block, endpoint, iendpoint, length, normal}) or nil
function this.pick(cam, screen_pos, max_distance)
    local origin, dir = this.get_ray(cam, screen_pos)
    return block.raycast(origin, dir, max_distance or MAX_DISTANCE)
end

return this
