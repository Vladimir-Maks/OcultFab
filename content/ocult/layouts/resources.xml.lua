-- Resource bar: one cell per item of RESOURCES, counts from ocult:economy
local economy = require "ocult:economy"

local RESOURCES = {"ocult:stone.item", "ocult:iron_ore.item", "ocult:mana_ore.item"}
local CELL_W = 140
local REFRESH_MS = 250

local function icon_of(name)
    local ok, id = pcall(item.index, name)
    return ok and item.icon(id) or "gui/no_icon"
end

local function refresh()
    for i, name in ipairs(RESOURCES) do
        document["count_" .. i].text = "× " .. economy.get(name)
    end
end

function on_open()
    local row = document.root -- a layout's root is always "root"
    row:clear()
    row.size = {CELL_W * #RESOURCES, 36}
    for i, name in ipairs(RESOURCES) do
        local x = (i - 1) * CELL_W
        row:add(string.format(
            "<image src='%s' pos='%d,2' size='32,32' interactive='false'/>",
            icon_of(name), x + 6))
        row:add(string.format(
            "<label id='count_%d' pos='%d,9' size='%d,18' color='#e0c8d0FF' "
            .. "interactive='false' tooltip='%s'></label>",
            i, x + 44, CELL_W - 48, economy.caption(name)))
    end
    refresh()
    document.root:setInterval(REFRESH_MS, refresh)
end
