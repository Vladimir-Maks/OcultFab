-- Item pump settings window (buildings/pump: pump.editing is the pump).
-- Changes apply right away.
local economy = require "ocult:economy"
local machines = require "ocult:machines"
local pump = require "ocult:buildings/pump"

local ROW_W, ROW_H = 326, 36 -- as in storage.xml.lua
local REFRESH_MS = 500
local SELECTED = {138, 42, 64, 255}
local NORMAL = {34, 20, 28, 255}

local shown -- signature of the item rows on screen

local function state()
    local b = pump.editing
    if not b or block.get(b.x, b.y, b.z) ~= b.id then
        return nil -- demolished while the window is open
    end
    return machines.of(b)
end

local function configure(settings)
    if state() then
        pump.configure(pump.editing, settings)
    end
end

local function icon_of(name)
    local ok, id = pcall(item.index, name)
    return ok and item.icon(id) or "gui/no_icon"
end

local function show_items(st)
    local list = economy.items()
    local selected = st.item
    if selected and economy.get(selected) == 0 then
        table.insert(list, 1, {name = selected, caption = economy.caption(selected), count = 0})
    end
    local parts = {selected or ""}
    for _, entry in ipairs(list) do
        table.insert(parts, entry.name .. "=" .. entry.count)
    end
    local sig = table.concat(parts, ";")
    if sig == shown then
        return
    end
    shown = sig
    local rows = document.items
    rows:clear()
    if #list == 0 then
        rows:add(string.format("<label size='%d,24' color='#a08890FF'>Склад пуст</label>", ROW_W))
        return
    end
    for _, entry in ipairs(list) do
        local color = entry.name == selected and "#8a2a40FF" or "#22141cFF"
        -- same row as in the storage window, clickable
        rows:add(string.format([[
            <container size='%d,%d' color='%s' hover-color='#3a2430FF' onclick='DATA.pick()'>
                <image src='%s' pos='4,2' size='32,32'/>
                <label pos='44,9' size='190,18' color='#e0c8d0FF'>%s</label>
                <label pos='236,9' size='84,18' text-align='right' color='#e0c8d0FF'>%d</label>
            </container>]], ROW_W, ROW_H, color, icon_of(entry.name), entry.caption, entry.count),
            {pick = function()
                configure({item = entry.name})
                shown = nil
                refresh()
            end})
    end
end

function refresh()
    local st = state()
    if not st then
        document.status.text = "Помпа разрушена"
        return
    end
    show_items(st)
    document.mode_once.color = st.mode == "once" and SELECTED or NORMAL
    document.mode_keep.color = st.mode == "keep" and SELECTED or NORMAL
    document.spread.text = st.spread == "round"
        and "Выходы: по очереди" or "Выходы: первый свободный"
    document.status.text = st._status or ""
end

function set_mode(mode)
    configure({mode = mode})
    refresh()
end

function toggle_spread()
    local st = state()
    if st then
        configure({spread = st.spread == "round" and "first" or "round"})
        refresh()
    end
end

function is_count(text)
    return text == "" or text:match("^%d+$") ~= nil
end

function on_limit(text)
    if is_count(text) then
        configure({limit = tonumber(text) or 0})
    end
end

local ticking = false

function on_open()
    shown = nil
    local st = state()
    document.limit.text = st and tostring(st.limit) or ""
    refresh()
    -- the document outlives the window: start the timer only once
    if not ticking then
        ticking = true
        document.root:setInterval(REFRESH_MS, refresh)
    end
end
