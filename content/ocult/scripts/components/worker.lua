-- Cultist: basic worker unit. Carries resources lying on the ground to the
-- core or to the nearest sitting mimic, one item per trip, and builds: "Стройка" opens the build menu
-- (extractor; altar - the cultist sacrifices itself to become one).
-- RMB on an item (or right next to it) = gather around it.
-- RMB on an enemy = attack it until it dies (stats: config/combat.json,
-- units["ocult:worker"]).
local unit = require "ocult:rts/unit"
local building = require "ocult:rts/building"
local arena = require "ocult:arena"
local drops = require "ocult:drops"
local economy = require "ocult:economy"
local core_site = require "ocult:rts/core_site"
local fog = require "ocult:fog"
local debug_flags = require "ocult:debug"
local combat = require "ocult:combat"
local command_panel = require "ocult:rts/command_panel"
local sounds = require "ocult:sounds"

local GATHER_RADIUS = 15 -- RMB on an item: gather within this many blocks of it
local STATS = combat.stats.units["ocult:worker"]
local CHASE_INTERVAL = 0.5 -- seconds between route updates while chasing
local MIMIC = "ocult:mimic"
local MIMIC_REACH = 2.5  -- hands an item to a mimic from this close

-- costs in items stored in the core
local ALTAR_COST = {["ocult:stone.item"] = 25, ["ocult:mana_ore.item"] = 1}
local EXTRACTOR_COST = {
    ["ocult:stone.item"] = 10,
    ["ocult:iron_ore.item"] = 10,
    ["ocult:mana_ore.item"] = 1,
}
-- placeholder prices
local PUMP_COST = {["ocult:stone.item"] = 10, ["ocult:iron_ore.item"] = 5}
local CAULDRON_COST = {["ocult:stone.item"] = 20, ["ocult:iron_ore.item"] = 5}
local TANK_COST = {["ocult:stone.item"] = 15, ["ocult:iron_ore.item"] = 5}
local EYE_TOWER_COST = {["ocult:stone.item"] = 20, ["ocult:mana_ore.item"] = 2}
local SKULL_ALTAR_COST = {
    ["ocult:refined_gold.item"] = 3,
    ["ocult:oil.item"] = 2,
    ["ocult:stone.item"] = 20,
    ["ocult:rubinyte_ore.item"] = 1,
}

unit.extend(this, {
    title = "Прихвостень",
    description = function(self)
        return "Прихвостень для работы.\nНенавидит запах винограда...\n\n"
            .. self.health_text()
    end,
    health = combat.stats.units["ocult:worker"].health,
    select_sound = "cultist",
    preview = {model = "ocult_cultist_full", center = {0, 0, 0}},
    commands = {
        {id = "stop", label = "Стоп", hint = "Остановиться", slot = 2},
        {id = "gather", label = "Сбор", slot = 3, target = "zone",
         hint = "Собрать ресурсы: ЛКМ по ресурсу или выделить область"},
        {id = "build", label = "Стройка", hint = "Меню построек", slot = 9,
         submenu = "build"},
        {id = "defense", label = "Защита", hint = "Защитные сооружения", slot = 10,
         submenu = "defense"},
        -- build menu
        {id = "extractor", label = "Экстр.", menu = "build", slot = 1,
         hint = "Построить экстрактор", place = "ocult:extractor",
         cost = EXTRACTOR_COST},
        {id = "altar", label = "Алтарь", menu = "build", slot = 2,
         hint = "Принести себя в жертву и стать алтарем", place = "ocult:altar",
         cost = ALTAR_COST},
        {id = "pump", label = "Помпа", menu = "build", slot = 3,
         hint = "Построить помпу предметов: подает ресурс со склада",
         place = "ocult:pump", cost = PUMP_COST, show_ports = true},
        {id = "cauldron", label = "Тигель", menu = "build", slot = 4,
         hint = "Построить тигель: плавит ресурсы в жидкость",
         place = "ocult:cauldron", cost = CAULDRON_COST, show_ports = true},
        {id = "tank", label = "Цист.", menu = "build", slot = 5,
         hint = "Построить цистерну для жидкости", place = "ocult:tank",
         cost = TANK_COST, show_ports = true},
        -- defense menu
        {id = "eye_tower", label = "Глаз", menu = "defense", slot = 1,
         hint = "Построить глазоцвет: стреляет по врагам, питается маной из цистерны",
         place = "ocult:eye_tower", cost = EYE_TOWER_COST},
        {id = "skull_altar", label = "Кости", menu = "defense", slot = 2,
         hint = "Принести себя в жертву и стать ПЛОХИМИ КОСТЯМИ: метает череп, "
             .. "питается расплавленным рубинитом из цистерны",
         place = "ocult:skull_altar", cost = SKULL_ALTAR_COST},
    },
})

