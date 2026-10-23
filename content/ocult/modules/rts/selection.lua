-- Client-side selection and orders.
--   LMB on a unit/building - select it (shift - add/remove)
--   LMB on the ground      - clear selection
--   LMB on minable stone   - mine it (see ocult:mining)
--   LMB drag               - select all units inside the box (shift - add)
--   RMB                    - order selected objects (move / rally point);
--                            on an item (or right next to it) workers gather
-- Commands with `place` switch to placement mode first (see rts/placement).
-- Commands with `target = "zone"` ask for an area first: LMB click - a square
-- around the point, LMB drag - a rectangle; RMB / Esc cancel. The handler
-- gets {x0, z0, x1, z1}. A handler returning a string shows it as a message.
-- `submenu` commands switch the command card (see rts/command_panel); a
-- `cost` is checked before a placement starts (the handler pays).
-- With nothing selected the panel shows default commands (rts/commander).
local unit = require "ocult:rts/unit"
local building = require "ocult:rts/building"
local placement = require "ocult:rts/placement"
local cursor_ray = require "ocult:cursor_ray"
local command_panel = require "ocult:rts/command_panel"
local commander = require "ocult:rts/commander"
local port_overlay = require "ocult:rts/port_overlay"
local rts_camera = require "ocult:rts_camera"
local mining = require "ocult:mining"
local drops = require "ocult:drops"
local economy = require "ocult:economy"

local this = {}

local BOX_LAYOUT = "ocult:selection_box"
local DRAG_THRESHOLD = 6 -- px before a click turns into a box
local ZONE_RADIUS = 15   -- blocks around the clicked point for a zone target
local ITEM_PICK_RADIUS = 0.8 -- RMB this close to an item counts as clicking it

local selected = {} -- list of handles (unit components / building handles)
local prev_left, prev_right = false, false
local shown_mode -- mode command the panel currently shows
local targeting  -- {cmd, holders} while waiting for a zone
local menu_id    -- open submenu of the command card, nil = root
local drag_start -- screen pos where LMB went down (outside of UI)
local dragging = false
local box_doc
local cam, pid

local refresh

-- command of the active mode: placement or zone targeting
local function mode_command()
    return placement.get_command() or (targeting and targeting.cmd)
end

local function cancel_modes()
    placement.cancel()
    targeting = nil
end

local function report(result)
    if type(result) == "string" then
        command_panel.notify(result)
    end
end

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
    if cmd.submenu then
        menu_id = cmd.submenu
        refresh()
        return
    end
    if cmd.cost and not economy.can_afford(cmd.cost) then
        command_panel.notify("Не хватает: " .. economy.cost_text(cmd.cost))
        return
    end
    if cmd.target == "zone" then
        placement.cancel()
        targeting = {cmd = cmd, holders = holders}
        refresh()
        return
    end
    if cmd.place then
        targeting = nil
        -- one builder per building, like a zerg drone
        placement.start(cmd.place, function(origin)
            if holders[1].is_alive() then
                report(holders[1].run_command(id, origin))
            end
        end, cmd.continuous and function(pos)
            holders[1].run_command(id .. "_remove", pos)
        end, cmd)
        refresh()
        return
    end
    for _, obj in ipairs(holders) do
        report(obj.run_command(id))
    end
    refresh()
end

refresh = function()
    local mode
    shown_mode = mode_command()
    if shown_mode then
        local def = placement.get_block() and building.get_def(block.index(placement.get_block()))
        mode = {
            command = shown_mode,
            preview = def and def.preview,
            on_cancel = cancel_modes,
        }
    end
    local menu = menu_id and {
        id = menu_id,
        on_back = function()
            menu_id = nil
            refresh()
        end,
    }
    command_panel.show(selected, run_command, commander.commands, mode, menu)
    port_overlay.set_visible(shown_mode ~= nil and shown_mode.show_ports == true, cam,
        rts_camera.get_focus())
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
    cancel_modes()
    menu_id = nil
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
    local hit = pick()
    local obj = object_at(hit)
    local shift = input.is_pressed("key:left-shift")
    if obj then
        if shift then
            toggle(obj)
        else
            this.set({obj})
        end
    elseif hit and not hit.entity and hit.iendpoint
            and mining.can_mine(unpack(hit.iendpoint)) then
        -- mining keeps the selection
        local _, reason = mining.try_mine(unpack(hit.iendpoint))
        if reason then
            command_panel.notify(reason)
        end
    elseif not shift then
        this.set({})
    end
