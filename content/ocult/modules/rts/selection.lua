-- Client-side selection and orders.
--   LMB on a unit/building - select it (shift - add/remove)
--   LMB on the ground      - clear selection
--   LMB drag               - select all units inside the box (shift - add)
--   RMB                    - order selected objects (move / rally point)
-- Commands with `place` switch to placement mode first (see rts/placement).
-- With nothing selected the panel shows default commands (rts/commander).
local unit = require "ocult:rts/unit"
local building = require "ocult:rts/building"
local placement = require "ocult:rts/placement"
local cursor_ray = require "ocult:cursor_ray"
local command_panel = require "ocult:rts/command_panel"
local commander = require "ocult:rts/commander"

local this = {}

local BOX_LAYOUT = "ocult:selection_box"
local DRAG_THRESHOLD = 6 -- px before a click turns into a box

local selected = {} -- list of handles (unit components / building handles)
local prev_left, prev_right = false, false
local shown_mode -- placement command the panel currently shows
local drag_start -- screen pos where LMB went down (outside of UI)
local dragging = false
local box_doc
local cam, pid

local refresh

-- who runs panel commands: the selection, or the defaults if it's empty
local function command_holders()
    if #selected == 0 then
        return {commander}
    end
    return selected
end

local function run_command(id)
    local holders = {}
    for _, obj in ipairs(command_holders()) do
        if obj.find_command(id) then
            table.insert(holders, obj)
        end
    end
    if #holders == 0 then
        return
    end
    local cmd = holders[1].find_command(id)
    if cmd.place then
        -- one builder per building, like a zerg drone
        placement.start(cmd.place, function(origin)
            if holders[1].is_alive() then
                holders[1].run_command(id, origin)
            end
        end, cmd.continuous and function(pos)
            holders[1].run_command(id .. "_remove", pos)
        end, cmd)
        refresh()
        return
    end
    for _, obj in ipairs(holders) do
        obj.run_command(id)
    end
    refresh()
end

refresh = function()
    local mode
    shown_mode = placement.get_command()
    if shown_mode then
        local def = building.get_def(block.index(placement.get_block()))
        mode = {
            command = shown_mode,
            preview = def and def.preview,
            on_cancel = function() placement.cancel() end,
        }
    end
    command_panel.show(selected, run_command, commander.commands, mode)
end

function this.set(list)
    for _, obj in ipairs(selected) do
        obj.set_selected(false)
    end
    selected = {}
    for _, obj in ipairs(list) do
        if obj.is_alive() then
            obj.set_selected(true)
            table.insert(selected, obj)
        end
    end
    placement.cancel()
    refresh()
end

function this.get()
    return selected
end

local function toggle(obj)
    local list = {}
    local found = false
    for _, o in ipairs(selected) do
        if o.key() == obj.key() then
            found = true
        else
            table.insert(list, o)
        end
    end
    if not found then
        table.insert(list, obj)
    end
    this.set(list)
end

local function pick()
    local origin, dir = cursor_ray.get_ray(cam)
    return entities.raycast(origin, dir, 500, player.get_entity(pid))
end

-- RTS object under the cursor hit, or nil
local function object_at(hit)
    if not hit then
        return nil
    end
    if hit.entity then
        return unit.get(hit.entity)
    end
    if hit.iendpoint then
        return building.instance(unpack(hit.iendpoint))
    end
    return nil
end

local function on_left_click()
    local obj = object_at(pick())
    local shift = input.is_pressed("key:left-shift")
    if obj then
        if shift then
            toggle(obj)
        else
            this.set({obj})
        end
    elseif not shift then
        this.set({})
    end
end

local function on_right_click()
    local hit = pick()
    if not hit then
        return
    end
    local pos
    if hit.iendpoint then
        pos = {
            hit.iendpoint[1] + hit.normal[1],
            hit.iendpoint[2] + hit.normal[2],
            hit.iendpoint[3] + hit.normal[3],
        }
    else
        pos = {math.floor(hit.endpoint[1]), math.floor(hit.endpoint[2]),
               math.floor(hit.endpoint[3])}
    end
    for _, obj in ipairs(selected) do
        obj.on_order(pos, hit.entity)
    end
