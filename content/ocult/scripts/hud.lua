local rts_camera = require "ocult:rts_camera"
local hud_cleanup = require "ocult:hud_cleanup"
local selection = require "ocult:rts/selection"
local core_site = require "ocult:rts/core_site"
local arena = require "ocult:arena"
local fog = require "ocult:fog"
local combat = require "ocult:combat"
local sounds = require "ocult:sounds"
local economy = require "ocult:economy"
local command_panel = require "ocult:rts/command_panel"

local DEBUG_LAYOUT = "ocult:debug"
local debug_open = false

-- "Склад переполнен" when the core storage fills up (once per filling)
local FULL_CHECK = 0.5 -- seconds between checks
local full_timer = 0
local was_full = false

local function check_storage()
    full_timer = full_timer - time.delta()
    if full_timer > 0 then
        return
    end
    full_timer = FULL_CHECK
    local full = economy.is_full()
    if full and not was_full then
        command_panel.notify("Склад переполнен")
    end
    was_full = full
end

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
    combat.check_core() -- the core may have been destroyed before saving
    hud.open_permanent("ocult:resources")
    hud.open_permanent("ocult:wave_timer")
    -- F6: debug panel, like the engine's F3
    input.add_callback("key:f6", function()
        debug_open = not debug_open
        if debug_open then
            hud.open_permanent(DEBUG_LAYOUT)
        else
            hud.close(DEBUG_LAYOUT)
        end
    end)
end

function on_hud_render()
    hud_cleanup.update()
    if not hud.is_paused() and not hud.is_inventory_open()
            and input.is_pressed("key:space") then
        center_camera()
    end
    rts_camera.update(time.delta())
    local changed = sounds.update()
    if changed then
        command_panel.notify(changed == "night" and "Наступила ночь" or "Наступил день", true)
    end
    check_storage()
    local focus = rts_camera.get_focus()
    fog.debug_update(focus[1], focus[3])
    if not hud.is_paused() then
        selection.update()
    end
end

function on_hud_close()
    sounds.stop_music()
end
