-- Tank (block ocult:tank, 2x1x2, placeholder box model): stores up to
-- CAPACITY ml of one liquid at a time. Filled by cauldrons through the pipes;
-- a portion is sent only once the tank has reserved room for it.
local building = require "ocult:rts/building"
local machines = require "ocult:machines"
local liquids = require "ocult:liquids"

local CAPACITY = 10000 -- ml

-- nothing inside and nothing on the way: any liquid fits
local function is_empty(state)
    return state.ml == 0 and (state._pending or 0) == 0
end

return {
    title = "Цистерна",
    description = function(self)
        local text = string.format("Хранит до %d л одной жидкости.\n\n", CAPACITY / 1000)
        local state = machines.of(self)
        if not state or is_empty(state) then
            return text .. "Пусто"
        end
        return text .. string.format("%s: %d / %d мл", liquids.caption(state.liquid),
            state.ml, CAPACITY)
    end,
    preview = {model = "ocult_tank", center = {1, 0.7, 1}},
    commands = {
        {id = "drain", label = "Слить", hint = "Вылить всё содержимое", slot = 1},
        {id = "demolish", label = "Разр.", hint = "Разрушить цистерну", slot = 12},
    },
    command_drain = function(self)
        local state = machines.of(self)
        state.ml = 0
        if is_empty(state) then
            state.liquid = nil
        end
    end,
    command_demolish = function(self)
        building.demolish(self)
    end,
    pipes = true,
    ports = {
        {cell = {0, 0}, side = "west", mode = "in"},
        {cell = {1, 1}, side = "east", mode = "out"},
    },

    machine = true,
    new_state = function()
        return {ml = 0}
    end,

    -- liquid receiver (see buildings/cauldron)
    can_take_liquid = function(self, state, id, amount)
        if not is_empty(state) and state.liquid ~= id then
            return false
        end
        return state.ml + (state._pending or 0) + amount <= CAPACITY
    end,
    reserve_liquid = function(self, state, id, amount)
        state._pending = (state._pending or 0) + amount
        state.liquid = id
    end,
    take_liquid = function(self, state, id, amount)
        state._pending = math.max(0, (state._pending or 0) - amount)
        state.ml = math.min(CAPACITY, state.ml + amount)
    end,
}
