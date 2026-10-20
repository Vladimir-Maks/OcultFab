-- Building placement mode: footprint preview under the cursor, snapped to the
-- block grid. LMB - confirm (if the spot is valid), RMB - cancel.
local building = require "ocult:rts/building"
local cursor_ray = require "ocult:cursor_ray"
local markers = require "ocult:rts/markers"

local this = {}

local active -- {block_name, on_confirm, origin, valid, marks}

local function clear_marks()
    if active then
        markers.clear(active.marks)
        active.marks = nil
    end
end

function this.start(block_name, on_confirm)
    this.cancel()
    active = {block_name = block_name, on_confirm = on_confirm}
end

function this.cancel()
    clear_marks()
    active = nil
end

function this.is_active()
    return active ~= nil
end

local function update_preview(cam)
    local hit = cursor_ray.pick(cam)
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

-- left/right: true on the frame the mouse button went down
function this.update(cam, left, right)
    if not active then
        return
    end
    if right then
        this.cancel()
        return
    end
    update_preview(cam)
    if left and active.origin and active.valid then
        local callback, origin = active.on_confirm, active.origin
        this.cancel()
        callback(origin)
    end
end

return this
