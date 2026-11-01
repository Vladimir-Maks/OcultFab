-- Shared parts of defensive buildings (buildings/eye_tower,
-- buildings/skull_altar): drawing liquid from tanks nearby, picking a target
-- in sight, the entity on top, taking damage.
local building = require "ocult:rts/building"
local machines = require "ocult:machines"
local combat = require "ocult:combat"

local this = {}

local DRAW_INTERVAL = 0.5 -- seconds between draws from a tank
local DRAW_AMOUNT = 50    -- ml drawn at a time (at most)
local AIM_HEIGHT = 0.6    -- aim at this height above the enemy's feet

-- distance from (x, z) to the footprint of a building at origin m
local function distance_to(x, z, m)
    local sx, _, sz = block.get_size(m.id)
    local dx = math.max(m.x - x, 0, x - (m.x + sx))
    local dz = math.max(m.z - z, 0, z - (m.z + sz))
    return math.sqrt(dx * dx + dz * dz)
end

-- tops up state[field] (ml of `liquid`, up to `capacity`) from the nearest
-- tank with that liquid within `range` of the 1x1 building self
function this.draw_liquid(self, state, field, liquid, capacity, range, dt)
    state._draw_timer = (state._draw_timer or 0) - dt
    local need = capacity - state[field]
    if state._draw_timer > 0 or need <= 0 then
        return
    end
    state._draw_timer = DRAW_INTERVAL
    local cx, cz = self.x + 0.5, self.z + 0.5
    local best, best_d
    for _, m in ipairs(machines.all()) do
        local def = building.get_def(m.id)
        local tank = def and def.draw_liquid and machines.get(m.x, m.y, m.z)
        if tank and tank.liquid == liquid and tank.ml > 0 then
            local d = distance_to(cx, cz, m)
            if d <= range and (not best or d < best_d) then
                best, best_d = m, d
            end
        end
    end
    if best then
        local def = building.get_def(best.id)
        state[field] = state[field] + def.draw_liquid(best,
            machines.get(best.x, best.y, best.z), liquid, math.min(need, DRAW_AMOUNT))
    end
end

-- blocks rays ignore: buildings (pipes, other towers...)
local see_through

-- the nearest enemy within range seen from `eye` (unmined stone blocks the
-- view): {uid, pos, comp} and the aim point; or nil
function this.find_target(eye, range)
    if not see_through then
        see_through = {}
        for _, name in ipairs(building.block_names()) do
            table.insert(see_through, block.index(name))
        end
    end
    local best, best_d, best_aim
    for _, enemy in ipairs(combat.enemies()) do
        local aim = {enemy.pos[1], enemy.pos[2] - 0.6 + AIM_HEIGHT, enemy.pos[3]}
        local dir = vec3.sub(aim, eye)
        local d = vec3.length(dir)
        if d <= range and (not best or d < best_d) then
            local hit = d > 0 and block.raycast(eye, vec3.normalize(dir), d, nil, see_through)
            if not hit then
                best, best_d, best_aim = enemy, d, aim
            end
        end
    end
    return best, best_aim
end

-- the entity standing on the building (not saved: spawned again when gone);
-- its uid lives in state._top_uid
function this.top(self, state, entity_name)
    local e = state._top_uid and entities.get(state._top_uid)
    if not e then
        e = entities.spawn(entity_name, {self.x + 0.5, self.y, self.z + 0.5})
        state._top_uid = e:get_uid()
    end
    return e
end

function this.remove_top(state)
    local e = state._top_uid and entities.get(state._top_uid)
    if e then
        e:despawn()
    end
    state._top_uid = nil
end

-- adds the usual parts to a defensive building definition: machine with
-- health (`max_health`), demolish command, take_damage, on_remove
function this.extend(def, max_health)
    def.machine = true
    def.defense = true -- enemies attack it
    def.on_remove = this.remove_top

    function def.command_demolish(self)
        local state = machines.of(self)
        if state then
            this.remove_top(state)
        end
        building.demolish(self)
    end

    -- enemies hit it (see ocult:combat)
    function def.take_damage(self, n)
        local state = machines.of(self)
        if not state then
            return
        end
        state.health = math.max(0, (state.health or max_health) - n)
        if state.health == 0 then
            def.command_demolish(self)
        end
    end
    return def
end

return this
