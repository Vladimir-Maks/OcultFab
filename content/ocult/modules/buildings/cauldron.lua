-- Cauldron / crucible (block ocult:cauldron, 1x1): melts items into liquid
-- (ocult:liquids): one item -> PORTION ml, the time depends on the liquid.
-- It doesn't take anything from the storage itself: a pump brings the items
-- into its input. Ready portions go out through the output to the nearest
-- tank with room for them; the liquid can't go to the core.
-- One liquid at a time: while something is melting or waiting to be sent,
-- only items of the same kind are accepted. The block variant shows the
-- liquid inside (model per liquid, tools/cauldron_liquids.py).
local building = require "ocult:rts/building"
local machines = require "ocult:machines"
local liquids = require "ocult:liquids"
local logistics = require "ocult:logistics"

local PORTION = 250 -- ml per item
local INPUT_MAX = 2 -- items inside + on the way

local function is_empty(state)
    return state.input == 0 and state.ready == 0 and (state._pending or 0) == 0
end

local function show_liquid(self, id)
    local liquid = id and liquids.get(id)
    block.set_variant(self.x, self.y, self.z, liquid and liquid.index or 0)
end

local function tank_for(liquid)
    return function(target, def, mode)
        return logistics.TARGET_IN(mode) and def.can_take_liquid ~= nil
            and def.can_take_liquid(target, machines.of(target), liquid, PORTION)
    end
end

-- sends a ready portion to a tank; false if there is none with room
local function send_portion(self, state)
    local liquid = state.liquid
    local route, target = logistics.find(self, logistics.PORT_OUT, tank_for(liquid))
    if not route then
        return false
    end
    local def = building.get_def(target.id)
    def.reserve_liquid(target, machines.of(target), liquid, PORTION)
    state.ready = state.ready - PORTION
    logistics.send({liquid = liquid}, route, self.y, function()
        local tank = machines.get(target.x, target.y, target.z)
        if tank then -- not demolished meanwhile
            def.take_liquid(target, tank, liquid, PORTION)
        end
    end)
    return true
end

return {
    title = "Тигель",
    description = function(self)
        local text = "Плавит ресурсы в жидкость: камень - лава, мана камень - мана, "
            .. "рубинит - жидкий рубинит. Ресурсы подаёт помпа, жидкость уходит "
            .. "в цистерну.\n\n"
        local state = machines.of(self)
        if not state or (is_empty(state) and not state.liquid) then
            return text .. "Пусто"
        end
        local liquid = liquids.get(state.liquid)
        text = text .. string.format("%s. Ресурсов внутри: %d", liquid.caption, state.input)
        if state.input > 0 and state.ready == 0 then
            text = text .. string.format("\nПлавка: %d%%", state.progress / liquid.time * 100)
        end
        if state._status then
            text = text .. "\n" .. state._status
        end
        return text
    end,
    preview = {model = "ocult_cauldron_lava", center = {0.5, 0.4, 0.5}},
    commands = {
        {id = "demolish", label = "Разр.", hint = "Разрушить тигель", slot = 12},
    },
    command_demolish = function(self)
        building.demolish(self)
    end,
    pipes = true,
    -- the model's nozzles IN / OUT (turned by tools/cauldron_liquids.py):
    -- input on the west, output on the east
    ports = {
        {cell = {0, 0}, side = "west", mode = "out"},
        {cell = {0, 0}, side = "east", mode = "in"},
    },

    machine = true,
    new_state = function()
        return {input = 0, ready = 0, progress = 0}
    end,

    update = function(self, state, dt)
        state._status = nil
        if state.ready >= PORTION and not send_portion(self, state) then
            state._status = "Нет цистерны со свободным местом"
        end
        if state.input > 0 and state.ready < PORTION then
            local liquid = liquids.get(state.liquid)
            state.progress = state.progress + dt
            if state.progress >= liquid.time then
                state.progress = 0
                state.input = state.input - 1
                state.ready = state.ready + PORTION
            end
        end
        if state.liquid and is_empty(state) then
            state.liquid = nil
            state.progress = 0
            show_liquid(self, nil)
        end
    end,

    -- item receiver (see buildings/pump)
    can_take_item = function(self, state, name)
        local liquid = liquids.of_item(name)
        if not liquid then
            return false
        end
        if not is_empty(state) and state.liquid ~= liquid.id then
            return false
        end
        return state.input + (state._pending or 0) < INPUT_MAX
    end,
    reserve_item = function(self, state, name)
        state._pending = (state._pending or 0) + 1
        local id = liquids.of_item(name).id
        if state.liquid ~= id then
            state.liquid = id
            show_liquid(self, id)
        end
    end,
    take_item = function(self, state, name)
        state._pending = math.max(0, (state._pending or 0) - 1)
        state.input = state.input + 1
    end,
}
