-- "ПЛОХИЕ КОСТИ" (block ocult:skull_altar, 1x1): a defensive building built
-- by a cultist's sacrifice. Throws the skull from its model at the nearest
-- enemy it can see; the skull deals splash damage where it lands (square of
-- `splash` blocks). Every shot costs molten rubinyte, drawn from the nearest
-- tank within range (no pipes). Stats: config/combat.json, skull_altar.
-- The banner and the skull are the entity ocult:skull_altar_top (idle and
-- reload animations).
local machines = require "ocult:machines"
local combat = require "ocult:combat"
local defense = require "ocult:defense"

local STATS = combat.stats.skull_altar
local RUBINYTE = "rubinyte"
local TOP_ENTITY = "ocult:skull_altar_top"
local PROJECTILE = "ocult:skull_projectile"
local SKULL_HEIGHT = 0.85 -- blocks above the floor: the skull on the pedestal

local this = defense.extend({
    title = "ПЛОХИЕ КОСТИ",
    preview = {model = "ocult_skull_altar_full", center = {0.5, 1.0, 0.5}},
    commands = {
        {id = "demolish", label = "Разр.", hint = "Разрушить ПЛОХИЕ КОСТИ", slot = 12},
    },
    range_marker = STATS.range,
    vision = 6,
}, STATS.health)

function this.new_state()
    return {rubinyte = 0, health = STATS.health}
end

function this.description(self)
    local state = machines.of(self)
    local text = string.format("Метает череп во врагов в радиусе %d блоков: %d урона "
        .. "всем в квадрате %dx%d, %d мл расплавленного рубинита за выстрел. "
        .. "Рубинит берет сам из ближайшей цистерны в этом радиусе.\n\n",
        STATS.range, STATS.damage, STATS.splash, STATS.splash, STATS.rubinyte_per_shot)
    if not state then
        return text
    end
    return text .. string.format("Прочность: %d/%d\nРубинит: %d/%d мл",
        state.health, STATS.health, state.rubinyte, STATS.liquid_capacity)
end

function this.update(self, state, dt)
    local top = defense.top(self, state, TOP_ENTITY)
    defense.draw_liquid(self, state, "rubinyte", RUBINYTE, STATS.liquid_capacity,
        STATS.range, dt)
    state._cooldown = math.max(0, (state._cooldown or 0) - dt)
    if state._cooldown > 0 or state.rubinyte < STATS.rubinyte_per_shot then
        return
    end
    local skull = {self.x + 0.5, self.y + SKULL_HEIGHT, self.z + 0.5}
    local enemy, aim = defense.find_target(skull, STATS.range)
    if not enemy then
        return
    end
    state._cooldown = STATS.shot_interval
    state.rubinyte = state.rubinyte - STATS.rubinyte_per_shot
    top:get_component(TOP_ENTITY).shoot()
    entities.spawn(PROJECTILE, skull, {ocult__skull_projectile = {
        from = skull, to = aim, speed = STATS.projectile_speed,
        damage = STATS.damage, splash = STATS.splash,
    }})
end

return this
