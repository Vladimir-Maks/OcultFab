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
-- Units live on the floor (arena.LEVEL): their height is fixed every physics
-- step, and the entity needs "step-height": 0 so the engine doesn't lift it
-- onto low blocks (pipes, the altar).
--
-- Traffic rules for units meeting on the way: a unit ahead in our lane makes
-- us steer aside (head-on: both keep right and pass); of two units meeting
-- head-on the one with the lower traffic_priority() (ties: higher uid)
-- slows down and lets the other pass. Workers carrying an item go first.
--
-- Extra def fields:
--   speed  - max speed, blocks/s
--   accel  - acceleration and braking, blocks/s^2
--   health - hit points (saved); at 0 the unit dies (env.on_death(), then
--            it's removed). Without it the unit can't be damaged
--   enemy  - true for enemies: not selectable, don't reveal the fog
--   model_yaw - degrees added to the model's rotation, for models whose
--            front isn't -Z (90: the model looks along +X)

local object = require "ocult:rts/object"
local building = require "ocult:rts/building"
local arena = require "ocult:arena"

local unit = {}

unit.AVOID_TAG = "ocult:avoid"

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
local HIT_FLASH = 0.25           -- seconds a damaged unit is tinted
local HIT_COLOR = {1, 0.25, 0.25}
local UNSTUCK_RADIUS = 3  -- blocks searched for a free cell when inside a block

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

-- main component of one of our units (not an enemy), or nil
function unit.get_own(uid)
    local comp = unit.get(uid)
    if comp and not comp.def.enemy then
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
    -- cells to walk around: blocks tagged "ocult:avoid" (e.g. under a
    -- sitting mimic, see components/mimic)
    pathfinding.avoid_tag(agent, unit.AVOID_TAG)

    local base_color = def.color or {1, 1, 1}
    local flash = 0 -- seconds of the hit flash left
    rig:set_color(base_color)

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

    if def.health then
        env.max_health = def.health
        env.health = env.SAVED_DATA.health or def.health

        function env.take_damage(n)
            if not alive then
                return
            end
            env.health = math.max(0, env.health - n)
            env.SAVED_DATA.health = env.health
            flash = HIT_FLASH
            if env.health == 0 then
                if env.on_death then
                    env.on_death()
                end
                env.remove()
            end
        end
    end

    -- "Прочность: 7/10" for descriptions, "" without health
    function env.health_text()
        if not env.max_health then
            return ""
        end
        return string.format("Прочность: %d/%d", env.health, env.max_health)
    end

    local function halt()
        local vel = body:get_vel()
        body:set_vel({0, vel[2], 0})
        speed = 0
    end

    -- pos - block position to stand on; callback (optional) fires on arrival,
    -- fail (optional) when there is no path
    -- units never leave the floor: the hitbox centre stays at this height
    -- (no climbing onto low buildings or onto each other, no falling)
    local height = arena.LEVEL + body:get_size()[2] / 2

    local function keep_height()
        local p = tsf:get_pos()
        if math.abs(p[2] - height) > 1e-3 then
            tsf:set_pos({p[1], height, p[3]})
        end
        local vel = body:get_vel()
        if vel[2] ~= 0 then
            body:set_vel({vel[1], 0, vel[3]})
        end
    end

    -- stuck in or on top of a block (a building placed on the unit, pushed
    -- onto raised stone): step down to the nearest free floor cell, or the
    -- route search can't even start. Units only walk at arena.LEVEL, so the
    -- cell is checked there (not by the current height: a unit bouncing on a
    -- pipe would look like it is in the air)
    local function leave_block()
        local p = tsf:get_pos()
        if building.is_walkable(math.floor(p[1]), arena.LEVEL, math.floor(p[3])) then
            return
        end
        local cell = building.free_cell_near(p, arena.LEVEL, UNSTUCK_RADIUS)
        if cell then
            tsf:set_pos({cell[1] + 0.5, height, cell[3] + 0.5})
        end
    end

    function env.move_to(pos, callback, fail)
        leave_block()
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

    -- turn the model towards pos (e.g. while attacking on the spot)
    function env.face(pos)
        local p = tsf:get_pos()
        local d = vec2.normalize({pos[1] - p[1], pos[3] - p[3]})
        if d[1] == d[1] then -- not NaN
            dir_x, dir_z = d[1], d[2]
        end
    end

    -- current movement direction {x, z}, or nil when standing
    function env.get_move_dir()
        if target and speed > 0.05 then
            return {dir_x, dir_z}
        end
        return nil
    end

    -- current speed as a fraction of the max speed (0..1)
    function env.get_speed_fraction()
        return target and speed / max_speed or 0
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
                if spot and vec2.distance(flat(opos), spot) < 0.75 then -- anywhere in the cell
                    target_taken = true
                end
            end
        end
        return sx * SEPARATION_SPEED, sz * SEPARATION_SPEED, target_taken
    end

    -- anchored: stands still and isn't pushed aside (a sitting mimic);
    -- move orders have to be refused by the unit itself
    local anchored = false
    function env.set_anchored(flag)
        anchored = flag
        if flag then
            env.stop()
        end
    end

    function env.on_physics_update(delta)
        keep_height()
        if anchored then
            halt()
            return
        end
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
        tsf:set_rot(mat4.rotate({0, 1, 0}, yaw + (def.model_yaw or 0)))
        if flash > 0 then
            flash = math.max(0, flash - delta)
            local k = flash / HIT_FLASH
            rig:set_color({
                base_color[1] + (HIT_COLOR[1] - base_color[1]) * k,
                base_color[2] + (HIT_COLOR[2] - base_color[2]) * k,
                base_color[3] + (HIT_COLOR[3] - base_color[3]) * k,
            })
        end
    end

    function env.on_despawn()
        pathfinding.remove_agent(agent)
    end
end

return unit
