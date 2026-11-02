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

-- a wave right away, worth the shortest wait (spawn.wave_interval_min);
-- replaces what's left of the queued wave
function spawn_wave()
    local s = combat.stats.spawn
    combat.clear_queue()
    local n = combat.start_wave(math.floor(s.wave_interval_min * s.points_per_minute
        * combat.difficulty()))
    require("ocult:rts/command_panel").notify("Волна: " .. n .. " врагов", true)
end

-- "До волны: 12 мин", the enemies still queued
function wave_status()
    local eta = combat.next_wave_eta()
    local text = string.format("Ночь %d (x%g). ", combat.night(), combat.difficulty())
        .. (eta and string.format("До волны: %d мин", math.ceil(eta)) or "Волн нет")
    if combat.queued() > 0 then
        text = text .. ", в очереди " .. combat.queued()
    end
    return text
end

-- the start of the night (config/combat.json, spawn.night_start)
function make_night()
    world.set_day_time(combat.stats.spawn.night_start / 24)
end

-- removes every enemy and the rest of the current wave
function kill_enemies()
    local n = combat.kill_all()
    require("ocult:rts/command_panel").notify("Убито врагов: " .. n, true)
end
