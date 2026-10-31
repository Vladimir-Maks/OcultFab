-- Combat: stats (config/combat.json), health of the core and of defensive
-- buildings, what enemies attack, the night spawner and the game over.
--
-- config/combat.json:
--   core.health                    - the core's health
--   units[<entity>].health         - our units (rts/unit takes it from here)
--   eye_tower.*                    - see buildings/eye_tower
--   enemies[<id>]                  - entity, health, speed (blocks/s),
--                                    attack_range (blocks), damage,
--                                    attack_speed (attacks per second)
--   spawn.night_start / night_end  - in-game hours: enemies appear only
--                                    between them (0 = midnight)
--   spawn.enemy                    - which enemy (a key of `enemies`)
--   spawn.interval / group         - every `interval` seconds of the night
--                                    `group` enemies appear (intensity)
--   spawn.max_alive                - no new ones while this many are alive
--   spawn.distance / distance_spread - spawn on dug-out floor at least
--                                    `distance` blocks from any building,
--                                    up to distance + distance_spread from
--                                    the core
--
-- Enemies attack our units, defensive buildings (definition has
-- `defense = true` and is a machine: health lives in its state) and the
-- core. The core at 0 health ends the game (layouts/game_over.xml).
local arena = require "ocult:arena"
local building = require "ocult:rts/building"
local core_site = require "ocult:rts/core_site"
local machines = require "ocult:machines"

local this = {}

this.stats = json.parse(file.read("ocult:config/combat.json"))

local SAVE_FILE = "world:data/ocult/combat.json"
this.GAME_OVER_FILE = "world:data/ocult/game_over" -- start.lua watches it

local core_health = this.stats.core.health
local spawn_timer = 0
local game_over = false

-- enemy uid -> true (registered by the enemy components)
local enemies = {}

function this.register_enemy(uid)
    enemies[uid] = true
end

function this.unregister_enemy(uid)
    enemies[uid] = nil
end

function this.enemy_count()
    local n = 0
    for uid in pairs(enemies) do
        if entities.exists(uid) then
            n = n + 1
        else
            enemies[uid] = nil
        end
    end
    return n
end

-- enemies: list of {uid, pos, comp}
function this.enemies()
    local list = {}
    for uid in pairs(enemies) do
        local e = entities.get(uid)
        if e then
            local comp = e:get_component(e:def_name())
            if comp then
                table.insert(list, {uid = uid, pos = e.transform:get_pos(), comp = comp})
            end
        else
            enemies[uid] = nil
        end
    end
    return list
end

---------------------------------------------------------------- the core

function this.core_health()
    return core_health
end

function this.is_game_over()
    return game_over
end

local function end_game()
    if game_over then
        return
    end
    game_over = true
    hud.open_permanent("ocult:game_over")
end

function this.damage_core(n)
    core_health = math.max(0, core_health - n)
    if core_health == 0 then
        end_game()
    end
end

-- "ОК" in the game over window: start.lua deletes the world and quits
function this.confirm_game_over()
    file.mkdirs("world:data/ocult")
    file.write(this.GAME_OVER_FILE, "")
end

---------------------------------------------------------------- targets

-- building target: {kind = "building", x, y, z, sx, sz, id} (origin, size)
local function building_target(x, y, z, id)
    local sx, _, sz = block.get_size(id)
    return {kind = "building", x = x, y = y, z = z, sx = sx, sz = sz, id = id}
end

-- everything enemies may attack: our units and buildings
-- (list of targets: {kind = "unit", uid, pos} or building targets)
function this.targets()
    local list = {}
    for uid, e in pairs(entities.get_all()) do
        local comp = e:get_component(e:def_name())
        if comp and comp.is_rts_object and not comp.def.enemy and comp.take_damage then
            table.insert(list, {kind = "unit", uid = uid, pos = e.transform:get_pos()})
        end
    end
    local core = core_site.origin()
    if core then
        table.insert(list, building_target(core[1], core[2], core[3],
            block.index(core_site.BLOCK)))
    end
    for _, m in ipairs(machines.all()) do
        local def = building.get_def(m.id)
        if def and def.defense then
            table.insert(list, building_target(m.x, m.y, m.z, m.id))
        end
    end
    return list
end

