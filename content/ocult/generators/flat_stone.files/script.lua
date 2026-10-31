-- Finite arena (sizes in ocult:arena): stone floating in the void, open floor
-- in the middle, around it one block higher stone with ore veins and
-- unbreakable basalt veins (natural walls), all of it under a layer of fog of
-- war (ocult:fog) except the starting platform.
local arena = require "ocult:arena"
local fog_layer = require "ocult:fog"

local stone = block.index("base:stone")
local mine_stone = block.index("ocult:stone") -- minable stone of the raised layer
local bazalt = block.index("base:bazalt")
local fog = block.index(fog_layer.BLOCK)
local shade = block.index(fog_layer.SHADE_BLOCK)

-- ore veins: the arena is split into VEIN_CELL x VEIN_CELL cells, a cell
-- holds at most one vein: a connected blob of 1..max blocks grown by a random
-- walk inside the cell. The last row/column of a cell stays stone, so veins
-- of neighbouring cells never touch. chance = share of cells (rarest last)
local VEIN_CELL = 4
local VEIN_AREA = VEIN_CELL - 1
local ORES = {
    {block = block.index("ocult:iron_ore"), chance = 0.16, max = 24},
    {block = block.index("ocult:mana_ore"), chance = 0.12, max = 16},
    {block = block.index("ocult:rubinyte_ore"), chance = 0.06, max = 4},
}
local STEPS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

-- deterministic 0..1 noise per integer point
local function hash(x, z, salt)
    local v = math.sin(x * 12.9898 + z * 78.233 + salt * 37.719 + SEED % 10007) * 43758.5453
    return v - math.floor(v)
end

local veins = {} -- "cx,cz" -> {block, {["x,z"] = true}} or false

local function vein_of_cell(cx, cz)
    local key = cx .. "," .. cz
    if veins[key] ~= nil then
        return veins[key]
    end
    local roll = hash(cx, cz, 1)
    local acc = 0
    local ore
    for _, o in ipairs(ORES) do
        acc = acc + o.chance
        if roll < acc then
            ore = o
            break
        end
    end
    if not ore then
        veins[key] = false
        return false
    end
    local size = 1 + math.floor(hash(cx, cz, 3) * ore.max)
    local x0, z0 = cx * VEIN_CELL, cz * VEIN_CELL
    local x = x0 + math.floor(hash(cx, cz, 4) * VEIN_AREA)
    local z = z0 + math.floor(hash(cx, cz, 5) * VEIN_AREA)
    local blocks = {[x .. "," .. z] = true}
    local count = 1
    for i = 1, 32 do
        if count >= size then
            break
        end
        local step = STEPS[1 + math.floor(hash(cx * 31 + i, cz * 17 + i, 6) * 4)]
        x = math.max(x0, math.min(x0 + VEIN_AREA - 1, x + step[1]))
        z = math.max(z0, math.min(z0 + VEIN_AREA - 1, z + step[2]))
        if not blocks[x .. "," .. z] then
            blocks[x .. "," .. z] = true
            count = count + 1
        end
    end
    veins[key] = {ore.block, blocks}
    return veins[key]
end

-- basalt veins: same idea on a coarser grid, 12..24 blocks each, never
-- closer than BASALT_CLEARANCE to the starting platform
local BASALT_CELL = 12
local BASALT_AREA = BASALT_CELL - 1
local BASALT_CHANCE = 0.3
local BASALT_MIN, BASALT_MAX = 12, 24
local BASALT_CLEARANCE = 6

local basalt_veins = {} -- "cx,cz" -> {["x,z"] = true} or false

local function near_platform(x, z)
    local p0 = (arena.SIZE - arena.PLATFORM) / 2 - BASALT_CLEARANCE
    local p1 = p0 + arena.PLATFORM + BASALT_CLEARANCE * 2
    return x >= p0 and x < p1 and z >= p0 and z < p1
end

local function basalt_of_cell(cx, cz)
    local key = cx .. "," .. cz
    if basalt_veins[key] ~= nil then
        return basalt_veins[key]
    end
    if hash(cx, cz, 11) >= BASALT_CHANCE then
        basalt_veins[key] = false
        return false
    end
    local size = BASALT_MIN + math.floor(hash(cx, cz, 13) * (BASALT_MAX - BASALT_MIN + 1))
    local x0, z0 = cx * BASALT_CELL, cz * BASALT_CELL
    local x = x0 + math.floor(hash(cx, cz, 14) * BASALT_AREA)
    local z = z0 + math.floor(hash(cx, cz, 15) * BASALT_AREA)
    local blocks = {[x .. "," .. z] = true}
    local count = 1
    for i = 1, 400 do
        if count >= size then
            break
        end
        local step = STEPS[1 + math.floor(hash(cx * 37 + i, cz * 23 + i, 16) * 4)]
        x = math.max(x0, math.min(x0 + BASALT_AREA - 1, x + step[1]))
        z = math.max(z0, math.min(z0 + BASALT_AREA - 1, z + step[2]))
        if not blocks[x .. "," .. z] then
            blocks[x .. "," .. z] = true
            count = count + 1
        end
    end
    -- a vein touching the area around the platform is dropped whole
    -- (cutting it would leave a stub smaller than BASALT_MIN)
    for k in pairs(blocks) do
        local bx, bz = k:match("(-?%d+),(-?%d+)")
        if near_platform(tonumber(bx), tonumber(bz)) then
            basalt_veins[key] = false
            return false
        end
    end
    basalt_veins[key] = blocks
    return blocks
end

local function basalt_at(x, z)
    local vein = basalt_of_cell(math.floor(x / BASALT_CELL), math.floor(z / BASALT_CELL))
    return vein and vein[x .. "," .. z] or false
end

local function ore_at(x, z)
    local vein = vein_of_cell(math.floor(x / VEIN_CELL), math.floor(z / VEIN_CELL))
    if vein and vein[2][x .. "," .. z] then
        return vein[1]
    end
    return nil
end

function generate_heightmap(x, y, w, h, s, inputs)
    return Heightmap(w, h)
end

function place_structures(x, z, w, d, hmap, chunk_height)
    local placements = {}
    local x0, x1 = math.max(x, 0), math.min(x + w, arena.SIZE) - 1
    local z0, z1 = math.max(z, 0), math.min(z + d, arena.SIZE) - 1
    -- note: ":block" positions are world coords (despite the docs saying
    -- chunk-relative), see WorldGenerator::placeBlock
    for bx = x0, x1 do
        for bz = z0, z1 do
            table.insert(placements, {":block", bazalt, {bx, 0, bz}})
            for y = 1, arena.FLOOR_TOP do
                table.insert(placements, {":block", stone, {bx, y, bz}})
            end
            if not arena.in_platform(bx, bz) then
                local top = basalt_at(bx, bz) and bazalt or ore_at(bx, bz) or mine_stone
                table.insert(placements, {":block", top, {bx, arena.LEVEL, bz}})
                table.insert(placements, {":block", fog, {bx, fog_layer.Y, bz}})
                table.insert(placements, {":block", shade, {bx, fog_layer.SHADE_Y, bz}})
            end
        end
    end
    return placements
end
