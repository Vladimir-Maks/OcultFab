-- Base for mobile units (entities).
--
-- Right click on the ground -> walk there: A* route (pathfinding library),
-- smooth acceleration up to max speed and smooth braking before the target.
-- The model turns towards the movement direction; turning is purely visual
-- and never slows the unit down.
--
-- Units are solid (entity "solid": true) and also keep apart softly: nearby
-- units push each other aside, idle ones step out of the way. A unit that
-- makes no progress re-paths; one whose target cell is taken by another unit
-- stops next to it.
--
-- Traffic rules for units meeting on the way: a unit ahead in our lane makes
-- us steer aside (head-on: both keep right and pass); of two units meeting
-- head-on the one with the lower traffic_priority() (ties: higher uid)
-- slows down and lets the other pass. Workers carrying an item go first.
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
local SEPARATION_RADIUS = 0.9  -- blocks: closer units push each other
local LOOKAHEAD = 1.6          -- blocks ahead checked for oncoming units
local LANE_WIDTH = 0.8         -- units further sideways aren't in our way
local AVOID_STRENGTH = 0.9     -- sidestep speed, fraction of own speed
local YIELD_SPEED = 0.3        -- speed fraction when giving way
local SEPARATION_SPEED = 1.5   -- blocks/s at full overlap
local CROWD_ARRIVE = 1.2       -- "arrived" this close if the target is taken
local STUCK_CHECK = 1.0        -- seconds between progress checks
local STUCK_PROGRESS = 0.25    -- blocks of progress expected per check
local STUCK_GIVE_UP = 3        -- failed checks in a row before giving up
local TURN_SMOOTHING = 10 -- higher = faster turning

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

-- horizontal {x, z} of a block cell centre / of a position
local function center(p)
    return {p[1] + 0.5, p[3] + 0.5}
end