end

-- floor point under a screen position (buildings are see-through)
local function ground_point(screen)
    local hit = cursor_ray.pick(cam, screen, nil, building.block_names())
    return hit and hit.endpoint
end

local function finish_targeting(a, b, dragged)
    local t = targeting
    targeting = nil
    local zone
    if dragged then
        local p, q = ground_point(a), ground_point(b)
        if p and q then
            zone = {math.min(p[1], q[1]), math.min(p[3], q[3]),
                    math.max(p[1], q[1]), math.max(p[3], q[3])}
        end
    else
        local p = ground_point(b)
        if p then
            zone = {p[1] - ZONE_RADIUS, p[3] - ZONE_RADIUS,
                    p[1] + ZONE_RADIUS, p[3] + ZONE_RADIUS}
        end
    end
    if zone then
        for _, obj in ipairs(t.holders) do
            if obj.is_alive() then
                report(obj.run_command(t.cmd.id, zone))
            end
        end
    end
    refresh()
end

local function walkable(x, y, z)
    local id = block.get(x, y, z)
    return (id == 0 or block.name(id) == "ocult:pipe") and block.is_solid_at(x, y - 1, z)
end

-- up to n distinct walkable cells around pos (pos first), so a group
-- doesn't fight for one cell
local function spread_cells(pos, n)
    local cells, seen, queue = {}, {}, {pos}
    seen[pos[1] .. "," .. pos[3]] = true
    local head = 1
    while head <= #queue and #cells < n and head < 200 do
        local c = queue[head]
        head = head + 1
        if walkable(c[1], c[2], c[3]) then
            table.insert(cells, c)
        end
        for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            local nc = {c[1] + d[1], c[2], c[3] + d[2]}
            local key = nc[1] .. "," .. nc[3]
            if not seen[key] then
                seen[key] = true
                table.insert(queue, nc)
            end
        end
    end
    return cells
end

-- an item under the cursor: hit directly, or lying right next to the hit point
local function item_at(hit)
    if hit.entity and drops.get(hit.entity) then
        return hit.entity
    end
    local p = hit.endpoint
    local best, best_d
    for _, d in ipairs(drops.list()) do
        local dx, dz = d.pos[1] - p[1], d.pos[3] - p[3]
        local dist = dx * dx + dz * dz
        if dist <= ITEM_PICK_RADIUS * ITEM_PICK_RADIUS and (not best or dist < best_d) then
            best, best_d = d.uid, dist
        end
    end
    return best
end

local function on_right_click()
    local hit = pick()
    if not hit then
        return
    end
    local item = item_at(hit)
    if item then
        for _, obj in ipairs(selected) do
            obj.on_order(nil, item)
        end
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
    local units = {}
    for _, obj in ipairs(selected) do
        if type(obj.key()) == "number" then
            table.insert(units, obj)
        else
            obj.on_order(pos, hit.entity, hit.iendpoint) -- buildings: rally point
        end
    end
    local cells = spread_cells(pos, #units)
    for i, obj in ipairs(units) do
        obj.on_order(cells[i] or pos, hit.entity, hit.iendpoint)
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
        if mode_command() then
            cancel_modes()
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
    if mode_command() ~= shown_mode then
        if not mode_command() then
            menu_id = nil -- a build is placed / cancelled: back to the root card
        end
        refresh() -- entered/left a mode (Esc, RMB, new selection...)
    end
    command_panel.update()

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
            hide_box()
            if targeting then
                finish_targeting(drag_start, mouse, dragging)
            elseif dragging then
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
    if targeting and right_click then
        targeting = nil
        refresh()
        return
    end
    if left_click then
        drag_start = input.get_mouse_pos()
    end
    if right_click then on_right_click() end
end

return this
