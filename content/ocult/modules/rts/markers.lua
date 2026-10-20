-- Ground markers drawn with block wraps (only the top face is shown).
local this = {}

local function top_wrap(x, y, z, texture)
    local id = gfx.blockwraps.wrap({x, y, z}, texture, 0.6)
    gfx.blockwraps.set_faces(id, nil, nil, nil, texture, nil, nil)
    return id
end

-- filled rectangle on top of the blocks at layer y
function this.rect(x0, y, z0, w, d, texture)
    local ids = {}
    for x = x0, x0 + w - 1 do
        for z = z0, z0 + d - 1 do
            table.insert(ids, top_wrap(x, y, z, texture))
        end
    end
    return ids
end

-- one-block frame around a w x d rectangle on layer y
function this.ring(x0, y, z0, w, d, texture)
    local ids = {}
    for x = x0 - 1, x0 + w do
        for z = z0 - 1, z0 + d do
            if x < x0 or x >= x0 + w or z < z0 or z >= z0 + d then
                table.insert(ids, top_wrap(x, y, z, texture))
            end
        end
    end
    return ids
end

function this.clear(ids)
    for _, id in ipairs(ids or {}) do
        gfx.blockwraps.unwrap(id)
    end
end

return this
