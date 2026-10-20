-- Base for mobile units (entities).
--
-- Right click on the ground -> walk there: A* route (pathfinding library),
-- smooth acceleration up to max speed and smooth braking before the target.
-- The model turns towards the movement direction; turning is purely visual
-- and never slows the unit down.
--
-- Extra def fields:
--   speed - max speed, blocks/s
--   accel - acceleration and braking, blocks/s^2

local object = require "ocult:rts/object"

local unit = {}

local ARRIVE_DISTANCE = 0.15
local WAYPOINT_REACHED = 0.4
local DEFAULT_SPEED = 3.0
local DEFAULT_ACCEL = 6.0
local MAX_VISITED = 5000
local JUMP_SPEED = 6.0
local TURN_SMOOTHING = 10 -- higher = faster turning
local SELECTED_LIGHTEN = 0.5

-- main component of a unit entity, or nil
function unit.get(uid)
    local e = entities.get(uid)
    if not e then
        return nil
    end
    local comp = e:get_component(e:def_name())
    if comp and comp.is_rts_object then
        return comp
    end
    return nil
end

local function center(p)
    return p[1] + 0.5, p[3] + 0.5
end

local function hdist(x1, z1, x2, z2)
    local dx, dz = x2 - x1, z2 - z1
    return math.sqrt(dx * dx + dz * dz)
end

function unit.extend(env, def)
    local entity = env.entity
    local tsf = entity.transform
    local body = entity.rigidbody
    local rig = entity.skeleton
    local uid = entity:get_uid()
    local max_speed = def.speed or DEFAULT_SPEED
    local accel = def.accel or DEFAULT_ACCEL

    local alive = true
    local target, on_arrive
    local route -- waypoints, route[#route] is the next one; nil while searching
    local had_waypoints = false
    local speed = 0
    local dir_x, dir_z = 0, 1 -- last movement direction
    local yaw = 0             -- rendered model yaw, degrees

    -- the unit sets its velocity itself
    body:set_linear_damping(0)

    local agent = pathfinding.create_agent()
    pathfinding.set_max_visited(agent, MAX_VISITED)

    local function tint(selected)
        local c = def.color or {1, 1, 1}
        if selected then
            local k = SELECTED_LIGHTEN
            c = {c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k}
        end
        rig:set_color(c)
    end

    object.extend(env, def, tint)
    tint(false)

    function env.key() return uid end
    function env.is_alive() return alive and entities.exists(uid) end
    function env.get_pos() return tsf:get_pos() end

    -- despawn without waiting for the end of the frame to stop being selectable
    function env.remove()
        alive = false
        entity:despawn()
    end

    local function halt()
        local vel = body:get_vel()
        body:set_vel({0, vel[2], 0})
        speed = 0
    end

    -- pos - block position to stand on; callback(optional) fires on arrival
    function env.move_to(pos, callback)
        target = {pos[1], pos[2], pos[3]}
        on_arrive = callback
        route = nil
        had_waypoints = false
        pathfinding.make_route_async(agent, tsf:get_pos(), target)
    end

    function env.stop()
        target = nil
        on_arrive = nil
        route = nil
        halt()
    end

    function env.is_moving()
        return target ~= nil
    end

    function env.on_order(pos, target_uid)
        env.move_to(pos)
    end

    local function arrive()
        local callback = on_arrive
        env.stop()
        if callback then
            callback()
        end
    end

    function env.on_physics_update(delta)
        if not target then
            return
        end
        if not route then
            route = pathfinding.pull_route(agent)
            if not route then
                return -- still searching
            end
            -- a late answer to a previous order: ask again
            local last = route[1]
            if last and (last[1] ~= target[1] or last[3] ~= target[3]) then
                route = nil
                pathfinding.make_route_async(agent, tsf:get_pos(), target)
                return
            end
        end
        if #route > 0 then
            had_waypoints = true
        elseif not had_waypoints then
            env.stop() -- unreachable
            return
        end

        local pos = tsf:get_pos()
        local tx, tz = center(target)

        -- route[#route] is the next waypoint, route[1] the last one
        while #route > 0 do
            local wx, wz = center(route[#route])
            if hdist(pos[1], pos[3], wx, wz) > WAYPOINT_REACHED then
                break
            end
            table.remove(route, #route)
        end

        local nx, nz = tx, tz
        local remaining
        if #route > 0 then
            nx, nz = center(route[#route])
            remaining = hdist(pos[1], pos[3], nx, nz)
            for i = #route, 2, -1 do
                local ax, az = center(route[i])
                local bx, bz = center(route[i - 1])
                remaining = remaining + hdist(ax, az, bx, bz)
            end
            local lx, lz = center(route[1])
            remaining = remaining + hdist(lx, lz, tx, tz)
        else
            remaining = hdist(pos[1], pos[3], tx, tz)
        end

        if remaining < ARRIVE_DISTANCE then
            arrive()
            return
        end

        -- ease in: accelerate up to max; ease out: never faster than what
        -- still allows stopping exactly at the target
        local brake_limit = math.sqrt(2 * accel * remaining)
        speed = math.min(speed + accel * delta, max_speed, brake_limit)

        local dist = hdist(pos[1], pos[3], nx, nz)
        local dx, dz = (nx - pos[1]) / dist, (nz - pos[3]) / dist
        local vel = body:get_vel()
        if #route > 0 and route[#route][2] > math.floor(pos[2]) and body:is_grounded() then
            vel[2] = JUMP_SPEED
        end
        body:set_vel({dx * speed, vel[2], dz * speed})
        dir_x, dir_z = dx, dz
    end

    -- model front is -Z
    function env.on_render(delta)
        local target_yaw = math.deg(math.atan2(-dir_x, -dir_z))
        local diff = (target_yaw - yaw + 180) % 360 - 180
        yaw = yaw + diff * (1 - math.exp(-TURN_SMOOTHING * delta))
        tsf:set_rot(mat4.rotate({0, 1, 0}, yaw))
    end

    function env.on_despawn()
        pathfinding.remove_agent(agent)
    end
end

return unit
