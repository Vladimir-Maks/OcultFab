-- Tank (block ocult:tank, 2x2x2, model by tools/tank.py): stores up to
-- CAPACITY ml of one liquid at a time. Filled by cauldrons through the pipes;
-- a portion is sent only once the tank has reserved room for it.
-- Buildings nearby may draw liquid straight from it (draw_liquid; eye
-- towers take mana this way).
-- The liquid cube inside (entity ocult:tank_liquid) keeps its size (stretching
-- it would squash the texture) and sinks by whole pixels as the tank
-- empties.
local building = require "ocult:rts/building"
local machines = require "ocult:machines"
local liquids = require "ocult:liquids"

local CAPACITY = 10000 -- ml
local LIQUID_PX = 21    -- height of the liquid cube at full fill (tools/tank.py)

-- nothing inside and nothing on the way: any liquid fits
local function is_empty(state)
    return state.ml == 0 and (state._pending or 0) == 0
end

local LIQUID_ENTITY = "ocult:tank_liquid"

local function remove_liquid(state)
    local e = state._liquid_uid and entities.get(state._liquid_uid)
    if e then
        e:despawn()
    end
    state._liquid_uid = nil
end

-- keeps the liquid cube in line with the state; it isn't saved, the tank
-- spawns it again when needed
local function show(self, state)
    if state.ml == 0 then
        remove_liquid(state)
        return
    end
    local e = state._liquid_uid and entities.get(state._liquid_uid)
    if not e then
        -- the model is made for the block's corner (tools/tank.py)
        e = entities.spawn(LIQUID_ENTITY, {self.x, self.y, self.z}, {
            ocult__tank_liquid = {liquid = state.liquid},
        })
        state._liquid_uid = e:get_uid()
    end
    -- pixels of liquid shown, at least 1 while there is any
    local px = math.max(1, math.floor(state.ml / CAPACITY * LIQUID_PX + 0.5))
    local comp = e:get_component(LIQUID_ENTITY)
    comp.liquid = state.liquid
    comp.sink = (LIQUID_PX - px) / 16
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
        local state = machines.of(self)
        if state then
            remove_liquid(state)
        end
        building.demolish(self)
    end,
    pipes = true,
    ports = {
        {cell = {0, 0}, side = "west", mode = "out"},
        {cell = {1, 1}, side = "east", mode = "in"},
    },

    machine = true,
    on_remove = remove_liquid,
    new_state = function()
        return {ml = 0}
    end,
    update = function(self, state, dt)
        show(self, state)
    end,

    -- takes up to `amount` ml of liquid `id` out of the tank; returns how
    -- much was taken
    draw_liquid = function(self, state, id, amount)
        if state.liquid ~= id then
            return 0
        end
        local taken = math.min(amount, state.ml)
        state.ml = state.ml - taken
        return taken
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
