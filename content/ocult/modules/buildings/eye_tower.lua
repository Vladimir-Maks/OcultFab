-- Eye tower "Глазоцвет" (block ocult:eye_tower, 1x1): a defensive building.
-- Shoots the nearest enemy in range it can see (a ray that unmined stone
-- blocks), spending mana per shot. It draws liquid mana itself from the
-- nearest tank within its attack range (no pipes). Enemies attack it; at 0
-- health it's destroyed. The range is drawn on the ground while placing it
-- and while it's selected (`range_marker`).
-- Stats: config/combat.json, eye_tower.
-- The plant with the eye is the entity ocult:eye_head (not saved, spawned
-- again by update), turning towards the target.
local building = require "ocult:rts/building"
local machines = require "ocult:machines"
local combat = require "ocult:combat"
local liquids = require "ocult:liquids"

local STATS = combat.stats.eye_tower
local MANA = "mana"
local HEAD_ENTITY = "ocult:eye_head"
local BEAM_ENTITY = "ocult:beam"
local EYE_HEIGHT = 1.2 -- blocks above the floor: where the ray starts
local AIM_HEIGHT = 0.6 -- aim at this height above the enemy's feet
local DRAW_INTERVAL = 0.5 -- seconds between draws from a tank
local DRAW_AMOUNT = 50    -- ml drawn at a time (at most)

local this = {
    title = "Глазоцвет",
    preview = {model = "ocult_eye_tower_full", center = {0.5, 0.6, 0.5}},
    commands = {
        {id = "demolish", label = "Разр.", hint = "Разрушить глазоцвет", slot = 12},
    },
    machine = true,
    defense = true, -- enemies attack it
    range_marker = STATS.range,
    vision = 6,
}

function this.new_state()
    return {mana = 0, health = STATS.health}
end

function this.description(self)
    local state = machines.of(self)
    local text = string.format("Стреляет во врагов в радиусе %d блоков: %d урона "
        .. "за выстрел, %d мл маны. Ману берёт сам из ближайшей цистерны "
        .. "в этом радиусе.\n\n",
        STATS.range, STATS.damage, STATS.mana_per_shot)
    if not state then
        return text
    end
    return text .. string.format("Прочность: %d/%d\nМана: %d/%d мл",
        state.health, STATS.health, state.mana, STATS.mana_capacity)
end

local function remove_head(state)
    local e = state._head_uid and entities.get(state._head_uid)
    if e then
        e:despawn()
    end
    state._head_uid = nil
end
this.on_remove = remove_head

function this.command_demolish(self)
    local state = machines.of(self)
    if state then
        remove_head(state)
    end
    building.demolish(self)
end

-- enemies hit it (see ocult:combat)
function this.take_damage(self, n)
    local state = machines.of(self)
    if not state then
        return
    end
    state.health = math.max(0, state.health - n)
    if state.health == 0 then
        this.command_demolish(self)
    end
end

-- distance from (x, z) to the footprint of a building at origin m
local function distance_to(x, z, m)
    local sx, _, sz = block.get_size(m.id)
    local dx = math.max(m.x - x, 0, x - (m.x + sx))
    local dz = math.max(m.z - z, 0, z - (m.z + sz))
    return math.sqrt(dx * dx + dz * dz)
end

-- tops up the mana from the nearest tank with mana within range
local function draw_mana(self, state, dt)
    state._draw_timer = (state._draw_timer or 0) - dt
    local need = STATS.mana_capacity - state.mana
    if state._draw_timer > 0 or need <= 0 then
        return
    end
    state._draw_timer = DRAW_INTERVAL
    local cx, cz = self.x + 0.5, self.z + 0.5
    local best, best_d
    for _, m in ipairs(machines.all()) do
        local def = building.get_def(m.id)
        local tank = def and def.draw_liquid and machines.get(m.x, m.y, m.z)
        if tank and tank.liquid == MANA and tank.ml > 0 then
            local d = distance_to(cx, cz, m)
            if d <= STATS.range and (not best or d < best_d) then
                best, best_d = m, d
            end
        end
    end
    if best then
        local def = building.get_def(best.id)
        state.mana = state.mana + def.draw_liquid(best,
            machines.get(best.x, best.y, best.z), MANA, math.min(need, DRAW_AMOUNT))
    end
end

-- blocks the ray ignores: buildings (pipes, other towers...)
local see_through

-- the nearest enemy in range and in sight: {uid, pos, comp} and the aim point
local function find_target(eye)
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
        if d <= STATS.range and (not best or d < best_d) then
            local hit = d > 0 and block.raycast(eye, vec3.normalize(dir), d, nil, see_through)
            if not hit then
                best, best_d, best_aim = enemy, d, aim
            end
        end
    end
    return best, best_aim
end

function this.update(self, state, dt)
    local head = state._head_uid and entities.get(state._head_uid)
    if not head then
        head = entities.spawn(HEAD_ENTITY, {self.x + 0.5, self.y, self.z + 0.5})
        state._head_uid = head:get_uid()
    end
    draw_mana(self, state, dt)
    local eye = {self.x + 0.5, self.y + EYE_HEIGHT, self.z + 0.5}
    local enemy, aim = find_target(eye)
    head:get_component(HEAD_ENTITY).aim = aim
    state._cooldown = math.max(0, (state._cooldown or 0) - dt)
    if not enemy or state._cooldown > 0 or state.mana < STATS.mana_per_shot then
        return
    end
    state._cooldown = STATS.shot_interval
    state.mana = state.mana - STATS.mana_per_shot
    head:get_component(HEAD_ENTITY).shoot()
    entities.spawn(BEAM_ENTITY, eye, {ocult__beam = {
        from = eye, to = aim, color = liquids.color(MANA),
    }})
    if enemy.comp.take_damage then
        enemy.comp.take_damage(STATS.damage)
    end
end

return this
