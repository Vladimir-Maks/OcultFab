-- Pipes: 1x1 blocks on the floor that auto-connect to horizontal neighbours:
-- other pipes and buildings whose definition has `pipes = true`.
--
-- Shapes are block variants (blocks/pipe.json), each modelled with these
-- connections before rotation:
--   0 i - straight  E W
--   1 v - corner    E N
--   2 t - tee       E W N
--   3 k - cross     E W N S
-- The "pane" rotation profile turns them in 90 degree steps.
local building = require "ocult:rts/building"

local this = {}

this.BLOCK = "ocult:pipe"

local E, W, S, N = 1, 2, 4, 8
local DIRS = {
    {bit = E, dx = 1, dz = 0},
    {bit = W, dx = -1, dz = 0},
    {bit = S, dx = 0, dz = 1},
    {bit = N, dx = 0, dz = -1},
}
local SHAPES = {
    [0] = E + W,
    [1] = E + N,
    [2] = E + W + N,
    [3] = E + W + N + S,
}
-- "pane" profile axes from the engine (voxels/Block.cpp): {X, Z} as {x, z}
local ROTATIONS = {
    [0] = {{1, 0}, {0, 1}},
    [1] = {{0, -1}, {1, 0}},
    [2] = {{-1, 0}, {0, -1}},
    [3] = {{0, 1}, {-1, 0}},
}

local function rotate_mask(mask, rotation)
    local axes = ROTATIONS[rotation]
    local result = 0
    for _, d in ipairs(DIRS) do
        if math.floor(mask / d.bit) % 2 == 1 then
            local wx = axes[1][1] * d.dx + axes[2][1] * d.dz
            local wz = axes[1][2] * d.dx + axes[2][2] * d.dz
            for _, o in ipairs(DIRS) do
                if o.dx == wx and o.dz == wz then
                    result = result + o.bit
                end
            end
        end
    end
    return result
end

-- neighbour mask -> {variant, rotation}
local SHAPE_FOR = {}
for variant = 0, 3 do
    for rotation = 0, 3 do
        local mask = rotate_mask(SHAPES[variant], rotation)
        SHAPE_FOR[mask] = SHAPE_FOR[mask] or {variant, rotation}
    end
end
-- dead ends and lonely pipes are straight along their only neighbour
SHAPE_FOR[0] = SHAPE_FOR[E + W]
SHAPE_FOR[E] = SHAPE_FOR[E + W]
SHAPE_FOR[W] = SHAPE_FOR[E + W]
SHAPE_FOR[N] = SHAPE_FOR[N + S]
SHAPE_FOR[S] = SHAPE_FOR[N + S]

local function pipe_id()
    return block.index(this.BLOCK)
end

function this.is_pipe(x, y, z)
    return block.get(x, y, z) == pipe_id()
end

-- a pipe at a neighbouring cell would connect to (x, y, z)
function this.connects_to(x, y, z)
    if this.is_pipe(x, y, z) then
        return true
    end
    local id = block.get(x, y, z)
    if id <= 0 then
        return false
    end
    local def = building.get_def(id)
    return def ~= nil and def.pipes == true
end

-- picks the model and rotation for the pipe at (x, y, z) from its neighbours
function this.refresh(x, y, z)
    if not this.is_pipe(x, y, z) then
        return
    end
    local mask = 0
    for _, d in ipairs(DIRS) do
        if this.connects_to(x + d.dx, y, z + d.dz) then
            mask = mask + d.bit
        end
    end
    local shape = SHAPE_FOR[mask]
    block.set_variant(x, y, z, shape[1])
    block.set_rotation(x, y, z, shape[2])
end

local function refresh_around(x, y, z)
    this.refresh(x, y, z)
    for _, d in ipairs(DIRS) do
        this.refresh(x + d.dx, y, z + d.dz)
    end
end

-- refresh pipes around a w x d footprint (after a building appeared/vanished)
function this.refresh_ring(x0, y, z0, w, d)
    for x = x0 - 1, x0 + w do
        for z = z0 - 1, z0 + d do
            if x < x0 or x >= x0 + w or z < z0 or z >= z0 + d then
                this.refresh(x, y, z)
            end
        end
    end
end

-- pipes stand only on solid blocks (the stone floor), never on other pipes
function this.can_place(x, y, z)
    return block.is_solid_at(x, y - 1, z) and block.is_replaceable_at(x, y, z)
end

function this.place(x, y, z)
    if not this.can_place(x, y, z) then
        return false
    end
    block.set(x, y, z, pipe_id(), 0)
    refresh_around(x, y, z)
    return true
end

function this.remove(x, y, z)
    if not this.is_pipe(x, y, z) then
        return
    end
    block.set(x, y, z, 0, 0)
    refresh_around(x, y, z)
end

return this
