-- Core storage window: one row per stored item (icon, name, count, "−"
-- button that throws one away; with Shift - ten).
-- Icons are the items' inventory icons for now.
local economy = require "ocult:economy"

local ROW_W, ROW_H = 326, 36
local REFRESH_MS = 500

local shown -- "name=count;..." of the rows on screen, to rebuild only on changes

local function signature(list)
    local parts = {}
    for _, entry in ipairs(list) do
        table.insert(parts, entry.name .. "=" .. entry.count)
    end
    return table.concat(parts, ";")
end

local function icon_of(name)
    local ok, id = pcall(item.index, name)
    return ok and item.icon(id) or "gui/no_icon"
end

local function refresh()
    local list = economy.items()
    document.capacity.text = string.format("Занято %d из %d, свободно %d",
        economy.total(), economy.capacity(), economy.free())
    local sig = signature(list)
    if sig == shown then
        return
    end
    shown = sig
    local rows = document.rows
    rows:clear()
    if #list == 0 then
        rows:add(string.format(
            "<label size='%d,24' color='#a08890FF'>Пусто</label>", ROW_W))
        return
    end
    for _, entry in ipairs(list) do
        rows:add(string.format([[
            <container size='%d,%d' color='#22141cFF'>
                <image src='%s' pos='4,2' size='32,32'/>
                <label pos='44,9' size='176,18' color='#e0c8d0FF'>%s</label>
                <label pos='222,9' size='64,18' text-align='right' color='#e0c8d0FF'>%d</label>
                <button pos='294,5' size='26,26' onclick='DATA.remove()'
                        tooltip='Утилизировать 1 (Shift - 10)'>-</button>
            </container>]], ROW_W, ROW_H, icon_of(entry.name), entry.caption, entry.count),
            {remove = function()
                local n = input.is_pressed("key:left-shift") and 10 or 1
                economy.discard(entry.name, n)
                refresh()
            end})
    end
end

local ticking = false

function on_open()
    shown = nil
    refresh()
    -- the document outlives the window: start the timer only once
    if not ticking then
        ticking = true
        document.root:setInterval(REFRESH_MS, refresh)
    end
end
