-- Hides the default first-person HUD (hotbar, crosshair) while keeping the
-- inventory screen available.

local this = {}

-- 1x1 transparent png
local EMPTY_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII="

function this.init()
    assets.load_texture(base64.decode(EMPTY_PNG), "gui/crosshair")
end

-- must run every frame: the engine re-shows the hotbar on each HUD update
function this.update()
    local hotbar = gui.root["hud.hotbar"]
    if hotbar then
        hotbar.visible = false
    end
end

return this
