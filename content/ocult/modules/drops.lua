-- Items on the ground: the standard "base:drop" entities (one item stack
-- each; equal stacks lying close merge by themselves).
local this = {}

local ENTITY = "base:drop"
local COMPONENT = "base:drop"

-- drop component of an entity, or nil. Its `dropitem` = {id, count};
-- workers mark the one they go for in `claimed_by`
function this.get(uid)
    local e = entities.get(uid)
    if not e then
        return nil
    end
    return e:get_component(COMPONENT)
end

-- base:drop merges equal items whose centres are closer than ~0.45 blocks
-- into one stack (= one item on screen); a ring this wide keeps up to 5
-- items of one block apart
local RING_RADIUS = 0.4

-- count separate items (numeric id) laid in a ring around pos
function this.spawn(item_id, count, pos)
    local name = item.name(item_id)
    local start = math.random() * math.pi * 2
    for i = 1, count do
        local r = count > 1 and RING_RADIUS or 0
        local a = start + (i - 1) * math.pi * 2 / count
        entities.spawn(ENTITY, {pos[1] + math.cos(a) * r, pos[2], pos[3] + math.sin(a) * r},
            {base__drop = {item = name, count = 1}})
    end
end

-- all drops: list of {uid, comp, pos}; filter(pos, comp) optional
function this.list(filter)
    local result = {}
    for uid, e in pairs(entities.get_all()) do
        local comp = e:get_component(COMPONENT)
        if comp and (comp.dropitem.count or 0) > 0 then
            local pos = e.transform:get_pos()
            if not filter or filter(pos, comp) then
                table.insert(result, {uid = uid, comp = comp, pos = pos})
            end
        end
    end
    return result
end

-- items lying around (stacks counted by their size)
function this.count()
    local n = 0
    for _, d in ipairs(this.list()) do
        n = n + d.comp.dropitem.count
    end
    return n
end

-- the nearest unclaimed drop to `from` satisfying filter, or nil
function this.nearest_free(from, filter)
    local best, best_d
    for _, d in ipairs(this.list(filter)) do
        if not d.comp.claimed_by or not entities.exists(d.comp.claimed_by) then
            local dx, dz = d.pos[1] - from[1], d.pos[3] - from[3]
            local dist = dx * dx + dz * dz
            if not best or dist < best_d then
                best, best_d = d, dist
            end
        end
    end
    return best
end

-- takes one item out of the stack; returns its item name or nil
function this.take_one(uid)
    local comp = this.get(uid)
    if not comp or (comp.dropitem.count or 0) <= 0 then
        return nil
    end
    local name = item.name(comp.dropitem.id)
    comp.dropitem.count = comp.dropitem.count - 1
    if comp.dropitem.count <= 0 then
        entities.get(uid):despawn()
    end
    return name
end

return this
