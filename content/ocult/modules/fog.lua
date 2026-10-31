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
--
-- Debug (F6 panel, ocult:debug): the fog can be switched off. Then nothing
-- counts as hidden, and the fog/shade blocks around the camera are taken
-- away (remembered, so switching it on puts them back where they were).
local arena = require "ocult:arena"

local this = {}

this.BLOCK = "ocult:fog"
this.Y = arena.LEVEL + 1
this.SHADE_BLOCK = "ocult:shade"
this.SHADE_Y = arena.LEVEL + 16
this.UNIT_VISION = 6
this.BUILDING_VISION = 4

local DEBUG_RADIUS = 40 -- blocks around the camera cleared while the fog is off
local DEBUG_STEP = 4    -- camera moves this far before clearing again

local last_cell = {} -- unit uid -> "x,z" it last revealed from
local disabled = false
local debug_removed = {} -- "x,z" -> true: fog taken away by the debug switch
local debug_center      -- {x, z} the last clearing was around

local function cell_key(x, z)
    return x .. "," .. z
end

function this.is_hidden(x, z)
    if disabled then
        return false
    end
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
            if dx * dx + dz * dz <= r2 then
                if block.get(x, this.Y, z) == fog then
                    block.set(x, this.Y, z, 0, 0)
                    block.set(x, this.SHADE_Y, z, 0, 0)
                end
                -- revealed for real: the debug switch mustn't bring it back
                debug_removed[cell_key(x, z)] = nil
            end
        end
    end
end

-- call every world tick: units reveal around them when they enter a new cell
function this.update()
    for uid, e in pairs(entities.get_all()) do
        local comp = e:get_component(e:def_name())
        if comp and comp.is_rts_object and not comp.def.enemy then
            local pos = e.transform:get_pos()
            local cell = math.floor(pos[1]) .. "," .. math.floor(pos[3])
            if last_cell[uid] ~= cell then
                last_cell[uid] = cell
                this.reveal(pos[1], pos[3], comp.def.vision or this.UNIT_VISION)
            end
        end
    end
end

function this.is_enabled()
    return not disabled
end

function this.set_enabled(flag)
    disabled = not flag
    debug_center = nil
end

-- puts back the fog taken away by the debug switch (cells in chunks that
-- aren't loaded wait for the next call)
local function restore()
    local fog, shade = block.index(this.BLOCK), block.index(this.SHADE_BLOCK)
    for k in pairs(debug_removed) do
        local x, z = k:match("(-?%d+),(-?%d+)")
        x, z = tonumber(x), tonumber(z)
        local id = block.get(x, this.Y, z)
        if id == 0 then
            block.set(x, this.Y, z, fog, 0)
            block.set(x, this.SHADE_Y, z, shade, 0)
        end
        if id ~= -1 then
            debug_removed[k] = nil
        end
    end
end

-- call every frame with the camera focus point
function this.debug_update(cx, cz)
    if not disabled then
        if next(debug_removed) then
            restore()
        end
        return
    end
    if debug_center and math.abs(cx - debug_center[1]) < DEBUG_STEP
            and math.abs(cz - debug_center[2]) < DEBUG_STEP then
        return
    end
    debug_center = {cx, cz}
    local fog = block.index(this.BLOCK)
    local r2 = DEBUG_RADIUS * DEBUG_RADIUS
    for x = math.floor(cx - DEBUG_RADIUS), math.floor(cx + DEBUG_RADIUS) do
        for z = math.floor(cz - DEBUG_RADIUS), math.floor(cz + DEBUG_RADIUS) do
            local dx, dz = x + 0.5 - cx, z + 0.5 - cz
            if dx * dx + dz * dz <= r2 and block.get(x, this.Y, z) == fog then
                block.set(x, this.Y, z, 0, 0)
                block.set(x, this.SHADE_Y, z, 0, 0)
                debug_removed[cell_key(x, z)] = true
            end
        end
    end
end

-- debug state for saving / loading (ocult:debug)
function this.debug_cells()
    local list = {}
    for k in pairs(debug_removed) do
        table.insert(list, k)
    end
    return list
end

function this.set_debug_cells(list)
    debug_removed = {}
    for _, k in ipairs(list) do
        debug_removed[k] = true
    end
end

return this
