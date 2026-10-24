-- Cultist population: price, limit and how many exist or are on the way
-- (summoned by the core or an altar, see ocult:logistics).
local this = {}

this.ENTITY = "ocult:worker"
this.COST = {["ocult:stone.item"] = 10}
this.LIMIT = 5

local pending = 0 -- summons paid for, cultist not spawned yet

function this.count()
    local n = 0
    for _, e in pairs(entities.get_all()) do
        if e:def_name() == this.ENTITY then
            n = n + 1
        end
    end
    return n
end

-- nil if one more can be summoned, otherwise the reason for the player
function this.check_limit()
    if this.count() + pending >= this.LIMIT then
        return "Не больше " .. this.LIMIT .. " прихвостней"
    end
    return nil
end

function this.reserve()
    pending = pending + 1
end

-- spawns a reserved cultist at pos
function this.spawn_reserved(pos)
    pending = math.max(0, pending - 1)
    entities.spawn(this.ENTITY, pos)
end

return this
