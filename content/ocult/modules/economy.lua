-- Storage: items the workers brought in, by item name
-- ("ocult:stone.item" = 12, ...). Any item can be stored; names shown to
-- the player come from the items themselves. Shared by all scripts, saved
-- with the world (scripts/world.lua calls load/save).
--
-- Items lie in the core and in mimics (ocult:mimic, each one registers its
-- own stock table here). The limit is common: CAPACITY plus
-- MIMIC_BONUS per mimic, for the core and all mimics together; a mimic also
-- holds at most MIMIC_CAPACITY itself. Everything else (get, spend, items...)
-- sees the core and the mimics as one storage.
local this = {}

this.CAPACITY = 100        -- the core alone
this.MIMIC_BONUS = 150     -- every mimic raises the common limit by this
this.MIMIC_CAPACITY = 100  -- what one mimic can hold
-- summoned at an altar (placeholder price)
this.MIMIC_COST = {["ocult:stone.item"] = 30, ["ocult:iron_ore.item"] = 5}

local SAVE_FILE = "world:data/ocult/storage.json"

local stock = {}   -- the core
local mimics = {}  -- uid -> stock table of the mimic

function this.reset()
    stock = {}
end

-- mimic uid -> stock; forgets mimics that are gone
local function live_mimics()
    for uid in pairs(mimics) do
        if not entities.exists(uid) then
            mimics[uid] = nil
        end
    end
    return mimics
end

function this.register_mimic(uid, mimic_stock)
    mimics[uid] = mimic_stock
end

function this.unregister_mimic(uid)
    mimics[uid] = nil
end

local function sum(t)
    local n = 0
    for _, count in pairs(t) do
        n = n + count
    end
    return n
end

function this.capacity()
    local n = this.CAPACITY
    for _ in pairs(live_mimics()) do
        n = n + this.MIMIC_BONUS
    end
    return n
end

function this.get(name)
    local n = stock[name] or 0
    for _, s in pairs(live_mimics()) do
        n = n + (s[name] or 0)
    end
    return n
end

function this.total()
    local n = sum(stock)
    for _, s in pairs(live_mimics()) do
        n = n + sum(s)
    end
    return n
end

function this.free()
    return math.max(0, this.capacity() - this.total())
end

function this.is_full()
    return this.free() == 0
end

-- adds as much as fits into the core; returns how many were taken
function this.add(name, count)
    local taken = math.min(count, this.free())
    if taken > 0 then
        stock[name] = (stock[name] or 0) + taken
    end
    return taken
end

-- items in one mimic
function this.mimic_total(uid)
    return mimics[uid] and sum(mimics[uid]) or 0
end

-- how many more items the mimic can take right now
function this.mimic_free(uid)
    if not mimics[uid] then
        return 0
    end
    return math.max(0, math.min(this.free(), this.MIMIC_CAPACITY - sum(mimics[uid])))
end

-- adds as much as fits into the mimic; returns how many were taken
function this.add_to_mimic(uid, name, count)
    local taken = math.min(count, this.mimic_free(uid))
    if taken > 0 then
        local s = mimics[uid]
        s[name] = (s[name] or 0) + taken
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

-- takes up to n of name from s, returns how many are still missing
local function take(s, name, n)
    local taken = math.min(n, s[name] or 0)
    if taken > 0 then
        s[name] = s[name] - taken
        if s[name] == 0 then
            s[name] = nil
        end
    end
    return n - taken
end

-- from the core first, then from the mimics
function this.spend(cost)
    if not this.can_afford(cost) then
        return false
    end
    for name, n in pairs(cost) do
        n = take(stock, name, n)
        for _, s in pairs(live_mimics()) do
            if n == 0 then
                break
            end
            n = take(s, name, n)
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
    local counts = {}
    for name, n in pairs(stock) do
        counts[name] = n
    end
    for _, s in pairs(live_mimics()) do
        for name, n in pairs(s) do
            counts[name] = (counts[name] or 0) + n
        end
    end
    local list = {}
    for name, n in pairs(counts) do
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
