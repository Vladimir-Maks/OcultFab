-- Base for buildings. A building is a (usually extended) block with a custom
-- model; its RTS definition is modules/buildings/<name>.lua in the block's pack:
--
--   return {
--       title = "...",
--       description = "...",
--       commands = {{id = "foo", label = "..."}},
--       pipes = true, -- adjacent pipes connect to it (bottom layer)
--       command_foo = function(self) ... end, -- self = building handle
--   }

local object = require "ocult:rts/object"
local markers = require "ocult:rts/markers"

local building = {}

local defs = {}

-- RTS definition for a block id, or nil if the block isn't a building
function building.get_def(id)
    local cached = defs[id]
    if cached == nil then
        local prefix, short = parse_path(block.name(id))
        cached = false
        if file.exists(prefix .. ":modules/buildings/" .. short .. ".lua") then
            cached = require(prefix .. ":buildings/" .. short)
        end
        defs[id] = cached
    end
    return cached or nil
end

local function size_of(block_name)
    return block.get_size(block.index(block_name))
end

-- origin of a building of this type centered on the ground point; y is the
-- first air layer. Use odd sizes (1x1, 3x3, ...) so the cursor cell is the center
function building.snap(block_name, point, y)
    local sx, _, sz = size_of(block_name)
    return {
        math.floor(point[1] - sx / 2 + 0.5),
        y,
        math.floor(point[3] - sz / 2 + 0.5),
    }
end

-- middle cell of the footprint (where a morphing unit should stand)
function building.center_cell(block_name, origin)
    local sx, _, sz = size_of(block_name)
    return {origin[1] + math.floor(sx / 2), origin[2], origin[3] + math.floor(sz / 2)}
end

function building.footprint(block_name, origin)
    local sx, _, sz = size_of(block_name)
    return origin[1], origin[3], sx, sz
end

-- free space and solid ground under the whole footprint
function building.can_place(block_name, origin)
    local sx, sy, sz = size_of(block_name)
    local ox, oy, oz = origin[1], origin[2], origin[3]
    for x = ox, ox + sx - 1 do
        for z = oz, oz + sz - 1 do
            if not block.is_solid_at(x, oy - 1, z) then
                return false
            end
            for y = oy, oy + sy - 1 do
                if not block.is_replaceable_at(x, y, z) then
                    return false
                end
            end
        end
    end
    return true
end

function building.place(block_name, origin)
    block.place(origin[1], origin[2], origin[3], block.index(block_name), 0)
    -- lazy: ocult:pipes requires this module
    local sx, _, sz = size_of(block_name)
    require("ocult:pipes").refresh_ring(origin[1], origin[2], origin[3], sx, sz)
end

-- removes the building (handle from building.instance); air in the origin
-- cell makes the engine erase all segments of an extended block
function building.demolish(self)
    local sx, _, sz = block.get_size(self.id)
    block.set(self.x, self.y, self.z, 0, 0)
    require("ocult:pipes").refresh_ring(self.x, self.y, self.z, sx, sz)
end

-- handle for the building occupying (x, y, z) (any segment), or nil
function building.instance(x, y, z)
    local ox, oy, oz = block.seek_origin(x, y, z)
    local id = block.get(ox, oy, oz)
    local def = id > 0 and building.get_def(id)
    if not def then
        return nil
    end
    local sx, _, sz = block.get_size(id)
    local self = {x = ox, y = oy, z = oz, id = id}
    local ring

    object.extend(self, def, function(selected)
        if selected then
            ring = markers.ring(ox, oy - 1, oz, sx, sz, "blocks:green")
        else
            markers.clear(ring)
            ring = nil
        end
    end)

    -- bind definition handlers to this instance
    for k, v in pairs(def) do
        if type(v) == "function" and k:sub(1, 8) == "command_" then
            self[k] = function(...) return v(self, ...) end
        end
    end

    function self.key() return "b" .. ox .. "," .. oy .. "," .. oz end
    function self.is_alive() return block.get(ox, oy, oz) == id end
    function self.get_pos() return {ox + sx / 2, oy, oz + sz / 2} end

    return self
end

return building
