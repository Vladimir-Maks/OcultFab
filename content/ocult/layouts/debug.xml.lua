-- Debug panel switches, see ocult:debug
local debug_flags = require "ocult:debug"
local fog = require "ocult:fog"
local combat = require "ocult:combat"

function get_free_build()
    return debug_flags.free_build
end

function set_free_build(flag)
    debug_flags.free_build = flag
end

function get_fog()
    return fog.is_enabled()
end

function set_fog(flag)
    fog.set_enabled(flag)
end

-- one enemy of the spawner's kind, placed by the spawner's rules
function spawn_enemy()
    if not combat.spawn_enemy(combat.stats.spawn.enemy) then
        require("ocult:rts/command_panel").notify(
            "Нет прокопанного места дальше " .. combat.stats.spawn.distance .. " блоков от построек")
    end
end

-- the start of the night (config/combat.json, spawn.night_start)
function make_night()
    world.set_day_time(combat.stats.spawn.night_start / 24)
end
