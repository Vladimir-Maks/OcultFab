-- Banner and skull of a "ПЛОХИЕ КОСТИ" altar (groups banner and skull of
-- .assets/skull_altar/skull-altar.bbmodel, skeleton skull_altar by
-- tools/bbmodel2rig.py). Plays idle; shoot() plays reload once: the skull is
-- gone (it flew off) and grows back while the banner spins.
local IDLE = "ocult_skull_altar_idle"
local RELOAD = "ocult_skull_altar_reload"
local RELOAD_TIME = 2.0 -- seconds of the reload animation

entity.rigidbody:set_enabled(false) -- placed by the altar, no physics
local rig = entity.skeleton

local track = animation.play(IDLE, rig)
local reloading = 0

function shoot()
    track:stop()
    track = animation.play(RELOAD, rig)
    reloading = RELOAD_TIME
end

function on_render(delta)
    if reloading > 0 then
        reloading = reloading - delta
        if reloading <= 0 then
            track:stop()
            track = animation.play(IDLE, rig)
        end
    end
end

function on_despawn()
    track:stop()
end
