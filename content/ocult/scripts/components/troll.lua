-- Troll: the first enemy. Walks to the nearest target (our unit, defensive
-- building or the core, see ocult:combat) and hits it while it's within
-- attack range. Stats: config/combat.json, enemies.troll.
-- Model and animations: .assets/troll/troll.bbmodel (tools/bbmodel2rig.py,
-- the model looks along +X). The attack animation is fitted into one attack
-- interval; the damage lands when the arms come down.
local unit = require "ocult:rts/unit"
local combat = require "ocult:combat"
local building = require "ocult:rts/building"
local arena = require "ocult:arena"

local STATS = combat.stats.enemies.troll
local THINK_INTERVAL = 1.0 -- seconds between target / route updates
local ANIM_WALK = "ocult_troll_walk"
local ANIM_ATTACK = "ocult_troll_attack"
local ATTACK_LENGTH = 1.5 -- seconds of motion in the attack animation
local ATTACK_HIT = 0.83   -- second of the animation when the blow lands
local WALK_RATE = 1.2     -- walk animation speed at full speed

local uid = entity:get_uid()

unit.extend(this, {
    title = "Тролль",
    enemy = true,
    model_yaw = 90,
    speed = STATS.speed,
    health = STATS.health,
})

combat.register_enemy(uid)

local target    -- see combat.targets()
local think_timer = 0
local attack_timer = 0
local hit_timer        -- seconds until the blow of the current attack lands
local hit_target

local rig = entity.skeleton
local track, track_name
local attack_rate = 1  -- attack animation speed

local function play(name)
    if track_name == name then
        return
    end
    if track then
        track:stop()
    end
    track_name = name
    track = name and animation.play(name, rig)
    if not name then
        rig:reset_pose()
    end
end

local function cell_of(pos)
    return {math.floor(pos[1]), arena.LEVEL, math.floor(pos[3])}
end

local function nearest_target()
    local pos = get_pos()
    local best, best_d
    for _, t in ipairs(combat.targets()) do
        local d = combat.distance(pos, t)
        if not best or d < best_d then
            best, best_d = t, d
        end
    end
    return best
end

-- where to walk to reach the target
local function approach_cell(t)
    if t.kind == "unit" then
        local cell = cell_of(t.pos)
        if building.is_walkable(cell[1], cell[2], cell[3]) then
            return cell
        end
        -- e.g. a sitting mimic: its cell is walked around
        return building.ring_cell(cell, 1, 1, get_pos())
    end
    return building.ring_cell({t.x, t.y, t.z}, t.sx, t.sz, get_pos())
end

local function think()
    target = nearest_target()
    if not target then
        stop()
        return
    end
    if combat.distance(get_pos(), target) <= STATS.attack_range then
        stop()
        return
    end
    local cell = approach_cell(target)
    if cell then
        move_to(cell)
    end
end

function on_update(tps)
    local dt = 1 / tps
    if target then
        target = combat.refresh(target)
    end
    think_timer = think_timer - dt
    if think_timer <= 0 or not target then
        think_timer = THINK_INTERVAL
        think()
    end
    attack_timer = math.max(0, attack_timer - dt)
    if target and attack_timer == 0
            and combat.distance(get_pos(), target) <= STATS.attack_range then
        stop()
        if target.kind == "unit" then
            face(target.pos)
        else
            face({target.x + target.sx / 2, 0, target.z + target.sz / 2})
        end
        attack_timer = 1 / STATS.attack_speed
        -- the whole swing fits into one attack interval
        attack_rate = math.max(1, ATTACK_LENGTH / attack_timer)
        play(nil)
        play(ANIM_ATTACK)
        hit_timer = ATTACK_HIT / attack_rate
        hit_target = target
    end
    if hit_timer then
        hit_timer = hit_timer - dt
        if hit_timer <= 0 then
            hit_timer = nil
            hit_target = combat.refresh(hit_target)
            if hit_target and combat.distance(get_pos(), hit_target) <= STATS.attack_range + 0.5 then
                combat.damage(hit_target, STATS.damage)
            end
        end
    end
end

local base_on_render = on_render
function on_render(delta)
    base_on_render(delta)
    local attacking = track_name == ANIM_ATTACK
        and track.__timer < ATTACK_LENGTH
    if not attacking then
        play(get_move_dir() and ANIM_WALK or nil)
    end
    if track and track_name == ANIM_ATTACK then
        track.__timer = track.__timer + delta * (attack_rate - 1)
    elseif track and track_name == ANIM_WALK then
        track.__timer = track.__timer + delta * (WALK_RATE * get_speed_fraction() - 1)
    end
end

-- player orders are ignored (enemies aren't selectable anyway)
function on_order() end

local base_on_despawn = on_despawn
function on_despawn()
    combat.unregister_enemy(uid)
    if track then
        track:stop()
    end
    base_on_despawn()
end
