-- Eye tower "Глазоцвет" (block ocult:eye_tower, 1x1): a defensive building.
-- Shoots the nearest enemy in range it can see (a ray that unmined stone
-- blocks), spending mana per shot. It draws liquid mana itself from the
-- nearest tank within its attack range (no pipes). Enemies attack it; at 0
-- health it's destroyed. The range is drawn on the ground while placing it
-- and while it's selected (`range_marker`).
-- Stats: config/combat.json, eye_tower.
-- The plant with the eye is the entity ocult:eye_head (not saved, spawned
-- again by update), turning towards the target.
local machines = require "ocult:machines"
local combat = require "ocult:combat"
local liquids = require "ocult:liquids"
local defense = require "ocult:defense"

local STATS = combat.stats.eye_tower
local MANA = "mana"
local HEAD_ENTITY = "ocult:eye_head"
local BEAM_ENTITY = "ocult:beam"
local EYE_HEIGHT = 1.2 -- blocks above the floor: where the ray starts

local this = defense.extend({
    title = "Глазоцвет",
    preview = {model = "ocult_eye_tower_full", center = {0.5, 0.6, 0.5}},
    commands = {
        {id = "demolish", label = "Разр.", hint = "Разрушить глазоцвет", slot = 12},
    },
    range_marker = STATS.range,
    vision = 6,
}, STATS.health)

function this.new_state()
    return {mana = 0, health = STATS.health}
end

function this.description(self)
    local state = machines.of(self)
    local text = string.format("Стреляет во врагов в радиусе %d блоков: %d урона "
        .. "за выстрел, %d мл маны. Ману берет сам из ближайшей цистерны "
        .. "в этом радиусе.\n\n",
        STATS.range, STATS.damage, STATS.mana_per_shot)
    if not state then
        return text
    end
    return text .. string.format("Прочность: %d/%d\nМана: %d/%d мл",
        state.health, STATS.health, state.mana, STATS.mana_capacity)
end

function this.update(self, state, dt)
    local head = defense.top(self, state, HEAD_ENTITY)
    defense.draw_liquid(self, state, "mana", MANA, STATS.mana_capacity, STATS.range, dt)
    local eye = {self.x + 0.5, self.y + EYE_HEIGHT, self.z + 0.5}
    local enemy, aim = defense.find_target(eye, STATS.range)
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
