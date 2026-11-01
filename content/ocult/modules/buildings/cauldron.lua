-- Cauldron / crucible (block ocult:cauldron, 1x1): melts items into liquid
-- (ocult:liquids): one item -> `amount` ml in `time` seconds, both set per
-- liquid in config/liquids.json.
-- It doesn't take anything from the storage itself: a pump brings the items
-- into its input. Ready portions go out through the output to the nearest
-- tank with room for them; the liquid can't go to the core.
-- One liquid at a time: while something is melting or waiting to be sent,
-- only items of the same kind are accepted. The liquid inside is an entity
-- (ocult:cauldron_liquid) tinted with the liquid colour, flickering while
-- melting; it isn't saved, the cauldron spawns it again when needed.
local building = require "ocult:rts/building"
local machines = require "ocult:machines"
local liquids = require "ocult:liquids"
local logistics = require "ocult:logistics"

local INPUT_MAX = 2 -- items inside + on the way

local function is_empty(state)
    return state.input == 0 and state.ready == 0 and (state._pending or 0) == 0
end

local function is_melting(state)
    return state.liquid ~= nil and state.input > 0 and state.ready == 0
end

local LIQUID_ENTITY = "ocult:cauldron_liquid"

local function remove_liquid(state)
    local e = state._liquid_uid and entities.get(state._liquid_uid)
    if e then
        e:despawn()
    end
    state._liquid_uid = nil
end

-- keeps the liquid entity in line with the state
local function show(self, state)
    if not state.liquid then
        remove_liquid(state)
        return
    end
    local e = state._liquid_uid and entities.get(state._liquid_uid)
    if not e then
        -- the model is made for the block's corner (tools/cauldron.py)
        e = entities.spawn(LIQUID_ENTITY, {self.x, self.y, self.z}, {
            ocult__cauldron_liquid = {liquid = state.liquid},
        })
        state._liquid_uid = e:get_uid()
    end
    local comp = e:get_component(LIQUID_ENTITY)
    comp.liquid = state.liquid
    comp.melting = is_melting(state)
end

local function tank_for(liquid, amount)
    return function(target, def, mode)
        return logistics.TARGET_IN(mode) and def.can_take_liquid ~= nil
            and def.can_take_liquid(target, machines.of(target), liquid, amount)
    end
end

-- sends the melted liquid (state.ready ml, one item's worth) to a tank with
-- room for all of it; false if there is none
local function send_portion(self, state)
    local liquid, amount = state.liquid, state.ready
    local route, target = logistics.find(self, logistics.PORT_OUT, tank_for(liquid, amount))
    if not route then
        return false
    end
    local def = building.get_def(target.id)
    def.reserve_liquid(target, machines.of(target), liquid, amount)
    state.ready = 0
    logistics.send({liquid = liquid}, route, self.y, function()
        local tank = machines.get(target.x, target.y, target.z)
        if tank then -- not demolished meanwhile
            def.take_liquid(target, tank, liquid, amount)
        end
    end)
    return true
end

return {
    title = "Тигель",
    description = function(self)
        local text = "Плавит ресурсы в жидкость: камень - лава, мана камень - мана, "
            .. "рубинит - жидкий рубинит. Ресурсы подает помпа, жидкость уходит "
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
    preview = {model = "ocult_cauldron", center = {0.5, 0.4, 0.5}},
    commands = {
        {id = "demolish", label = "Разр.", hint = "Разрушить тигель", slot = 12},
    },
    command_demolish = function(self)
        local state = machines.of(self)
        if state then
            remove_liquid(state)
        end
        building.demolish(self)
    end,
    pipes = true,
    -- the model's nozzles IN / OUT (turned by tools/cauldron.py):
    -- input on the west, output on the east
    ports = {
        {cell = {0, 0}, side = "west", mode = "out"},
        {cell = {0, 0}, side = "east", mode = "in"},
    },

    machine = true,
    on_remove = remove_liquid,
    new_state = function()
        return {input = 0, ready = 0, progress = 0}
    end,

    update = function(self, state, dt)
        state._status = nil
        if state.ready > 0 and not send_portion(self, state) then
            state._status = "Нет цистерны со свободным местом"
        end
        if state.input > 0 and state.ready == 0 then
            local liquid = liquids.get(state.liquid)
            state.progress = state.progress + dt
            if state.progress >= liquid.time then
                state.progress = 0
                state.input = state.input - 1
                state.ready = liquid.amount
            end
        end
        if state.liquid and is_empty(state) then
            state.liquid = nil
            state.progress = 0
        end
        show(self, state)
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
        state.liquid = liquids.of_item(name).id
        show(self, state)
    end,
    take_item = function(self, state, name)
        state._pending = math.max(0, (state._pending or 0) - 1)
        state.input = state.input + 1
    end,
}