end

local function box_rect(a, b)
    local x0, y0 = math.min(a[1], b[1]), math.min(a[2], b[2])
    local x1, y1 = math.max(a[1], b[1]), math.max(a[2], b[2])
    return x0, y0, x1, y1
end

local function show_box(a, b)
    local x0, y0, x1, y1 = box_rect(a, b)
    local w, h = x1 - x0, y1 - y0
    local root = box_doc.root
    root.pos = {x0, y0}
    root.size = {w, h}
    box_doc.top.size = {w, 1}
    box_doc.bottom.pos = {0, h - 1}
    box_doc.bottom.size = {w, 1}
    box_doc.left.size = {1, h}
    box_doc.right.pos = {w - 1, 0}
    box_doc.right.size = {1, h}
end

-- the HUD forces its permanent elements visible every frame, so instead of
-- `visible = false` collapse the box and move it off screen
local function hide_box()
    box_doc.root.pos = {-10, -10}
    box_doc.root.size = {0, 0}
    for _, id in ipairs({"top", "bottom", "left", "right"}) do
        box_doc[id].size = {0, 0}
    end
end

local function on_box_select(a, b)
    local x0, y0, x1, y1 = box_rect(a, b)
    local list = {}
    if input.is_pressed("key:left-shift") then
        for _, obj in ipairs(selected) do
            table.insert(list, obj)
        end
    end
    local keys = {}
    for _, obj in ipairs(list) do
        keys[obj.key()] = true
    end
    for uid, _ in pairs(entities.get_all()) do
        local obj = unit.get(uid)
        if obj and not keys[uid] then
            local sp = cursor_ray.world_to_screen(cam, obj.get_pos())
            if sp and sp[1] >= x0 and sp[1] <= x1 and sp[2] >= y0 and sp[2] <= y1 then
                table.insert(list, obj)
            end
        end
    end
    this.set(list)
end

function this.init(camera, playerid)
    cam, pid = camera, playerid
    command_panel.open()
    hud.open_permanent(BOX_LAYOUT)
    box_doc = Document.new(BOX_LAYOUT)
    -- Esc leaves placement mode instead of opening the pause menu
    -- (handlers run newest first, true stops the chain)
    input.add_callback("key:escape", function()
        if placement.is_active() then
            placement.cancel()
            return true
        end
    end)
    hide_box()
    refresh() -- empty selection: show the default commands right away
end

function this.update()
    -- drop despawned units / destroyed buildings
    local alive = {}
    for _, obj in ipairs(selected) do
        if obj.is_alive() then
            table.insert(alive, obj)
        else
            obj.set_selected(false)
        end
    end
    if #alive ~= #selected then
        selected = alive
        refresh()
    end
    -- before any early return: the mode can end while the cursor is over
    -- the panel (the "Отмена" button)
    if placement.get_command() ~= shown_mode then
        refresh() -- entered/left placement mode (Esc, RMB, new selection...)
    end

    local left = input.is_pressed("mouse:left")
    local right = input.is_pressed("mouse:right")
    local left_click = left and not prev_left
    local left_release = prev_left and not left
    local right_click = right and not prev_right
    prev_left, prev_right = left, right

    -- an ongoing drag keeps going even over the panel
    if drag_start then
        local mouse = input.get_mouse_pos()
        if not dragging then
            local dx, dy = mouse[1] - drag_start[1], mouse[2] - drag_start[2]
            dragging = dx * dx + dy * dy > DRAG_THRESHOLD * DRAG_THRESHOLD
        end
        if dragging then
            show_box(drag_start, mouse)
        end
        if left_release then
            if dragging then
                hide_box()
                on_box_select(drag_start, mouse)
            else
                on_left_click()
            end
            drag_start, dragging = nil, false
        end
        return
    end

    if hud.is_inventory_open() or command_panel.is_hovered() then
        return
    end
    if placement.is_active() then
        placement.update(cam, left_click, right_click, left, right)
        return
    end
    if left_click then
        drag_start = input.get_mouse_pos()
    end
    if right_click then on_right_click() end
end

return this
