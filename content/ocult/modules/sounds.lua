-- Sounds of the game (sounds/, short ones preloaded in preload.json; the
-- day/night music is streamed).
--   play(name, pos, volume, pitch) - in the world, at pos
--   ui(name)                       - interface (ui/ui_click, ui/ui_error)
--   damage(who, pos)               - a blow dealt by `who` (sounds named
--                                    "<folder>/damage_<who>"), random pitch
--   select(kind)                   - sometimes, when a unit is clicked
--   update()                       - every frame (scripts/hud.lua): day and
--                                    night jingles and music; returns "day" /
--                                    "night" on the frame it changes
--
-- The engine has no setting for how far a sound carries, and the listener is
-- the RTS camera high above the map. So world sounds are played on the line
-- from the camera to their point, at HEARING_SCALE of the distance: same
-- direction, but they fade as if heard from much closer.
--   stop_music()                   - when the world closes
local combat = require "ocult:combat"
local rts_camera = require "ocult:rts_camera"

local this = {}

local DAMAGE_PITCH = {0.75, 1.25}
local SELECT_CHANCE = 0.35   -- a click on a unit says something this often
local SECRET_CHANCE = 0.01   -- ...and this rarely the secret line
local MUSIC = {
    day = "sounds/other/time_day_ambience.ogg",
    night = "sounds/other/time_night_ambience.ogg",
}
local JINGLE = {day = "other/time_day", night = "other/time_night"}
local MUSIC_VOLUME = 0.6
local HEARING_SCALE = 0.35 -- smaller = sounds carry farther

local DAMAGE = {
    troll = "enemies/damage_troll",
    goblin = "enemies/damage_goblin",
    skeleton = "enemies/damage_skeleton",
    cultist = "units/damage_cultist",
    mimic = "units/damage_mimic",
}
local SELECT = {
    cultist = {"units/select_cultist1", "units/select_cultist2"},
    cultist_secret = "units/select_cultist3-secret_superlowchance",
    mimic = {"units/select_mimic"},
}

function this.play(name, pos, volume, pitch)
    local cam = rts_camera.get_camera()
    if cam then
        local c = cam:get_pos()
        pos = {
            c[1] + (pos[1] - c[1]) * HEARING_SCALE,
            c[2] + (pos[2] - c[2]) * HEARING_SCALE,
            c[3] + (pos[3] - c[3]) * HEARING_SCALE,
        }
    end
    audio.play_sound(name, pos[1], pos[2], pos[3], volume or 1, pitch or 1, "regular")
end

function this.ui(name)
    audio.play_sound_2d("ui/ui_" .. name, 1, 1, "ui")
end

function this.damage(who, pos)
    local name = DAMAGE[who]
    if name then
        local pitch = DAMAGE_PITCH[1] + math.random() * (DAMAGE_PITCH[2] - DAMAGE_PITCH[1])
        this.play(name, pos, 1, pitch)
    end
end

-- kind: "cultist" / "mimic"
function this.select(kind)
    local list = SELECT[kind]
    if not list or math.random() >= SELECT_CHANCE then
        return
    end
    local name = list[math.random(#list)]
    if kind == "cultist" and math.random() < SECRET_CHANCE then
        name = SELECT.cultist_secret
    end
    audio.play_sound_2d(name, 1, 1, "ui")
end

-- "ПЛОХИЕ КОСТИ": a guitar riff cut in pieces, played in this order
local BADBONE = {1, 1, 2, 1, 3, 4}

-- plays the next piece; returns the next index (keep it per tower)
function this.badbone(index, pos)
    index = index or 1
    this.play("towers/shoot_badbone" .. BADBONE[index], pos)
    return index % #BADBONE + 1
end

local time_of_day -- "day" / "night" now playing
local music       -- speaker id of the music stream

function this.update()
    local now = combat.is_night() and "night" or "day"
    if now == time_of_day then
        return
    end
    local first = time_of_day == nil
    time_of_day = now
    if music then
        audio.stop(music)
    end
    music = audio.play_stream_2d(MUSIC[now], MUSIC_VOLUME, 1, "music", true)
    if not first then -- no jingle when the world opens
        audio.play_sound_2d(JINGLE[now], 1, 1, "regular")
        return now
    end
end

function this.stop_music()
    if music then
        audio.stop(music)
    end
    music, time_of_day = nil, nil
end

return this
