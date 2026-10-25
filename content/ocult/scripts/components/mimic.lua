-- Mimic: a walking chest, extra storage away from the core.
-- "Приём" makes it sit down: then it can't move or turn, and workers hand
-- their items to it as to the core. "Встать" gets it back on its feet.
-- Holds up to economy.MIMIC_CAPACITY items itself and raises the common
-- storage limit by economy.MIMIC_BONUS (see ocult:economy).
--
-- Animations (animation/ocult_mimic_*.vca, exported by tools/bbmodel2rig.py):
-- walk while moving (played faster the faster it goes), sitdown (holds the
-- last frame while sitting), standup. When an animation stops, the pose
-- eases back to rest instead of snapping.
local unit = require "ocult:rts/unit"
local economy = require "ocult:economy"

local ANIM_WALK = "ocult_mimic_walk"
local ANIM_SIT = "ocult_mimic_sitdown"
local ANIM_STAND = "ocult_mimic_standup"
local STAND_TIME = 0.75 -- seconds until it can walk after "Встать"
local WALK_RATE = 1.6   -- walk animation playback speed at full speed
local IDLE_DELAY = 0.15 -- seconds standing before the walk animation stops
local BLEND_TIME = 0.25 -- seconds to ease back to the rest pose
local BONES = {"chest", "upper_chest", "back_leg", "back_leg2", "group", "group2"}

local uid = entity:get_uid()
local rig = entity.skeleton

local stock = SAVED_DATA.stock or {}
local sitting = SAVED_DATA.sitting or false
local standing_up = 0 -- seconds left of the stand-up animation
local track          -- the playing animation
local track_name
local blend          -- {from = {bone index -> pose matrix}, t = seconds}
local idle_time = 0

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
        local state = sitting and "Принимает предметы, не двигается."
            or "Прикажите ему сесть, чтобы прихвостни несли добычу к нему."
        return string.format("Сундук на ножках. Хранит до %d предметов, "
            .. "общий склад больше на %d.\n%s\n\nВнутри: %d/%d",
            economy.MIMIC_CAPACITY, economy.MIMIC_BONUS, state,
            economy.mimic_total(uid), economy.MIMIC_CAPACITY)
    end,
    preview = {model = "ocult_mimic_full", center = {0, 0, 0}},
    speed = 2.5,
    commands = function(self)
        if sitting then
            return {
                {id = "stand", label = "Встать", slot = 1,
                 hint = "Встать и снова ходить"},
            }
        end
        return {
            {id = "sit", label = "Приём", slot = 1,
             hint = "Сесть и принимать предметы от прихвостней"},
            {id = "stop", label = "Стоп", hint = "Остановиться", slot = 2},
        }
    end,
})

function on_save()
    SAVED_DATA.stock = stock
    SAVED_DATA.sitting = sitting
end

-- workers may hand items in
function accepts_items()
    return sitting and economy.mimic_free(uid) > 0
end

function command_sit()
    sitting = true
    standing_up = 0
    set_anchored(true)
    play(ANIM_SIT)
end

function command_stand()
    sitting = false
    standing_up = STAND_TIME
    play(ANIM_STAND)
end

function command_stop()
    stop()
end

if sitting then
    set_anchored(true)
    -- loaded sitting: straight to the last frame
    play(ANIM_SIT).__timer = 100
end

local base_on_order = on_order
function on_order(pos, target_uid, target_block)
    if sitting or standing_up > 0 then
        return
    end
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
    if track then
        track:stop()
    end
    base_on_despawn()
end
