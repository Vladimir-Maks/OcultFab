-- State of buildings that work on their own (cauldron, pump, tank): a table
-- per building, keyed by its origin, saved with the world
-- (scripts/world.lua calls load/save/update).
--
-- A building takes part when its definition (modules/buildings/<name>.lua)
-- has:
--   machine = true
--   new_state = function() -> table   initial state (plain data: saved as JSON)
--   update = function(self, state, dt)  optional, called every world tick;
--                                       self = {x, y, z, id} (the origin)
--   on_remove = function(state)        optional, the building is gone: clean
--                                       up (e.g. entities it spawned)
-- State fields starting with "_" are not saved: counters of what travels in
-- the pipes, which is lost when the world closes (see ocult:logistics).
-- States of demolished buildings are dropped by update().
local building = require "ocult:rts/building"

local this = {}

local SAVE_FILE = "world:data/ocult/machines.json"

local states = {} -- "x,y,z" -> state

local function key(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function machine_def(id)
    local def = id > 0 and building.get_def(id)
    return def and def.machine and def or nil
end

-- state of the machine at origin (x, y, z), created on first use;
-- nil if there is no machine there
function this.get(x, y, z)
    local k = key(x, y, z)
    local state = states[k]
    if state then
        return state
    end
    local def = machine_def(block.get(x, y, z))
    if not def then
        return nil
    end
    state = def.new_state()
    states[k] = state
    return state
end

-- state of the building handle b ({x, y, z, ...})
function this.of(b)
    return this.get(b.x, b.y, b.z)
end

-- origins of all machines with a state: list of {x, y, z, id}
function this.all()
    local list = {}
    for k in pairs(states) do
        local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
        x, y, z = tonumber(x), tonumber(y), tonumber(z)
        local id = block.get(x, y, z)
        if machine_def(id) then
            table.insert(list, {x = x, y = y, z = z, id = id})
        end
    end
    return list
end

function this.forget(x, y, z)
    states[key(x, y, z)] = nil
end

function this.update(dt)
    for k, state in pairs(states) do
        local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
        x, y, z = tonumber(x), tonumber(y), tonumber(z)
        local id = block.get(x, y, z)
        if id ~= -1 then -- -1: chunk not loaded, keep it as it is
            local def = machine_def(id)
            if not def or block.is_segment(x, y, z) then
                states[k] = nil -- demolished
                if state._def and state._def.on_remove then
                    state._def.on_remove(state)
                end
            else
                state._def = def -- for on_remove, when the block is gone
                if def.update then
                    def.update({x = x, y = y, z = z, id = id}, state, dt)
                end
            end
        end
    end
end

function this.load()
    states = {}
    if not file.exists(SAVE_FILE) then
        return
    end
    for k, state in pairs(json.parse(file.read(SAVE_FILE))) do
        states[k] = state
    end
end

function this.save()
    file.mkdirs("world:data/ocult")
    local out = {}
    for k, state in pairs(states) do
        local copy = {}
        for field, value in pairs(state) do
            if field:sub(1, 1) ~= "_" then
                copy[field] = value
            end
        end
        out[k] = copy
    end
    file.write(SAVE_FILE, json.tostring(out))
end

return this
