-- Mimic: a walking chest, a buffer away from the core.
-- "Прием" makes it sit down: then it can't move or turn, and workers hand
-- their items to it instead of walking to the core. "Встать" gets it back
-- on its feet. It holds up to economy.MIMIC_CAPACITY items; they don't count
-- as stored until it brings them to the core: once full (or on "Отнести")
-- it gets up, walks to the core, unloads (waiting there while the core is
-- full), walks back to where it sat and sits down again. Every mimic also
-- raises the core's capacity by economy.MIMIC_BONUS (see ocult:economy).
-- While sitting it's a kinematic body (others bump into it, it doesn't move)
-- and its cell holds an invisible block ocult:mimic_seat, tagged so that
-- units route around it (rts/unit AVOID_TAG); workers hand items in from a
-- cell next to it.
--
-- Animations (animation/ocult_mimic_*.vca, exported by tools/bbmodel2rig.py):
-- walk while moving (played faster the faster it goes), sitdown (holds the
-- last frame while sitting), standup. When an animation stops, the pose
-- eases back to rest instead of snapping.
local unit = require "ocult:rts/unit"
local economy = require "ocult:economy"
local core_site = require "ocult:rts/core_site"
local combat = require "ocult:combat"

local ANIM_WALK = "ocult_mimic_walk"
local ANIM_SIT = "ocult_mimic_sitdown"
local ANIM_STAND = "ocult_mimic_standup"
local STAND_TIME = 0.75 -- seconds until it can walk after "Встать"
local WALK_RATE = 1.6   -- walk animation playback speed at full speed
local IDLE_DELAY = 0.15 -- seconds standing before the walk animation stops
local BLEND_TIME = 0.25 -- seconds to ease back to the rest pose
local BONES = {"chest", "upper_chest", "back_leg", "back_leg2", "group", "group2"}
local UNLOAD_RETRY = 2  -- seconds between unloading attempts at a full core

local uid = entity:get_uid()
local rig = entity.skeleton

local stock = SAVED_DATA.stock or {}
local sitting = SAVED_DATA.sitting or false
local standing_up = 0 -- seconds left of the stand-up animation
local track          -- the playing animation
local track_name
local blend          -- {from = {bone index -> pose matrix}, t = seconds}
local idle_time = 0
-- delivery trip: nil, "standing" (getting up), "to_core", "unloading",
-- "home" (walking back to sit down at `home`)
local trip
local home = SAVED_DATA.home -- {x, y, z} cell it sat on
local unload_timer = 0

local bones = {}
for _, name in ipairs(BONES) do
    local index = rig:index(name)
    if index then
        table.insert(bones, index)
    end
end

economy.register_mimic(uid, stock)

local function play(name)
    if track_name == name then
        return track
    end
    if track then
        track:stop()
    end
    track_name = name
    track = name and animation.play(name, rig)
    blend = nil
    if not name then
        -- ease from the current pose to rest (see on_render)
        blend = {from = {}, t = 0}
        for _, index in ipairs(bones) do
            blend.from[index] = rig:get_matrix(index)
        end
    end
    return track
end

unit.extend(this, {
    title = "Мимик",
    description = function(self)
        local state
        if trip == "unloading" then
            state = "Ждет у ядра: склад полон."
        elseif trip then
            state = "Несет добычу в ядро."
        elseif sitting then
            state = "Принимает предметы, не двигается."
        else
            state = "Прикажите ему сесть, чтобы прихвостни несли добычу к нему."
        end
        local text = string.format("Сундук на ножках. Копит до %d предметов и "
            .. "сам относит их в ядро; склад ядра больше на %d.\n%s\n\nВнутри: %d/%d",
            economy.MIMIC_CAPACITY, economy.MIMIC_BONUS, state,
            economy.mimic_total(uid), economy.MIMIC_CAPACITY)
        text = self.health_text() .. "\n" .. text
        for _, entry in ipairs(economy.mimic_items(uid)) do
            text = text .. string.format("\n%s ×%d", entry.caption, entry.count)
        end
        return text
    end,
    preview = {model = "ocult_mimic_full", center = {0, 0, 0}},
    speed = 2.5,
    health = combat.stats.units["ocult:mimic"].health,
    commands = function(self)
        if sitting then
            return {
                {id = "stand", label = "Встать", slot = 1,
                 hint = "Встать и снова ходить"},
                {id = "deliver", label = "Отнести", slot = 2,
                 hint = "Отнести содержимое в ядро и вернуться"},
            }
        end
        return {
            {id = "sit", label = "Прием", slot = 1,
             hint = "Сесть и принимать предметы от прихвостней"},
            {id = "stop", label = "Стоп", hint = "Остановиться", slot = 2},
        }
    end,
})

