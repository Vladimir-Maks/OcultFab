-- Where the core is and where workers stand to hand resources in.
local arena = require "ocult:arena"
local building = require "ocult:rts/building"

local this = {}

this.BLOCK = "ocult:core"

local origin -- cached {x, y, z}

function this.origin()
    local id = block.index(this.BLOCK)
    if origin and block.get(origin[1], origin[2], origin[3]) == id then
        return origin
    end
    origin = nil
    -- the core is spawned in the middle of the platform
    local p0 = (arena.SIZE - arena.PLATFORM) / 2
    local p1 = p0 + arena.PLATFORM - 1
    for _, b in ipairs(building.find_all(p0, p0, p1, p1, arena.LEVEL)) do
        if b.id == id then
            origin = {b.x, b.y, b.z}
            break
        end
    end
    return origin
end

-- the free floor cell next to the core nearest to `from`, or nil
function this.access_cell(from)
    local o = this.origin()
    if not o then
        return nil
    end
    local sx, _, sz = block.get_size(block.index(this.BLOCK))
    return building.ring_cell(o, sx, sz, from)
end

return this
