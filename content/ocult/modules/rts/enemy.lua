-- Base for enemies (entities): walks to the nearest target (our unit,
-- defensive building or the core, see ocult:combat) and hits it while it's
-- within attack range. Stats: config/combat.json, enemies[id].
--
-- enemy.extend(env, id, def): def as for rts/unit (title, model_yaw...) plus
--   anim_walk    - animation played while walking (sped up with the speed)
--   walk_rate    - its playback speed at full speed (default 1)
--   anim_attack  - animation of a blow, fitted into one attack interval
--   attack_length - seconds of motion in it
-- The damage lands when the swing is over (the animation has played; without
-- one after WINDUP). An enemy killed mid-swing deals nothing: its component
-- is gone before the timer runs out. A target that has stepped away is
-- missed.
local unit = require "ocult:rts/unit"
local combat = require "ocult:combat"
local building = require "ocult:rts/building"
local arena = require "ocult:arena"
local drops = require "ocult:drops"

local enemy = {}

local THINK_INTERVAL = 1.0 -- seconds between target / route updates
local HIT_SLACK = 0.5      -- the target may step this far away mid-swing
local WINDUP = 0.4         -- seconds before the blow of an enemy without
                           -- an attack animation

local function cell_of(pos)
    return {math.floor(pos[1]), arena.LEVEL, math.floor(pos[3])}
end

function enemy.extend(env, id, def)
    local stats = combat.stats.enemies[id]
    def.enemy = true
    def.speed = stats.speed
    def.health = stats.health
    unit.extend(env, def)

    local entity = env.entity
    local uid = entity:get_uid()
    local rig = entity.skeleton
    combat.register_enemy(uid)

    local target    -- see combat.targets()
    local think_timer = 0
    local attack_timer = 0
    local hit_timer -- seconds until the blow of the current attack lands
    local hit_target
    local track, track_name
    local attack_rate = 1 -- attack animation speed

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

    local function nearest_target()
        local pos = env.get_pos()
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
            return building.ring_cell(cell, 1, 1, env.get_pos())
        end
        return building.ring_cell({t.x, t.y, t.z}, t.sx, t.sz, env.get_pos())
    end

    local function think()
        target = nearest_target()
        if not target then
            env.stop()
            return
        end
        if combat.distance(env.get_pos(), target) <= stats.attack_range then
            env.stop()
            return
        end
        local cell = approach_cell(target)
        if cell then
            env.move_to(cell)
        end
    end

    local function strike()
        hit_target = combat.refresh(hit_target)
        if hit_target and combat.distance(env.get_pos(), hit_target)
                <= stats.attack_range + HIT_SLACK then
            combat.damage(hit_target, stats.damage)
        end
    end

    function env.on_update(tps)
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
                and combat.distance(env.get_pos(), target) <= stats.attack_range then
            env.stop()
            if target.kind == "unit" then
                env.face(target.pos)
            else
                env.face({target.x + target.sx / 2, 0, target.z + target.sz / 2})
            end
            attack_timer = 1 / stats.attack_speed
            hit_target = target
            if def.anim_attack then
                -- the whole swing fits into one attack interval
                attack_rate = math.max(1, def.attack_length / attack_timer)
                play(nil)
                play(def.anim_attack)
            end
            -- the blow lands at the end of the swing
            hit_timer = def.anim_attack and def.attack_length / attack_rate
                or math.min(WINDUP, attack_timer)
        end
        if hit_timer then
            hit_timer = hit_timer - dt
            if hit_timer <= 0 then
                hit_timer = nil
                strike()
            end
        end
    end

    local base_on_render = env.on_render
    function env.on_render(delta)
        base_on_render(delta)
        local attacking = track_name == def.anim_attack and track
            and track.__timer < def.attack_length
        if not attacking then
            play(env.get_move_dir() and def.anim_walk or nil)
        end
        -- the engine advances tracks by real time; speed them up or down
        if track and track_name == def.anim_attack then
            track.__timer = track.__timer + delta * (attack_rate - 1)
        elseif track and track_name == def.anim_walk then
            track.__timer = track.__timer
                + delta * ((def.walk_rate or 1) * env.get_speed_fraction() - 1)
        end
    end

    -- player orders are ignored (enemies aren't selectable anyway)
    function env.on_order() end

    -- loot (enemies[id].loot): every entry rolls its own chance
    function env.on_death()
        local pos = env.get_pos()
        for _, loot in ipairs(stats.loot or {}) do
            if math.random() < loot.chance then
                local ok, id = pcall(item.index, loot.item)
                if ok then
                    drops.spawn(id, loot.count or 1, {pos[1], arena.LEVEL + 0.3, pos[3]})
                else
                    print("enemy loot: unknown item " .. loot.item)
                end
            end
        end
    end

    local base_on_despawn = env.on_despawn
    function env.on_despawn()
        combat.unregister_enemy(uid)
        if track then
            track:stop()
        end
        base_on_despawn()
    end
end

return enemy
