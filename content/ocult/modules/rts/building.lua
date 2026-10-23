-- Base for buildings. A building is a (usually extended) block with a custom
-- model; its RTS definition is modules/buildings/<name>.lua in the block's pack:
--
--   return {
--       title = "...",
--       description = "...",
--       commands = {{id = "foo", label = "..."}},
--       pipes = true, -- adjacent pipes connect to it (bottom layer)
--       -- optional: only these spots accept pipes; without it any side works
--       -- as both input and output. cell = {x, z} footprint cell counted from
--       -- the building origin (north-west corner), side = north (-Z) /
--       -- south (+Z) / east (+X) / west (-X), mode = "in" / "out"
--       ports = {
--           {cell = {0, 0}, side = "west", mode = "in"},
--       },
--       command_foo = function(self) ... end, -- self = building handle
--   }

local object = require "ocult:rts/object"
local arena = require "ocult:arena"
local markers = require "ocult:rts/markers"

local building = {}

building.SIDES = {
    north = {0, -1},
    south = {0, 1},
    east = {1, 0},
    west = {-1, 0},
}
building.ANY = "any" -- port mode when the building has no `ports`

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

local block_names

-- names of all blocks that are buildings (have a modules/buildings def)
function building.block_names()
    if not block_names then
        block_names = {}
        for id = 0, block.defs_count() - 1 do
            if building.get_def(id) then
                table.insert(block_names, block.name(id))
            end
        end
    end
    return block_names
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

-- the free floor cell around a sx x sz footprint at origin nearest to
-- `from` (pipes count as free: units walk over them), or nil
function building.ring_cell(origin, sx, sz, from)
    local pipe = block.index("ocult:pipe")
    local best, best_d
    for x = origin[1] - 1, origin[1] + sx do
        for z = origin[3] - 1, origin[3] + sz do
            local ring = x < origin[1] or x >= origin[1] + sx
                or z < origin[3] or z >= origin[3] + sz
            local id = block.get(x, origin[2], z)
            if ring and (id == 0 or id == pipe) and block.is_solid_at(x, origin[2] - 1, z) then
                local dx, dz = x + 0.5 - from[1], z + 0.5 - from[3]
                local d = dx * dx + dz * dz
                if not best or d < best_d then
                    best, best_d = {x, origin[2], z}, d
                end
            end
        end
    end
    return best
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

-- only on the floor level (the platform and mined-out ground), never on
-- top of the raised stone
function building.is_floor_level(y)
    return y == arena.LEVEL
end

-- free space and solid ground under the whole footprint
function building.can_place(block_name, origin)
    local sx, sy, sz = size_of(block_name)
    local ox, oy, oz = origin[1], origin[2], origin[3]
    if not building.is_floor_level(oy) then
        return false
    end
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

-- mode of the port at building cell (x, y, z) facing direction (dx, dz),
-- i.e. a pipe standing at (x + dx, y, z + dz); nil if pipes can't attach there
function building.port_mode(x, y, z, dx, dz)
    local id = block.get(x, y, z)
    if id <= 0 then
        return nil
    end
    local def = building.get_def(id)
    if not def or not def.pipes then
        return nil
    end
    local ox, oy, oz = block.seek_origin(x, y, z)
    if y ~= oy then
        return nil -- pipes lie on the floor: bottom layer only
    end
    if not def.ports then
        return building.ANY
    end
    for _, port in ipairs(def.ports) do
        local side = building.SIDES[port.side]
        if ox + port.cell[1] == x and oz + port.cell[2] == z
                and side[1] == dx and side[2] == dz then
            return port.mode
        end
    end
    return nil
end

-- world positions of the ports of a building at origin (ox, oy, oz):
-- list of {x, y, z, dx, dz, mode}; buildings without `ports` get every
-- outer side of the bottom layer with mode building.ANY
function building.ports(id, ox, oy, oz)
    local def = building.get_def(id)
    if not def or not def.pipes then
        return {}
    end
    local list = {}
    if def.ports then
        for _, port in ipairs(def.ports) do
            local side = building.SIDES[port.side]
            table.insert(list, {ox + port.cell[1], oy, oz + port.cell[2],
                                side[1], side[2], port.mode})
        end
        return list
    end
    local sx, _, sz = block.get_size(id)
    for cx = 0, sx - 1 do
        for cz = 0, sz - 1 do
            for _, side in pairs(building.SIDES) do
                local nx, nz = cx + side[1], cz + side[2]
                if nx < 0 or nx >= sx or nz < 0 or nz >= sz then
                    table.insert(list, {ox + cx, oy, oz + cz, side[1], side[2], building.ANY})
                end
            end
        end
    end
    return list
end

-- origins of all placed buildings on layer y inside the x/z area
function building.find_all(x0, z0, x1, z1, y)
    local found = {}
    for x = x0, x1 do
        for z = z0, z1 do
            local id = block.get(x, y, z)
            if id > 0 and not block.is_segment(x, y, z) and building.get_def(id) then
                table.insert(found, {id = id, x = x, y = y, z = z})
            end
        end
    end
    return found
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
