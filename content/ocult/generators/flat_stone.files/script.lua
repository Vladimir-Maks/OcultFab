-- Finite flat arena: SIZE x SIZE blocks of stone floating in the void.
-- Keep in sync with ocult:arena
local SIZE = 100
local FLOOR_TOP = 8 -- y of the walkable surface

local stone = block.index("base:stone")
local bazalt = block.index("base:bazalt")

function generate_heightmap(x, y, w, h, s, inputs)
    return Heightmap(w, h)
end

function place_structures(x, z, w, d, hmap, chunk_height)
    local placements = {}
    local x0, x1 = math.max(x, 0), math.min(x + w, SIZE) - 1
    local z0, z1 = math.max(z, 0), math.min(z + d, SIZE) - 1
    -- note: ":block" positions are world coords (despite the docs saying
    -- chunk-relative), see WorldGenerator::placeBlock
    for bx = x0, x1 do
        for bz = z0, z1 do
            table.insert(placements, {":block", bazalt, {bx, 0, bz}})
            for y = 1, FLOOR_TOP do
                table.insert(placements, {":block", stone, {bx, y, bz}})
            end
        end
    end
    return placements
end