-- horizontal distance from pos to a target (to the footprint's edge for
-- buildings)
function this.distance(pos, t)
    if t.kind == "unit" then
        return vec2.distance({pos[1], pos[3]}, {t.pos[1], t.pos[3]})
    end
    local dx = math.max(t.x - pos[1], 0, pos[1] - (t.x + t.sx))
    local dz = math.max(t.z - pos[3], 0, pos[3] - (t.z + t.sz))
    return math.sqrt(dx * dx + dz * dz)
end

-- nil if the target is gone
function this.refresh(t)
    if t.kind == "unit" then
        local e = entities.get(t.uid)
        if not e then
            return nil
        end
        t.pos = e.transform:get_pos()
        return t
    end
    if block.get(t.x, t.y, t.z) ~= t.id then
        return nil
    end
    return t
end

function this.damage(t, n)
    if t.kind == "unit" then
        local e = entities.get(t.uid)
        local comp = e and e:get_component(e:def_name())
        if comp and comp.take_damage then
            comp.take_damage(n)
        end
        return
    end
    if block.name(t.id) == core_site.BLOCK then
        this.damage_core(n)
        return
    end
    local def = building.get_def(t.id)
    if def and def.take_damage then
        def.take_damage(building.instance(t.x, t.y, t.z), n)
    end
end

---------------------------------------------------------------- spawning

local function is_night()
    local hour = world.get_day_time() * 24
    local s = this.stats.spawn
    if s.night_start <= s.night_end then
        return hour >= s.night_start and hour < s.night_end
    end
    return hour >= s.night_start or hour < s.night_end -- e.g. 22..4
end
this.is_night = is_night

-- no building block within `radius` of (x, z) on the floor layer
local function far_from_buildings(x, z, radius)
    local y = arena.LEVEL
    for bx = x - radius, x + radius do
        for bz = z - radius, z + radius do
            local id = block.get(bx, y, bz)
            if id > 0 and building.get_def(id) then
                local dx, dz = bx - x, bz - z
                if dx * dx + dz * dz <= radius * radius then
                    return false
                end
            end
        end
    end
    return true
end

-- a dug-out floor cell far enough from the buildings, or nil
local function spawn_cell()
    local s = this.stats.spawn
    local core = core_site.origin()
    local cx, _, cz = arena.center()
    if core then
        cx, cz = core[1] + 1.5, core[3] + 1.5
    end
    for _ = 1, 40 do
        local angle = math.random() * math.pi * 2
        local r = s.distance + math.random() * s.distance_spread
        local x = math.floor(cx + math.cos(angle) * r)
        local z = math.floor(cz + math.sin(angle) * r)
        if arena.inside(x, z) and block.get(x, arena.LEVEL, z) ~= -1
                and building.is_walkable(x, arena.LEVEL, z)
                and far_from_buildings(x, z, s.distance) then
            return {x, arena.LEVEL, z}
        end
    end
    return nil
end

local function spawn_enemy(id)
    local def = this.stats.enemies[id]
    local cell = spawn_cell()
    if not def or not cell then
        return false
    end
    local e = entities.spawn(def.entity, {cell[1] + 0.5, cell[2] + 1, cell[3] + 0.5})
    return e ~= nil
end
this.spawn_enemy = spawn_enemy

function this.update(dt)
    if game_over then
        return
    end
    local s = this.stats.spawn
    if not is_night() then
        spawn_timer = 0
        return
    end
    spawn_timer = spawn_timer - dt
    if spawn_timer > 0 then
        return
    end
    spawn_timer = s.interval
    for _ = 1, s.group do
        if this.enemy_count() >= s.max_alive then
            break
        end
        spawn_enemy(s.enemy)
    end
end

---------------------------------------------------------------- saving

function this.load()
    core_health = this.stats.core.health
    spawn_timer = 0
    game_over = false
    enemies = {}
    if file.exists(SAVE_FILE) then
        local data = json.parse(file.read(SAVE_FILE))
        core_health = data.core_health or core_health
        spawn_timer = data.spawn_timer or 0
    end
end

function this.save()
    file.mkdirs("world:data/ocult")
    file.write(SAVE_FILE, json.tostring({core_health = core_health, spawn_timer = spawn_timer}))
end

-- after loading: the core may have been destroyed when the game closed
function this.check_core()
    if core_health <= 0 then
        end_game()
    end
end

return this
