-- Top-down RTS camera (StarCraft-like): free cursor, pan, zoom, rotate.
--
-- Controls:
--   WASD / arrows / screen edge - pan
--   middle mouse drag           - grab and drag the ground
--   mouse wheel                 - zoom
--   Q / E                       - rotate
--   left shift                  - faster pan

local arena = require "ocult:arena"

local this = {}

local MIN_DIST = 12
local MAX_DIST = 90
local PITCH_NEAR = 45   -- pitch (degrees) at MIN_DIST
local PITCH_FAR = 65    -- pitch (degrees) at MAX_DIST
local FOV = 50
local PAN_SPEED = 1.2   -- in camera distances per second
local EDGE_MARGIN = 6   -- px
local ROTATE_SPEED = 120 -- degrees per second
local ZOOM_STEP = 0.15  -- fraction of distance per wheel notch
local SMOOTHING = 12

local cam
local pid

-- target values; `cur` is the smoothed state that's actually rendered
local target = {x = 0, z = 0, dist = 40, yaw = 45}
local cur = {x = 0, y = 0, z = 0, dist = 40, yaw = 45}

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function key(name)
    return input.is_pressed("key:" .. name)
end

local function ground_height(x, z, fallback)
    local hit = block.raycast({x, 255, z}, {0, -1, 0}, 256)
    if hit then
        return hit.endpoint[2]
    end
    return fallback
end

-- ground-plane forward/right vectors for the current yaw
local function axes(yaw)
    local r = math.rad(yaw)
    local sy, cy = math.sin(r), math.cos(r)
    return -sy, -cy, cy, -sy
end

local function pitch_for(dist)
    local t = (dist - MIN_DIST) / (MAX_DIST - MIN_DIST)
    return lerp(PITCH_NEAR, PITCH_FAR, t)
end

-- world units per screen pixel at the focus point
local function units_per_pixel()
    local _, h = unpack(gui.get_viewport())
    return 2 * cur.dist * math.tan(math.rad(FOV) / 2) / h
end

-- engine locks the cursor whenever no GUI frame is active, so keep one active
local function keep_cursor_free()
    if not hud.is_paused() and gui.get_active_frame() == nil then
        gui.set_active_frame("core:main")
    end
end

local function handle_input(dt)
    local fx, fz, rx, rz = axes(cur.yaw)
    local mx, my = 0, 0

    if key("w") or key("up") then my = my + 1 end
    if key("s") or key("down") then my = my - 1 end
    if key("d") or key("right") then mx = mx + 1 end
    if key("a") or key("left") then mx = mx - 1 end

    local w, h = unpack(gui.get_viewport())
    local cx, cy = unpack(input.get_mouse_pos())
    if cx <= EDGE_MARGIN then mx = mx - 1 end
    if cx >= w - EDGE_MARGIN then mx = mx + 1 end
    if cy <= EDGE_MARGIN then my = my + 1 end
    if cy >= h - EDGE_MARGIN then my = my - 1 end

    if mx ~= 0 or my ~= 0 then
        local len = math.sqrt(mx * mx + my * my)
        local speed = PAN_SPEED * target.dist * dt / len
        if key("left-shift") then
            speed = speed * 2.5
        end
        target.x = target.x + (fx * my + rx * mx) * speed
        target.z = target.z + (fz * my + rz * mx) * speed
    end

    if input.is_pressed("mouse:middle") then
        local dx, dy = unpack(input.get_mouse_delta())
        local k = units_per_pixel()
        target.x = target.x - (rx * dx - fx * dy) * k
        target.z = target.z - (rz * dx - fz * dy) * k
    end

    local scroll = input.get_mouse_scroll()
    if scroll ~= 0 then
        target.dist = target.dist * (1 - ZOOM_STEP) ^ scroll
        target.dist = math.max(MIN_DIST, math.min(MAX_DIST, target.dist))
    end

    -- if key("q") then target.yaw = target.yaw - ROTATE_SPEED * dt end
    -- if key("e") then target.yaw = target.yaw + ROTATE_SPEED * dt end

    target.x, target.z = arena.clamp(target.x, target.z)
end

local function apply()
    local pitch = math.rad(pitch_for(cur.dist))
    local yaw = math.rad(cur.yaw)
    local horiz = math.cos(pitch) * cur.dist
    local pos = {
        cur.x + math.sin(yaw) * horiz,
        cur.y + math.sin(pitch) * cur.dist,
        cur.z + math.cos(yaw) * horiz,
    }
    cam:set_pos(pos)
    cam:look_at({cur.x, cur.y, cur.z})

    -- the player drives chunk loading, so drag it along (just behind the
    -- camera, where it can't be seen)
    player.set_pos(pid, pos[1], pos[2] + 3, pos[3])
    player.set_vel(pid, 0, 0, 0)
end

function this.init(playerid)
    pid = playerid
    cam = cameras.get("ocult:rts")
    cam:set_fov(FOV)
    cam:set_perspective(true)

    local x, y, z = arena.center()
    target.x, target.z = x, z
    cur.x, cur.y, cur.z = x, y, z

    player.set_flight(pid, true)
    player.set_noclip(pid, true)
    -- no first-person block selection/breaking; picking goes via cursor_ray
    player.set_interaction_distance(pid, 0)
    player.set_camera(pid, cam:get_index())
    input.set_enabled("camera.mode", false)
    hud.set_allow_pause(true)
    apply()
end

function this.update(dt)
    keep_cursor_free()
    if hud.is_paused() then
        return
    end
    handle_input(dt)

    local t = 1 - math.exp(-SMOOTHING * dt)
    cur.x = lerp(cur.x, target.x, t)
    cur.z = lerp(cur.z, target.z, t)
    cur.dist = lerp(cur.dist, target.dist, t)
    cur.yaw = lerp(cur.yaw, target.yaw, t)
    cur.y = lerp(cur.y, ground_height(cur.x, cur.z, cur.y), t * 0.5)
    apply()
end

function this.get_camera()
    return cam
end

-- current point on the ground the camera looks at
function this.get_focus()
    return {cur.x, cur.y, cur.z}
end

return this
