-- Bottom HUD panel: info about the selection + context command buttons.
local this = {}

local LAYOUT = "ocult:rts_panel"
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

-- objects: selected RTS components; on_command(id) is called on button click
function this.show(objects, on_command)
    if not doc then
        return
    end
    local commands = doc.commands
    commands:clear()

    local first = objects[1]
    if not first then
        doc.portrait_text.text = ""
        doc.sel_title.text = "Ничего не выбрано"
        doc.sel_desc.text = "ЛКМ - выбрать, ПКМ - приказ"
        return
    end

    doc.portrait_text.text = first.get_title()
    if #objects > 1 then
        doc.sel_title.text = first.get_title() .. " и ещё " .. (#objects - 1)
    else
        doc.sel_title.text = first.get_title()
    end
    doc.sel_desc.text = first.get_description()

    for i, cmd in ipairs(first.get_commands()) do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        commands:add(string.format(
            "<button pos='%d,%d' size='%d,%d' tooltip='%s' onclick='DATA.run()'>%s</button>",
            GAP + col * (BUTTON_W + GAP), GAP + row * (BUTTON_H + GAP),
            BUTTON_W, BUTTON_H, cmd.hint or cmd.label, cmd.label
        ), {run = function() on_command(cmd.id) end})
    end
end

return this