function on_save()
    SAVED_DATA.stock = stock
    SAVED_DATA.sitting = sitting
    SAVED_DATA.home = home
end

-- workers may hand items in
function accepts_items()
    return sitting and economy.mimic_free(uid) > 0
end

local function cell_of(pos)
    return {math.floor(pos[1]), math.floor(pos[2]), math.floor(pos[3])}
end

local SEAT = "ocult:mimic_seat"
local seat -- {x, y, z} of the placed seat block

local function place_seat(cell)
    local id = block.get(cell[1], cell[2], cell[3])
    if id == 0 then
        block.set(cell[1], cell[2], cell[3], block.index(SEAT), 0)
        seat = cell
    elseif id == block.index(SEAT) then
        seat = cell -- saved with the world
    end
end

local function remove_seat()
    if seat and block.get(seat[1], seat[2], seat[3]) == block.index(SEAT) then
        block.set(seat[1], seat[2], seat[3], 0, 0)
    end
    seat = nil
end

-- sitting: fixed in the middle of its cell, not pushed, walked around
local function settle()
    local cell = cell_of(get_pos())
    local pos = get_pos()
    entity.transform:set_pos({cell[1] + 0.5, pos[2], cell[3] + 0.5})
    entity.rigidbody:set_body_type("kinematic")
    set_anchored(true)
    place_seat(cell)
    return cell
end

local function sit_down()
    sitting = true
    standing_up = 0
    home = settle()
    play(ANIM_SIT)
end

local function get_up()
    sitting = false
    standing_up = STAND_TIME
    remove_seat()
    entity.rigidbody:set_body_type("dynamic")
    play(ANIM_STAND)
end

function command_sit()
    trip = nil
    sit_down()
end

function command_stand()
    trip = nil
    get_up()
end

function command_stop()
    trip = nil
    stop()
end

local function go_home()
    trip = "home"
    if not home then
        trip = nil
        return
    end
    move_to(home, function()
        trip = nil
        sit_down()
    end, function()
        trip = nil -- can't get back: stays standing
    end)
end

local function try_unload()
    if economy.unload_mimic(uid) == 0 then
        go_home()
    else
        trip = "unloading"
        unload_timer = UNLOAD_RETRY
    end
end

local function go_to_core()
    local cell = core_site.access_cell(get_pos())
    if not cell then
        trip = nil
        return
    end
    trip = "to_core"
    move_to(cell, try_unload, function()
        trip = nil -- no way to the core
    end)
end

-- the sitting mimic gets up and carries everything to the core
local function start_trip()
    if trip or economy.mimic_total(uid) == 0 then
        return
    end
    trip = "standing"
    get_up()
end

function command_deliver()
    start_trip()
end

function on_update(tps)
    if sitting and economy.mimic_free(uid) == 0 then
        start_trip()
    elseif trip == "unloading" then
        unload_timer = unload_timer - 1 / tps
        if unload_timer <= 0 then
            try_unload()
        end
    end
end

if sitting then
    home = home or cell_of(get_pos())
    settle()
    -- loaded sitting: straight to the last frame
    play(ANIM_SIT).__timer = 100
end

local base_on_order = on_order
function on_order(pos, target_uid, target_block)
    if sitting or standing_up > 0 then
        return
    end
    trip = nil -- the player's order cancels a delivery trip
    base_on_order(pos, target_uid)
end

local base_on_render = on_render
function on_render(delta)
    if not sitting and standing_up <= 0 then
        base_on_render(delta) -- turning towards the movement direction
    end
    if standing_up > 0 then
        standing_up = standing_up - delta
        if standing_up <= 0 then
            set_anchored(false)
            play(nil)
            if trip == "standing" then
                go_to_core()
            end
        end
    elseif not sitting then
        if get_move_dir() then
            idle_time = 0
            play(ANIM_WALK)
        else
            idle_time = idle_time + delta
            if idle_time > IDLE_DELAY then
                play(nil)
            end
        end
    end
    if track and track_name == ANIM_WALK then
        -- the engine advances tracks by real time; speed it up or down
        track.__timer = track.__timer + delta * (WALK_RATE * get_speed_fraction() - 1)
    end
    if blend then
        blend.t = blend.t + delta
        local k = math.min(1, blend.t / BLEND_TIME)
        k = k * k * (3 - 2 * k) -- smoothstep
        local rest = mat4.idt()
        for index, from in pairs(blend.from) do
            local m = {}
            for i = 1, 16 do
                m[i] = from[i] * (1 - k) + rest[i] * k
            end
            rig:set_matrix(index, m)
        end
        if k >= 1 then
            blend = nil
            rig:reset_pose()
        end
    end
end

local base_on_despawn = on_despawn
function on_despawn()
    economy.unregister_mimic(uid)
    remove_seat()
    if track then
        track:stop()
    end
    base_on_despawn()
end
