-- Core storage: items the workers brought in, by item name
-- ("ocult:stone.item" = 12, ...). Any item can be stored; names shown to
-- the player come from the items themselves. Shared by all scripts, saved
-- with the world (scripts/world.lua calls load/save).
local this = {}

this.CAPACITY = 100 -- total units of all items

local SAVE_FILE = "world:data/ocult/storage.json"

local stock = {}

function this.reset()
    stock = {}
end

function this.get(name)
    return stock[name] or 0
end

function this.total()
    local sum = 0
    for _, n in pairs(stock) do
        sum = sum + n
    end
    return sum
end

function this.free()
    return math.max(0, this.CAPACITY - this.total())
end

function this.is_full()
    return this.free() == 0
end

-- adds as much as fits; returns how many were taken
function this.add(name, count)
    local taken = math.min(count, this.free())
    if taken > 0 then
        stock[name] = this.get(name) + taken
    end
    return taken
end

-- cost: {["ocult:stone.item"] = 10, ...}
function this.can_afford(cost)
    for name, n in pairs(cost) do
        if this.get(name) < n then
            return false
        end
    end
    return true
end

function this.spend(cost)
    if not this.can_afford(cost) then
        return false
    end
    for name, n in pairs(cost) do
        stock[name] = this.get(name) - n
        if stock[name] == 0 then
            stock[name] = nil
        end
    end
    return true
end

-- display name of an item ("Камень")
function this.caption(name)
    local ok, id = pcall(item.index, name) -- throws for unknown items
    if not ok then
        return name
    end
    return gui.str(item.caption(id), "")
end

-- stored items sorted by display name: list of {name, caption, count}
function this.items()
    local list = {}
    for name, n in pairs(stock) do
        table.insert(list, {name = name, caption = this.caption(name), count = n})
    end
    table.sort(list, function(a, b) return a.caption < b.caption end)
    return list
end

-- "Камень ×10, Железная руда ×2"
function this.cost_text(cost)
    local parts = {}
    for name, n in pairs(cost) do
        table.insert(parts, this.caption(name) .. " ×" .. n)
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

function this.load()
    this.reset()
    if file.exists(SAVE_FILE) then
        for name, n in pairs(json.parse(file.read(SAVE_FILE))) do
            if n > 0 then
                stock[name] = n
            end
        end
    end
end

function this.save()
    file.mkdirs("world:data/ocult")
    file.write(SAVE_FILE, json.tostring(stock))
end

return this
