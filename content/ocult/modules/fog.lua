-- Fog of war (shroud): unexplored land is covered by a layer of fog blocks
-- one block above the walking level, placed by the world generator.
-- Units reveal a circle around them as they move, buildings when placed;
-- revealed is revealed for good (the fog blocks are simply removed, so the
-- world save keeps it). Hidden cells can't be mined, built on or gathered.
--
-- High above the fog an invisible light-blocking layer (ocult:shade) keeps
-- unexplored land in the dark; sky light leaking in from the sides gives
-- revealed areas a soft dark border. It is removed together with the fog.
--
-- Vision radius: `vision` in a unit/building definition, or the defaults.
local arena = require "ocult:arena"

local this = {}

this.BLOCK = "ocult:fog"
this.Y = arena.LEVEL + 1
this.SHADE_BLOCK = "ocult:shade"
this.SHADE_Y = arena.LEVEL + 16
this.UNIT_VISION = 6
this.BUILDING_VISION = 4

local last_cell = {} -- unit uid -> "x,z" it last revealed from

function this.is_hidden(x, z)
    return block.get(math.floor(x), this.Y, math.floor(z)) == block.index(this.BLOCK)
end

-- true if any cell of the w x d area at (x0, z0) is hidden
function this.any_hidden(x0, z0, w, d)
    for x = x0, x0 + w - 1 do
        for z = z0, z0 + d - 1 do
            if this.is_hidden(x, z) then
                return true
            end
        end
    end
    return false
end

-- removes the fog in a circle around (cx, cz)
function this.reveal(cx, cz, radius)
    local fog = block.index(this.BLOCK)
    local r2 = radius * radius
    for x = math.floor(cx - radius), math.floor(cx + radius) do
        for z = math.floor(cz - radius), math.floor(cz + radius) do
            local dx, dz = x + 0.5 - cx, z + 0.5 - cz
            if dx * dx + dz * dz <= r2 and block.get(x, this.Y, z) == fog then
                block.set(x, this.Y, z, 0, 0)
                block.set(x, this.SHADE_Y, z, 0, 0)
            end
        end
    end
end

-- call every world tick: units reveal around them when they enter a new cell
function this.update()
    for uid, e in pairs(entities.get_all()) do
        local comp = e:get_component(e:def_name())
        if comp and comp.is_rts_object then
            local pos = e.transform:get_pos()
            local cell = math.floor(pos[1]) .. "," .. math.floor(pos[3])
            if last_cell[uid] ~= cell then
                last_cell[uid] = cell
                this.reveal(pos[1], pos[3], comp.def.vision or this.UNIT_VISION)
            end
        end
    end
end

return this
