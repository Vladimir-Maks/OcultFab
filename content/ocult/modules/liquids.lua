-- Liquids melted in the cauldron: config/liquids.json. There are no
-- textures per liquid: the grey liquid model is tinted with `color` by code
-- (components/cauldron_liquid, components/tank_liquid,
-- components/pipe_item).
-- Amounts are in millilitres.
local this = {}

-- list of {id, caption, color = {r, g, b} 0..255, cauldron recipe: one
-- `source` item melts into `amount` ml in `time` seconds}
this.list = json.parse(file.read("ocult:config/liquids.json"))

local by_id, by_source = {}, {}
for _, liquid in ipairs(this.list) do
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

-- tint for set_color: {r, g, b} 0..1 (white for unknown ids)
function this.color(id)
    local liquid = by_id[id]
    if not liquid then
        return {1, 1, 1}
    end
    local c = liquid.color
    return {c[1] / 255, c[2] / 255, c[3] / 255}
end

function this.caption(id)
    local liquid = by_id[id]
    return liquid and liquid.caption or id
end

return this
