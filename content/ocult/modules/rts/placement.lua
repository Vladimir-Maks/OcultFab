-- Building placement mode: footprint preview under the cursor, snapped to the
-- block grid. LMB - confirm (if the spot is valid), RMB - cancel.
-- Continuous mode (pipes, walls...): stays on after placing, holding LMB
-- places on every new valid cell under the cursor, holding RMB removes blocks
-- of this type under the cursor; Esc finishes (see rts/selection).
local building = require "ocult:rts/building"
local cursor_ray = require "ocult:cursor_ray"
local markers = require "ocult:rts/markers"

local this = {}

local active -- {block_name, on_confirm, on_remove, command, origin, valid, marks, last}

-- the cursor ray goes through other buildings: their hitboxes would hide the
-- floor right behind them (where the ports often are)
local function pick(cam)
    local ignore = {}
    for _, name in ipairs(building.block_names()) do
        if name ~= active.block_name then
            table.insert(ignore, name)
        end
    end
    return cursor_ray.pick(cam, nil, nil, ignore)
end

local function clear_marks()
    if active then
        markers.clear(active.marks)
        active.marks = nil
    end
end

-- on_remove(pos): given -> continuous mode
-- command: the panel command that started the mode (for the UI)
function this.start(block_name, on_confirm, on_remove, command)
    this.cancel()
    active = {block_name = block_name, on_confirm = on_confirm, on_remove = on_remove,
              command = command}
end

function this.cancel()
    clear_marks()
    active = nil
end

function this.is_active()
    return active ~= nil
end

-- command that started the current mode, or nil
function this.get_command()
    return active and active.command
end

function this.get_block()
    return active and active.block_name
end

local function update_preview(cam)
    local hit = pick(cam)
    -- only the top faces of blocks are valid spots
    if not hit or hit.normal[2] ~= 1 then
        clear_marks()
        active.origin = nil
        return
    end
    local origin = building.snap(active.block_name, hit.endpoint, hit.iendpoint[2] + 1)
    local valid = building.can_place(active.block_name, origin)
    local prev = active.origin
    if prev and prev[1] == origin[1] and prev[2] == origin[2] and prev[3] == origin[3]
            and active.valid == valid and active.marks then
        return
    end
    clear_marks()
    local x, z, w, d = building.footprint(active.block_name, origin)
    active.marks = markers.rect(x, origin[2] - 1, z, w, d,
        valid and "blocks:green" or "blocks:red")
    active.origin = origin
    active.valid = valid
end

local function same(a, b)
    return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local function remove_under_cursor(cam)
    local hit = pick(cam)
    if hit and hit.block == block.index(active.block_name) then
        active.on_remove(hit.iendpoint)
        clear_marks()
        active.origin = nil
    end
end

-- left/right: true on the frame the mouse button went down;
-- left_held/right_held: the button is down (used by continuous mode)
function this.update(cam, left, right, left_held, right_held)
    if not active then
        return
    end
    local continuous = active.on_remove ~= nil
    if continuous and right_held then
        remove_under_cursor(cam)
    elseif right then
        this.cancel()
        return
    end
    update_preview(cam)
    local origin = active.origin
    if not origin or not active.valid then
        return
    end
    if continuous then
        if left_held and not same(origin, active.last) then
            active.last = origin
            active.on_confirm(origin)
            -- the spot is taken now: rebuild the preview
            clear_marks()
            active.origin = nil
        elseif not left_held then
            active.last = nil
        end
    elseif left then
        local callback = active.on_confirm
        this.cancel()
        callback(origin)
    end
end

return this
