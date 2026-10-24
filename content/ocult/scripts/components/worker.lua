-- Cultist: basic worker unit. Carries resources lying on the ground to the
-- core, one item per trip, and builds: "Стройка" opens the build menu
-- (extractor; altar - the cultist sacrifices itself to become one).
-- RMB on an item (or right next to it) = gather around it.
local unit = require "ocult:rts/unit"
local building = require "ocult:rts/building"
local arena = require "ocult:arena"
local drops = require "ocult:drops"
local economy = require "ocult:economy"
local core_site = require "ocult:rts/core_site"

local GATHER_RADIUS = 15 -- RMB on an item: gather within this many blocks of it

-- costs in items stored in the core
local ALTAR_COST = {["ocult:stone.item"] = 25, ["ocult:mana_ore.item"] = 1}
local EXTRACTOR_COST = {
    ["ocult:stone.item"] = 10,
    ["ocult:iron_ore.item"] = 10,
    ["ocult:mana_ore.item"] = 1,
}

unit.extend(this, {
    title = "Прихвостень",
    description = "Прихвостень для работы.\nНенавидит запах винограда...",
    preview = {model = "ocult_cultist_full", center = {0, 0, 0}},
    commands = {
        {id = "stop", label = "Стоп", hint = "Остановиться", slot = 2},
        {id = "gather", label = "Сбор", slot = 3, target = "zone",
         hint = "Собрать ресурсы: ЛКМ по ресурсу или выделить область"},
        {id = "build", label = "Стройка", hint = "Меню построек", slot = 9,
         submenu = "build"},
        -- build menu
        {id = "extractor", label = "Экстр.", menu = "build", slot = 1,
         hint = "Построить экстрактор", place = "ocult:extractor",
         cost = EXTRACTOR_COST},
        {id = "altar", label = "Алтарь", menu = "build", slot = 2,
         hint = "Принести себя в жертву и стать алтарем", place = "ocult:altar",
         cost = ALTAR_COST},
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

local function stop_gathering()
    release_claim()
    zone = nil
    busy = false
end

local function in_zone(pos)
    return pos[1] >= zone[1] and pos[1] <= zone[3] and pos[3] >= zone[2] and pos[3] <= zone[4]
end

local function next_drop()
    return drops.nearest_free(get_pos(), function(pos) return in_zone(pos) end)
end

local function deliver()
    local cell = core_site.access_cell(get_pos())
    if not cell then
        stop_gathering()
        return
    end
    busy = true
    move_to(cell, function()
        busy = false
        if economy.add(carried, 1) == 1 then
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
    if economy.is_full() then
        stop_gathering()
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
    if zone and not busy then
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
    local drop = target_uid and drops.get(target_uid)
    if drop then
        command_gather(zone_around(entities.get(target_uid).transform:get_pos()))
        return
    end
    -- RMB on the core with an item in hands: hand it in, then keep gathering
    if carried and target_block
            and block.name(block.get(unpack(target_block))) == core_site.BLOCK then
        stop()
        zone = last_zone or zone_around(get_pos())
        deliver()
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

-- walk to the chosen spot, then turn into the building
local function refund(cost)
    for id, n in pairs(cost) do
        economy.add(id, n)
    end
end

-- pays, walks to `stand`, places the building; refunds if it can't
local function build(block_name, origin, cost, stand, sacrifice)
    if not economy.spend(cost) then
        return "Не хватает: " .. economy.cost_text(cost)
    end
    stop_gathering()
    move_to(stand, function()
        if building.can_place(block_name, origin) then
            building.place(block_name, origin)
            if sacrifice then
                remove()
            end
        else
            refund(cost)
        end
    end, function()
        refund(cost)
    end)
end

-- the cultist stands in the middle of the spot and becomes the altar
function command_altar(origin)
    return build("ocult:altar", origin, ALTAR_COST,
        building.center_cell("ocult:altar", origin), true)
end

-- builds from the edge of the spot, so it isn't walled in
function command_extractor(origin)
    local sx, _, sz = block.get_size(block.index("ocult:extractor"))
    local stand = building.ring_cell(origin, sx, sz, get_pos())
    if not stand then
        return "Не подойти к месту стройки"
    end
    return build("ocult:extractor", origin, EXTRACTOR_COST, stand, false)
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
