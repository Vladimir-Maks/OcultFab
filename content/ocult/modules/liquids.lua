-- Liquids melted in the cauldron: config/liquids.json (also read by
-- tools/cauldron_liquids.py, which makes a cauldron model per liquid).
-- Amounts are in millilitres.
local this = {}

-- list of {id, caption, color = {r, g, b} 0..255, source = item name, time}
this.list = json.parse(file.read("ocult:config/liquids.json"))

local by_id, by_source = {}, {}
for i, liquid in ipairs(this.list) do
    liquid.index = i -- cauldron block variant
    by_id[liquid.id] = liquid
    by_source[liquid.source] = liquid
end

function this.get(id)
    return by_id[id]
end

-- the liquid an item melts into, or nil
function this.of_item(name)
    return by_source[name]
end

function this.caption(id)
    local liquid = by_id[id]
    return liquid and liquid.caption or id
end

return this
