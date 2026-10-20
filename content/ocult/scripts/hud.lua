local rts_camera = require "ocult:rts_camera"
local hud_cleanup = require "ocult:hud_cleanup"
local selection = require "ocult:rts/selection"

function on_hud_open(playerid)
    hud_cleanup.init()
    rts_camera.init(playerid)
    selection.init(rts_camera.get_camera(), playerid)
end

function on_hud_render()
    hud_cleanup.update()
    rts_camera.update(time.delta())
    if not hud.is_paused() then
        selection.update()
    end
end