local uid = entity:get_uid()
local zone       -- {x0, z0, x1, z1} while gathering
local last_zone  -- the last gathering zone (to go back to after a manual delivery)
local busy = false -- walking somewhere as part of gathering
local claimed    -- uid of the drop we're walking to
local carried -- name of the item in hands, or nil

local function release_claim()
    if claimed then
        local comp = drops.get(claimed)
        if comp and comp.claimed_by == uid then
            comp.claimed_by = nil
        end
        claimed = nil
    end
end

-- the carried item is shown in front of the cultist (skeleton bone "item")
local rig = entity.skeleton
local hand = rig:index("item")
local arms = {rig:index("arm_l"), rig:index("arm_r")}

-- arms stretch forward while carrying (rotation about X at the shoulder)
local ARMS_CARRY_ANGLE = 85 -- degrees
local ARMS_SPEED = 8        -- higher = faster raise/lower
local arms_angle = 0

carried = SAVED_DATA.carried

local function show_carried()
    if not hand then
        return
    end
    if carried then
        rig:set_model(hand, item.model_name(item.index(carried)))
    else
        rig:set_model(hand) -- back to no model
    end
end
show_carried()

function on_save()
    SAVED_DATA.carried = carried
end

local enemy_uid      -- the enemy being attacked
local chase_timer = 0
local attack_timer = 0

local function stop_gathering()
    release_claim()
    zone = nil
    busy = false
    enemy_uid = nil
end

-- the enemy's entity, or nil if it's dead
local function enemy_entity()
    local e = enemy_uid and entities.get(enemy_uid)
    local comp = e and unit.get(enemy_uid)
    if comp and comp.def.enemy then
        return e, comp
    end
    enemy_uid = nil
    return nil
end

local function fight(dt)
    local e, comp = enemy_entity()
    if not e then
        stop()
        return
    end
    local epos = e.transform:get_pos()
    local pos = get_pos()
    attack_timer = math.max(0, attack_timer - dt)
    if vec2.distance({pos[1], pos[3]}, {epos[1], epos[3]}) <= STATS.attack_range then
        stop()
        face(epos)
        if attack_timer == 0 then
            attack_timer = 1 / STATS.attack_speed
            comp.take_damage(STATS.damage)
            sounds.damage("cultist", pos)
        end
        return
    end
    chase_timer = chase_timer - dt
    if chase_timer <= 0 then
        chase_timer = CHASE_INTERVAL
        move_to({math.floor(epos[1]), arena.LEVEL, math.floor(epos[3])})
    end
end

local function in_zone(pos)
    return pos[1] >= zone[1] and pos[1] <= zone[3] and pos[3] >= zone[2] and pos[3] <= zone[4]
end

local function next_drop()
    return drops.nearest_free(get_pos(), function(pos)
        return in_zone(pos) and not fog.is_hidden(pos[1], pos[3])
    end)
end

