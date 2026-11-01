-- Combat: stats (config/combat.json), health of the core and of defensive
-- buildings, what enemies attack, the night spawner and the game over.
--
-- config/combat.json:
--   core.health                    - the core's health
--   units[<entity>].health         - our units (rts/unit takes it from here)
--   eye_tower.*                    - see buildings/eye_tower
--   enemies[<id>]                  - entity, health, speed (blocks/s),
--                                    attack_range (blocks), damage,
--                                    attack_speed (attacks per second),
--                                    cost (spawn points), loot: list of
--                                    {item, chance 0..1, count} dropped on
--                                    death (rts/enemy), min_night: waves
--                                    have it only from this night on
--                                    (nights are counted from 1, saved)
--   spawn.night_start / night_end  - in-game hours: waves come only
--                                    between them (0 = midnight)
--   spawn.wave_interval_min / max  - in-game minutes: when the night starts
--                                    (and after every wave) the time to the
--                                    next wave is picked at random in this
--                                    range
--   spawn.points_per_minute        - a wave gets this many spawn points per
--                                    in-game minute waited; they're spent on
--                                    random enemies (enemies[].cost) until
--                                    nothing more is affordable
--   spawn.spawn_interval_ticks     - world ticks between enemies of a wave
--   spawn.max_alive                - a safety cap: the wave waits while this
--                                    many enemies are alive
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

local function spawn_at(id, cell)
    local def = this.stats.enemies[id]
    if not def then
        return false
    end
    return entities.spawn(def.entity, {cell[1] + 0.5, cell[2] + 0.5, cell[3] + 0.5}) ~= nil
end

-- one enemy anywhere the spawner may put it; false if there's no place
function this.spawn_enemy(id)
    local cell = spawn_cell()
    return cell ~= nil and spawn_at(id, cell)
end

-- a walkable cell within 3 blocks of the wave's spot (they come as a crowd)
local function near(base)
    for _ = 1, 10 do
        local x = base[1] + math.random(-3, 3)
        local z = base[3] + math.random(-3, 3)
        if building.is_walkable(x, base[2], z) then
            return {x, base[2], z}
        end
    end
    return base
end

local MINUTES_PER_DAY = 24 * 60

local night_number = 0 -- nights begun since the world was created
local was_night = false
local next_wave_in -- in-game minutes from the timer start to the next wave
local waited = 0   -- in-game minutes since the timer started
local queue = {}   -- enemy ids of the wave still to spawn
local wave_spot    -- cell the current wave comes from
local queue_timer = 0
local last_day_time

local function roll_wave_time()
    local s = this.stats.spawn
    next_wave_in = s.wave_interval_min
        + math.random() * (s.wave_interval_max - s.wave_interval_min)
    waited = 0
end

-- random enemies for `points` spawn points: list of ids
function this.compose_wave(points)
    local list = {}
    while true do
        local affordable = {}
        for id, def in pairs(this.stats.enemies) do
            if def.cost and def.cost > 0 and def.cost <= points
                    and night_number >= (def.min_night or 1) then
                table.insert(affordable, id)
            end
        end
        if #affordable == 0 then
            return list
        end
        local id = affordable[math.random(#affordable)]
        table.insert(list, id)
        points = points - this.stats.enemies[id].cost
    end
end

-- queues a wave worth `points`; returns how many enemies it has
function this.start_wave(points)
    local list = this.compose_wave(points)
    for _, id in ipairs(list) do
        table.insert(queue, id)
    end
    wave_spot = nil
    return #list
end

-- debug: drops the enemies of the wave not spawned yet
function this.clear_queue()
    queue = {}
end

-- debug: removes all enemies and the queued rest of the wave; returns how
-- many were alive
function this.kill_all()
    queue = {}
    local n = 0
    for _, e in ipairs(this.enemies()) do
        e.comp.remove()
        n = n + 1
    end
    return n
end

-- in-game minutes left of the current night (0 by day)
local function night_left()
    if not is_night() then
        return 0
    end
    local end_time = this.stats.spawn.night_end / 24
    return ((end_time - world.get_day_time()) % 1) * MINUTES_PER_DAY
end

-- number of the current (or last) night, from 1; 0 before the first one
function this.night()
    return night_number
end

-- in-game minutes left to the next wave, or nil: no wave tonight (by day,
-- or the rolled time falls after dawn, when waves are called off)
function this.next_wave_eta()
    if not next_wave_in then
        return nil
    end
    local eta = math.max(0, next_wave_in - waited)
    if eta > night_left() then
        return nil
    end
    return eta
end

-- real seconds to the next wave, or nil (see next_wave_eta). The engine
-- advances the time of day by delta * speed / 1440 (World::updateTimers):
-- at speed 1 an in-game minute is one real second
function this.next_wave_seconds()
    local eta = this.next_wave_eta()
    local speed = world.get_day_time_speed()
    if not eta or speed <= 0 then
        return nil
    end
    return eta / speed
end

function this.queued()
    return #queue
end

-- spawns the next enemy of the queue every spawn_interval_ticks
local function spawn_from_queue()
    if #queue == 0 then
        return
    end
    queue_timer = queue_timer - 1
    if queue_timer > 0 or this.enemy_count() >= this.stats.spawn.max_alive then
        return
    end
    queue_timer = this.stats.spawn.spawn_interval_ticks
    wave_spot = wave_spot or spawn_cell()
    if not wave_spot then
        return -- no place yet: try again later
    end
    if spawn_at(queue[1], near(wave_spot)) then
        table.remove(queue, 1)
    end
end

function this.update(dt)
    if game_over then
        return
    end
    local t = world.get_day_time()
    -- in-game minutes since the last tick (the time of day wraps at 1)
    local minutes = last_day_time and ((t - last_day_time) % 1) * MINUTES_PER_DAY or 0
    last_day_time = t
    local night = is_night()
    if night and not was_night then
        night_number = night_number + 1
    end
    was_night = night
    if night then
        if not next_wave_in then
            roll_wave_time()
        else
            waited = waited + minutes
            if waited >= next_wave_in then
                this.start_wave(math.floor(waited * this.stats.spawn.points_per_minute))
                roll_wave_time()
            end
        end
    else
        next_wave_in = nil -- a wave not come by dawn is called off
    end
    spawn_from_queue()
end

---------------------------------------------------------------- saving

function this.load()
    core_health = this.stats.core.health
    game_over = false
    enemies = {}
    next_wave_in, waited, queue, wave_spot, last_day_time = nil, 0, {}, nil, nil
    night_number, was_night = 0, false
    if file.exists(SAVE_FILE) then
        local data = json.parse(file.read(SAVE_FILE))
        core_health = data.core_health or core_health
        next_wave_in = data.next_wave_in
        waited = data.waited or 0
        queue = data.queue or {}
        night_number = data.night or 0
        was_night = data.was_night or false
    end
end

function this.save()
    file.mkdirs("world:data/ocult")
    file.write(SAVE_FILE, json.tostring({
        core_health = core_health,
        next_wave_in = next_wave_in,
        waited = waited,
        queue = queue,
        night = night_number,
        was_night = was_night,
    }))
end

-- after loading: the core may have been destroyed when the game closed
function this.check_core()
    if core_health <= 0 then
        end_game()
    end
end

return this