local function flat(p)
    return {p[1], p[3]}
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
    local target, on_arrive, on_fail
    local stuck_timer, stuck_count, last_remaining = 0, 0, nil
    local route -- waypoints, route[#route] is the next one; nil while searching
    local had_waypoints = false
    local speed = 0
    local dir_x, dir_z = 0, 1 -- last movement direction
    local yaw = 0             -- rendered model yaw, degrees

    -- the unit sets its velocity itself
    body:set_linear_damping(0)

    local agent = pathfinding.create_agent()
    pathfinding.set_max_visited(agent, MAX_VISITED)
    -- units can't jump: the raised (unmined) stone is a wall for them
    pathfinding.set_jump_height(agent, 0)

    rig:set_color(def.color or {1, 1, 1})

    -- selection doesn't change how a unit looks
    object.extend(env, def, function(selected) end)

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

    -- pos - block position to stand on; callback (optional) fires on arrival,
    -- fail (optional) when there is no path
    function env.move_to(pos, callback, fail)
        target = {pos[1], pos[2], pos[3]}
        on_arrive = callback
        on_fail = fail
        route = nil
        had_waypoints = false
        stuck_timer, stuck_count, last_remaining = 0, 0, nil
        pathfinding.make_route_async(agent, tsf:get_pos(), target)
    end

    function env.stop()
        target = nil
        on_arrive = nil
        on_fail = nil
        route = nil
        halt()
    end

    -- current movement direction {x, z}, or nil when standing
    function env.get_move_dir()
        if target and speed > 0.05 then
            return {dir_x, dir_z}
        end
        return nil
    end

    -- who goes first when two units meet head-on (higher wins);
    -- units override it (workers: carrying an item = 1)
    function env.traffic_priority()
        return 0
    end

    -- sidestep for units ahead in our lane + whether we should give way
    local function avoidance(pos, dx, dz)
        local rx, rz = -dz, dx -- right-hand side
        local ax, az = 0, 0
        local yield = false
        for _, other in ipairs(entities.get_all_in_radius(pos, LOOKAHEAD)) do
            local comp = other ~= uid and unit.get(other)
            if comp then
                local opos = entities.get(other).transform:get_pos()
                local ox, oz = opos[1] - pos[1], opos[3] - pos[3]
                local ahead = ox * dx + oz * dz
                local lateral = ox * rx + oz * rz
                if ahead > 0 and math.abs(lateral) < LANE_WIDTH then
                    local odir = comp.get_move_dir()
                    local head_on = odir and (odir[1] * dx + odir[2] * dz) < -0.3
                    if head_on or not odir then
                        -- dead ahead: keep right (the other one does the
                        -- same); slightly to one side: pass on the other
                        local side = lateral > 0.15 and -1 or 1
                        local k = (1 - ahead / LOOKAHEAD) * AVOID_STRENGTH
                        ax, az = ax + rx * side * k, az + rz * side * k
                    end
                    if head_on then
                        local mine, theirs = env.traffic_priority(), comp.traffic_priority()
                        if mine < theirs or (mine == theirs and uid > other) then
                            yield = true
                        end
                    end
                end
            end
        end
        return ax, az, yield
    end

    -- pos is nil for orders on an item: units that can't gather ignore them
    function env.on_order(pos, target_uid)
        if not pos then
            return
        end
        env.move_to(pos)
    end

    local function arrive()
        local callback = on_arrive
        env.stop()
        if callback then
            callback()
        end
    end

    local function fail()
        local callback = on_fail
        env.stop()
        if callback then
            callback()
        end
    end

    -- push away from other units closer than SEPARATION_RADIUS;
    -- also tells if one of them stands at `spot` ({x, z}, optional)
    local function separation(pos, spot)
        local sx, sz = 0, 0
        local target_taken = false
        for _, other in ipairs(entities.get_all_in_radius(pos, SEPARATION_RADIUS * 2)) do
            if other ~= uid and unit.get(other) then
                local opos = entities.get(other).transform:get_pos()
                local dx, dz = pos[1] - opos[1], pos[3] - opos[3]
                local d = vec2.length({dx, dz})
                if d < SEPARATION_RADIUS then
                    if d < 1e-3 then
                        dx, dz, d = math.random() - 0.5, math.random() - 0.5, 0.5
                    end
                    local k = (1 - d / SEPARATION_RADIUS) / d
                    sx, sz = sx + dx * k, sz + dz * k
                end
                if spot and vec2.distance(flat(opos), spot) < 0.6 then
                    target_taken = true
                end
            end
        end
        return sx * SEPARATION_SPEED, sz * SEPARATION_SPEED, target_taken
    end

    function env.on_physics_update(delta)
        if not target then
            -- idle: only step aside when someone is too close
            local sx, sz = separation(tsf:get_pos())
            local vel = body:get_vel()
            body:set_vel({sx, vel[2], sz})
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
            fail() -- unreachable
            return
        end

        local pos = tsf:get_pos()
        local here = flat(pos)
        local goal = center(target)

        -- route[#route] is the next waypoint, route[1] the last one
        while #route > 0 do
            if vec2.distance(here, center(route[#route])) > WAYPOINT_REACHED then
                break
            end
            table.remove(route, #route)
        end

        local next_point = goal
        local remaining
        if #route > 0 then
            next_point = center(route[#route])
            remaining = vec2.distance(here, next_point)
            for i = #route, 2, -1 do
                remaining = remaining + vec2.distance(center(route[i]), center(route[i - 1]))
            end
            remaining = remaining + vec2.distance(center(route[1]), goal)
        else
            remaining = vec2.distance(here, goal)
        end

        local sx, sz, target_taken = separation(pos, goal)
        if remaining < ARRIVE_DISTANCE or (target_taken and remaining < CROWD_ARRIVE) then
            arrive()
            return
        end

        -- no progress (blocked by other units): re-path, eventually give up
        stuck_timer = stuck_timer + delta
        if stuck_timer >= STUCK_CHECK then
            stuck_timer = 0
            if last_remaining and last_remaining - remaining < STUCK_PROGRESS then
                stuck_count = stuck_count + 1
                if stuck_count >= STUCK_GIVE_UP then
                    if remaining < CROWD_ARRIVE * 2 then
                        arrive()
                    else
                        fail()
                    end
                    return
                end
                route = nil
                pathfinding.make_route_async(agent, pos, target)
            else
                stuck_count = 0
            end
            last_remaining = remaining
        end

        -- ease in: accelerate up to max; ease out: never faster than what
        -- still allows stopping exactly at the target
        local brake_limit = math.sqrt(2 * accel * remaining)
        speed = math.min(speed + accel * delta, max_speed, brake_limit)

        local dir = vec2.normalize(vec2.sub(next_point, here))
        local dx, dz = dir[1], dir[2]
        local vel = body:get_vel()
        local ax, az, yield = avoidance(pos, dx, dz)
        local forward = yield and speed * YIELD_SPEED or speed
        body:set_vel({dx * forward + ax * speed + sx, vel[2], dz * forward + az * speed + sz})
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