-- a sitting mimic that takes items, or nil
local function receiving_mimic(mimic_uid)
    local e = entities.get(mimic_uid)
    if not e or e:def_name() ~= MIMIC then
        return nil
    end
    local comp = unit.get(mimic_uid)
    return comp and comp.accepts_items() and e or nil
end

local function cell_of(pos)
    return {math.floor(pos[1]), arena.LEVEL, math.floor(pos[3])}
end

-- the free cell next to a sitting mimic nearest to us (its own cell is
-- walked around, see components/mimic)
local function mimic_cell(e)
    local c = cell_of(e.transform:get_pos())
    return building.ring_cell(c, 1, 1, get_pos())
end

-- the nearest place to hand the item in: a sitting mimic with free space
-- or the core (if it isn't full). Returns the cell to walk to and the mimic
-- uid (nil = core); nil if there is nowhere to put it
local function drop_off()
    local pos = get_pos()
    local function dist(cell)
        return vec2.distance({pos[1], pos[3]}, {cell[1] + 0.5, cell[3] + 0.5})
    end
    local fits = carried and economy.fits(carried) or not economy.is_full()
    local best = fits and core_site.access_cell(pos) or nil
    local best_d = best and dist(best)
    local best_uid
    for mimic_uid in pairs(entities.get_all()) do
        local e = receiving_mimic(mimic_uid)
        if e then
            local cell = mimic_cell(e)
            local d = cell and dist(cell)
            if d and (not best_d or d < best_d) then
                best, best_d, best_uid = cell, d, mimic_uid
            end
        end
    end
    return best, best_uid
end

-- to: nil - the nearest drop-off, "core", or a mimic uid
local function deliver(to)
    local cell, mimic_uid
    if to == "core" then
        cell = core_site.access_cell(get_pos())
    elseif to then
        mimic_uid = to
        local e = receiving_mimic(mimic_uid)
        cell = e and mimic_cell(e)
    else
        cell, mimic_uid = drop_off()
    end
    if not cell then
        stop_gathering()
        return
    end
    busy = true
    move_to(cell, function()
        busy = false
        if mimic_uid then
            -- it may have stood up or filled up meanwhile: then the next
            -- think() picks another drop-off
            local e = receiving_mimic(mimic_uid)
            if e and vec3.distance(e.transform:get_pos(), get_pos()) < MIMIC_REACH
                    and economy.add_to_mimic(mimic_uid, carried, 1) == 1 then
                carried = nil
                show_carried()
            end
        elseif economy.add(carried, 1) == 1 then
            carried = nil
            show_carried()
        else
            stop_gathering() -- storage is full: keep it in the hands
        end
    end, stop_gathering)
end

local function pick_up(drop)
    drop.comp.claimed_by = uid
    claimed = drop.uid
    busy = true
    move_to({math.floor(drop.pos[1]), arena.LEVEL, math.floor(drop.pos[3])}, function()
        busy = false
        local comp = drops.get(claimed)
        if comp and comp.claimed_by == uid then
            comp.claimed_by = nil -- the rest of the stack is free again
            carried = drops.take_one(claimed)
            show_carried()
        end
        claimed = nil
    end, function()
        -- unreachable (e.g. behind unmined stone): skip it for now
        busy = false
        release_claim()
        stop_gathering()
    end)
end

local function think()
    if carried then
        deliver()
        return
    end
    if not drop_off() then
        stop_gathering() -- the core and the mimics are full
        return
    end
    local drop = next_drop()
    if drop then
        pick_up(drop)
    else
        stop_gathering() -- nothing left in the zone
    end
end

function on_update(tps)
    if enemy_uid then
        fight(1 / tps)
    elseif zone and not busy then
        think()
    end
end

local base_on_despawn = on_despawn
function on_despawn()
    release_claim()
    base_on_despawn()
end

-- carrying an item: others give way in narrow spots (see rts/unit)
function traffic_priority()
    return carried and 1 or 0
end

local function zone_around(p)
    return {p[1] - GATHER_RADIUS, p[3] - GATHER_RADIUS, p[1] + GATHER_RADIUS, p[3] + GATHER_RADIUS}
end

local base_on_order = on_order
-- target_block: {x, y, z} of the clicked block, if any
function on_order(pos, target_uid, target_block)
    stop_gathering()
    local enemy = target_uid and unit.get(target_uid)
    if enemy and enemy.def.enemy then
        enemy_uid = target_uid
        chase_timer = 0
        return
    end
    local drop = target_uid and drops.get(target_uid)
    if drop then
        command_gather(zone_around(entities.get(target_uid).transform:get_pos()))
        return
    end
    -- RMB on the core or a sitting mimic with an item in hands: hand it in,
    -- then keep gathering
    local mimic = carried and target_uid and receiving_mimic(target_uid)
    if mimic or (carried and target_block
            and block.name(block.get(unpack(target_block))) == core_site.BLOCK) then
        stop()
        zone = last_zone or zone_around(get_pos())
        deliver(mimic and target_uid or "core")
        return
    end
    base_on_order(pos, target_uid)
end

function command_stop()
    stop_gathering()
    stop()
end

-- zone = {x0, z0, x1, z1} in world coords
function command_gather(new_zone)
    stop_gathering()
    stop()
    zone = new_zone
    last_zone = new_zone
end

-- checks the price, walks to `stand` and pays only there, when the
-- building is actually placed (the stock may have changed on the way)
local function build(block_name, origin, cost, stand, sacrifice)
    if debug_flags.free_build then
        cost = {}
    end
    if not economy.can_afford(cost) then
        return "Не хватает: " .. economy.cost_text(cost)
    end
    stop_gathering()
    move_to(stand, function()
        if not building.can_place(block_name, origin) then
            command_panel.notify("Место для стройки занято")
        elseif not economy.spend(cost) then
            command_panel.notify("Не хватает: " .. economy.cost_text(cost))
        else
            building.place(block_name, origin)
            if sacrifice then
                remove()
            end
        end
    end, function()
        command_panel.notify("Не подойти к месту стройки")
    end)
end

-- the cultist stands in the middle of the spot and becomes the altar
function command_altar(origin)
    return build("ocult:altar", origin, ALTAR_COST,
        building.center_cell("ocult:altar", origin), true)
end

-- the cultist becomes the altar, like with ocult:altar
function command_skull_altar(origin)
    return build("ocult:skull_altar", origin, SKULL_ALTAR_COST,
        building.center_cell("ocult:skull_altar", origin), true)
end

-- builds from the edge of the spot, so it isn't walled in
local function build_from_edge(block_name, origin, cost)
    local sx, _, sz = block.get_size(block.index(block_name))
    local stand = building.ring_cell(origin, sx, sz, get_pos())
    if not stand then
        return "Не подойти к месту стройки"
    end
    return build(block_name, origin, cost, stand, false)
end

function command_extractor(origin)
    return build_from_edge("ocult:extractor", origin, EXTRACTOR_COST)
end

function command_pump(origin)
    return build_from_edge("ocult:pump", origin, PUMP_COST)
end

function command_cauldron(origin)
    return build_from_edge("ocult:cauldron", origin, CAULDRON_COST)
end

function command_tank(origin)
    return build_from_edge("ocult:tank", origin, TANK_COST)
end

function command_eye_tower(origin)
    return build_from_edge("ocult:eye_tower", origin, EYE_TOWER_COST)
end

local base_on_render = on_render
function on_render(delta)
    base_on_render(delta)
    local target = carried and ARMS_CARRY_ANGLE or 0
    arms_angle = arms_angle + (target - arms_angle) * (1 - math.exp(-ARMS_SPEED * delta))
    local pose = mat4.rotate({1, 0, 0}, arms_angle)
    for _, index in ipairs(arms) do
        rig:set_matrix(index, pose)
    end
end
