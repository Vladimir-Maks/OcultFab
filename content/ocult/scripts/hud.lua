local rts_camera = require "ocult:rts_camera"
local hud_cleanup = require "ocult:hud_cleanup"
local selection = require "ocult:rts/selection"
local core_site = require "ocult:rts/core_site"
local arena = require "ocult:arena"

-- Space: camera to the selection (average point), or to the core when
-- nothing is selected (the world centre if there is no core). Held down,
-- the camera keeps following.
local function center_camera()
    local selected = selection.get()
    if #selected > 0 then
        local x, z = 0, 0
        for _, obj in ipairs(selected) do
            local pos = obj.get_pos()
            x, z = x + pos[1], z + pos[3]
        end
        rts_camera.focus_on(x / #selected, z / #selected)
        return
    end
    local core = core_site.origin()
    if core then
        local sx, _, sz = block.get_size(block.index(core_site.BLOCK))
        rts_camera.focus_on(core[1] + sx / 2, core[3] + sz / 2)
    else
        local x, _, z = arena.center()
        rts_camera.focus_on(x, z)
    end
end

function on_hud_open(playerid)
    hud_cleanup.init()
    rts_camera.init(playerid)
    selection.init(rts_camera.get_camera(), playerid)
end

function on_hud_render()
    hud_cleanup.update()
    if not hud.is_paused() and not hud.is_inventory_open()
            and input.is_pressed("key:space") then
        center_camera()
    end
    rts_camera.update(time.delta())
    if not hud.is_paused() then
        selection.update()
    end
end
