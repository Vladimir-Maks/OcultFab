-- Bottom HUD panel: info about the selection + context command buttons.
local this = {}

local LAYOUT = "ocult:rts_panel"
local PORTRAIT_SIZE = 130
local PORTRAIT_ROTATION = "45,-30,0" -- yaw, pitch, roll (degrees)
local COLS = 4
local BUTTON_W, BUTTON_H = 52, 38
local GAP = 4

local doc

function this.open()
    hud.open_permanent(LAYOUT)
    doc = Document.new(LAYOUT)
    this.show({}, nil)
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

local function show_buttons(list, on_command)
    local commands = doc.commands
    commands:clear()
    for i, cmd in ipairs(list) do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        commands:add(string.format(
            "<button pos='%d,%d' size='%d,%d' tooltip='%s' onclick='DATA.run()'>%s</button>",
            GAP + col * (BUTTON_W + GAP), GAP + row * (BUTTON_H + GAP),
            BUTTON_W, BUTTON_H, cmd.hint or cmd.label, cmd.label
        ), {run = function() on_command(cmd.id) end})
    end
end

-- 3D model of the object (def.preview), or its name if there is none.
-- modelviewer takes its camera center only from xml, so it's recreated
-- on every selection change. RMB drag rotates it, the wheel zooms.
local function show_portrait(obj)
    local portrait = doc.portrait
    portrait:clear()
    if not obj then
        return
    end
    local preview = obj.get_preview()
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
-- default_commands are shown when nothing is selected
function this.show(objects, on_command, default_commands)
    if not doc then
        return
    end
    local first = objects[1]
    if not first then
        show_portrait(nil)
        doc.sel_title.text = ""
        doc.sel_desc.text = ""
        show_buttons(default_commands or {}, on_command)
        return
    end

    show_portrait(first)
    if #objects > 1 then
        doc.sel_title.text = first.get_title() .. " и ещё " .. (#objects - 1)
    else
        doc.sel_title.text = first.get_title()
    end
    doc.sel_desc.text = first.get_description()
    show_buttons(first.get_commands(), on_command)
end

return this
