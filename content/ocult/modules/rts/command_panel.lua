-- Bottom HUD panel: info about the selection + context command buttons.
--
-- Buttons sit on a 4x3 grid (StarCraft "command card"). A command picks its
-- cell with `slot`, numbered left to right, top to bottom:
--    1  2  3  4
--    5  6  7  8
--    9 10 11 12   (12 - "Отмена" in a mode / "Назад" in a submenu)
-- Commands without a slot take the first free cells.
-- A command with `submenu = "x"` opens the menu "x": then only commands with
-- `menu = "x"` are shown (commands without `menu` live in the root menu).
-- `cost = {stone = 10}` is shown in the button tooltip.
local economy = require "ocult:economy"

local this = {}

local LAYOUT = "ocult:rts_panel"
local PORTRAIT_SIZE = 130
local PORTRAIT_ROTATION = "45,-30,0" -- yaw, pitch, roll (degrees)
local COLS, ROWS = 4, 3
local CANCEL_SLOT = COLS * ROWS
local BUTTON_W, BUTTON_H = 52, 38
local GAP = 4
local ACTIVE_COLOR = "#8a2a40FF"
local STATUS_TIME = 3 -- seconds a message stays

local doc
local status_until = 0
local described -- object whose description is on screen (kept up to date)

function this.open()
    hud.open_permanent(LAYOUT)
    doc = Document.new(LAYOUT)
end

-- short message under the description ("Склад полон"...)
function this.notify(text)
    if doc then
        doc.status.text = text
        status_until = time.uptime() + STATUS_TIME
    end
end

-- call every frame: hides old messages, refreshes live descriptions
function this.update()
    if doc and described and described.is_alive() then
        doc.sel_desc.text = described.get_description()
    end
    if doc and status_until > 0 and time.uptime() > status_until then
        doc.status.text = ""
        status_until = 0
    end
end

-- true if the cursor is over the panel (clicks shouldn't reach the world)
function this.is_hovered()
    if not doc then
        return false
    end
    -- a layout's root element is always reachable as "root"
    local panel = doc.root
    local mx, my = unpack(input.get_mouse_pos())
    local px, py = unpack(panel.wpos)
    local w, h = unpack(panel.size)
    return mx >= px and mx < px + w and my >= py and my < py + h
end

local function add_button(slot, label, hint, color, run)
    local col = (slot - 1) % COLS
    local row = math.floor((slot - 1) / COLS)
    doc.commands:add(string.format(
        "<button pos='%d,%d' size='%d,%d' tooltip='%s'%s onclick='DATA.run()'>%s</button>",
        GAP + col * (BUTTON_W + GAP), GAP + row * (BUTTON_H + GAP),
        BUTTON_W, BUTTON_H, hint, color and (" color='" .. color .. "'") or "", label
    ), {run = run})
end

-- slot -> command; explicit slots first, the rest fill free cells in order
local function layout(list, reserved)
    local cells = {}
    for _, cmd in ipairs(list) do
        local slot = cmd.slot
        if slot == reserved then -- hidden under "Отмена" for now
        elseif slot and slot >= 1 and slot <= COLS * ROWS and not cells[slot] then
            cells[slot] = cmd
        elseif slot then
            print("command '" .. cmd.id .. "': slot " .. slot .. " is taken or invalid")
        end
    end
    local free = 1
    for _, cmd in ipairs(list) do
        if not cmd.slot then
            while free <= COLS * ROWS and (cells[free] or free == reserved) do
                free = free + 1
            end
            if free > COLS * ROWS then
                print("command '" .. cmd.id .. "': no free slot")
                break
            end
            cells[free] = cmd
        end
    end
    return cells
end

local function tooltip(cmd)
    local text = cmd.hint or cmd.label
    if cmd.cost then
        text = text .. " (" .. economy.cost_text(cmd.cost) .. ")"
    end
    return text
end

-- mode: active placement mode (its button is highlighted, "Отмена" exits);
-- menu: {id, on_back} while a submenu is open
local function show_buttons(list, on_command, mode, menu)
    doc.commands:clear()
    local menu_id = menu and menu.id
    local visible = {}
    for _, cmd in ipairs(list) do
        if cmd.menu == menu_id then
            table.insert(visible, cmd)
        end
    end
    local reserved = (mode or menu) and CANCEL_SLOT
    for slot, cmd in pairs(layout(visible, reserved)) do
        local active = mode and mode.command.id == cmd.id
        add_button(slot, cmd.label, tooltip(cmd), active and ACTIVE_COLOR or nil,
            function() on_command(cmd.id) end)
    end
    if mode then
        add_button(CANCEL_SLOT, "Отмена", "Выйти из режима (Esc)", nil, mode.on_cancel)
    elseif menu then
        add_button(CANCEL_SLOT, "Назад", "Вернуться к командам", nil, menu.on_back)
    end
end

-- 3D model of the object (def.preview), or its name if there is none.
-- modelviewer takes its camera center only from xml, so it's recreated
-- on every selection change. RMB drag rotates it, the wheel zooms.
local function show_portrait(obj, preview)
    local portrait = doc.portrait
    portrait:clear()
    if not obj and not preview then
        return
    end
    preview = preview or obj.get_preview()
    if preview then
        local c = preview.center or {0, 0, 0}
        portrait:add(string.format(
            "<modelviewer src='%s' size='%d,%d' center='%g,%g,%g' cam-rotation='%s'/>",
            preview.model, PORTRAIT_SIZE, PORTRAIT_SIZE, c[1], c[2], c[3],
            preview.rotation or PORTRAIT_ROTATION
        ))
    else
        portrait:add(string.format(
            "<label pos='0,55' size='%d,20' text-align='center' color='#c8a0b0FF'>%s</label>",
            PORTRAIT_SIZE, obj.get_title()
        ))
    end
end

-- objects: selected RTS objects; on_command(id) is called on button click;
-- default_commands are shown when nothing is selected;
-- mode: {command, preview, on_cancel} while a placement mode is active;
-- menu: {id, on_back} while a submenu is open
function this.show(objects, on_command, default_commands, mode, menu)
    if not doc then
        return
    end
    local first = objects[1]
    described = nil
    if mode then
        show_portrait(nil, mode.preview)
        local prefix = mode.command.place and "Установка: " or "Цель: "
        doc.sel_title.text = prefix .. mode.command.label
        doc.sel_desc.text = mode.command.hint or ""
        show_buttons(first and first.get_commands() or default_commands or {}, on_command, mode, menu)
        return
    end
    if not first then
        show_portrait(nil)
        doc.sel_title.text = ""
        doc.sel_desc.text = ""
        show_buttons(default_commands or {}, on_command, nil, menu)
        return
    end

    show_portrait(first)
    if #objects > 1 then
        doc.sel_title.text = first.get_title() .. " и еще " .. (#objects - 1)
    else
        doc.sel_title.text = first.get_title()
    end
    doc.sel_desc.text = first.get_description()
    described = first
    show_buttons(first.get_commands(), on_command, nil, menu)
end

return this
