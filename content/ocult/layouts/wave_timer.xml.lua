-- Next wave countdown in real seconds (ocult:combat); hidden by day and when
-- the next wave would fall after dawn (it won't come then)
local combat = require "ocult:combat"

local BACKING = {20, 12, 18, 192}
local NONE = {0, 0, 0, 0}
local REFRESH_MS = 250

local function refresh()
    local seconds = combat.next_wave_seconds()
    if seconds then
        local s = math.ceil(seconds)
        document.text.text = string.format("Волна через %d:%02d", math.floor(s / 60), s % 60)
        document.root.color = BACKING
    else
        document.text.text = ""
        document.root.color = NONE
    end
end

function on_open()
    refresh()
    document.root:setInterval(REFRESH_MS, refresh)
end
