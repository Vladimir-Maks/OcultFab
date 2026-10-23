-- Player mining: LMB breaks a block of the raised layer into items.
-- Which blocks: "ocult:minable": true in the block definition. What falls
-- out: the block's standard "base:loot" (no loot = the block's own item).
local arena = require "ocult:arena"
local economy = require "ocult:economy"
local drops = require "ocult:drops"
local util = require "base:util"

local this = {}

this.DROP_LIMIT = 20 -- no mining while more items than this lie around

local SIDES = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

-- true if (x, y, z) is a minable block of the raised layer touching air
-- (inside the arena) on at least one horizontal side
function this.can_mine(x, y, z)
    if y ~= arena.LEVEL then
        return false
    end
    local id = block.get(x, y, z)
    if id <= 0 or not block.properties[id]["ocult:minable"] then
        return false
    end
    for _, s in ipairs(SIDES) do
        local nx, nz = x + s[1], z + s[2]
        if arena.inside(nx, nz) and block.get(nx, y, nz) == 0 then
            return true
        end
    end
    return false
end

-- breaks the block; returns true, or false and the reason for the player
function this.try_mine(x, y, z)
    if not this.can_mine(x, y, z) then
        return false, nil
    end
    if economy.is_full() then
        return false, "Склад полон"
    end
    if drops.count() > this.DROP_LIMIT then
        return false, "Слишком много ресурсов на земле"
    end
    local id = block.get(x, y, z)
    block.set(x, y, z, 0, 0)
    for _, loot in ipairs(util.block_loot(id)) do
        drops.spawn(loot.item, loot.count, {x + 0.5, y + 0.3, z + 0.5})
    end
    return true
end

return this
