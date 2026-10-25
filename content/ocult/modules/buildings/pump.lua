-- Item pump (block ocult:pump, 1x1, placeholder box model): takes the chosen
-- resource out of the storage (its input is piped to the core) and sends it
-- through its outputs to buildings that take items (cauldrons).
--
-- Settings (window layouts/pump.xml, "Настроить"):
--   item  - what to pump (any item in the storage)
--   limit - n
--   mode  - "once": pump until n are left in the storage, then stop for good
--                   (until the settings change);
--           "keep": pump while the storage has more than n, resume by itself
--                   when it gets more again
--   spread - "round": outputs take turns; "first": the first output that
--            can take it
-- An item leaves only if some receiver has reserved room for it; with every
-- receiver full the pump waits.
local building = require "ocult:rts/building"
local machines = require "ocult:machines"
local economy = require "ocult:economy"
local logistics = require "ocult:logistics"

local INTERVAL = 0.5 -- seconds between items
local OUTPUTS = 3    -- ports 2..4 (port 1 is the input)

local this = {
    title = "Помпа предметов",
    preview = {model = "ocult_pump", center = {0.5, 0.35, 0.5}},
    commands = {
        {id = "setup", label = "Настр.", hint = "Что и сколько качать", slot = 1},
        {id = "demolish", label = "Разр.", hint = "Разрушить помпу", slot = 12},
    },
    pipes = true,
    ports = {
        {cell = {0, 0}, side = "east", mode = "in"},
        {cell = {0, 0}, side = "north", mode = "out"},
        {cell = {0, 0}, side = "west", mode = "out"},
        {cell = {0, 0}, side = "south", mode = "out"},
    },
    machine = true,
}

-- the pump whose settings window is open ({x, y, z, id}), see pump.xml.lua
this.editing = nil

function this.new_state()
    return {limit = 0, mode = "keep", spread = "round", next = 1, stopped = false}
end

function this.description(self)
    local text = "Подаёт ресурс со склада в здания по трубам: 1 вход, 3 выхода.\n\n"
    local state = machines.of(self)
    if not state or not state.item then
        return text .. "Ресурс не выбран"
    end
    text = text .. string.format("%s, %s %d", economy.caption(state.item),
        state.mode == "once" and "пока на складе не останется" or "пока на складе больше",
        state.limit)
    if state._status then
        text = text .. "\n" .. state._status
    end
    return text
end

function this.command_setup(self)
    this.editing = {x = self.x, y = self.y, z = self.z, id = self.id}
    hud.show_overlay("ocult:pump", false)
end

function this.command_demolish(self)
    building.demolish(self)
end

local function receiver_for(name)
    return function(target, def, mode)
        return logistics.TARGET_IN(mode) and def.can_take_item ~= nil
            and def.can_take_item(target, machines.of(target), name)
    end
end

-- tries output k (1..OUTPUTS); true if an item went out
local function pump_through(self, state, k, route_in)
    local name = state.item
    local route, target = logistics.find(self,
        function(mode, index) return index == k + 1 end, receiver_for(name))
    if not route then
        return false
    end
    local def = building.get_def(target.id)
    def.reserve_item(target, machines.of(target), name)
    economy.spend({[name] = 1})
    -- storage -> pump cell, then pump cell -> receiver
    local full = {}
    for _, cell in ipairs(route_in) do
        table.insert(full, cell)
    end
    for i = 2, #route do
        table.insert(full, route[i])
    end
    logistics.send({item = name}, full, self.y, function()
        local receiver = machines.get(target.x, target.y, target.z)
        if receiver then -- not demolished meanwhile
            def.take_item(target, receiver, name)
        end
    end)
    return true
end

function this.update(self, state, dt)
    state._timer = (state._timer or 0) + dt
    if state._timer < INTERVAL then
        return
    end
    state._timer = 0
    if not state.item then
        state._status = nil
        return
    end
    if state.stopped then
        state._status = "Готово, помпа остановлена"
        return
    end
    if economy.get(state.item) <= state.limit then
        if state.mode == "once" then
            state.stopped = true
        end
        state._status = "На складе не больше " .. state.limit
        return
    end
    local route_in = logistics.storage_route(self)
    if not route_in then
        state._status = "Нет трубы к хранилищу"
        return
    end
    local start = state.spread == "round" and state.next or 1
    for j = 0, OUTPUTS - 1 do
        local k = (start - 1 + j) % OUTPUTS + 1
        if pump_through(self, state, k, route_in) then
            state.next = k % OUTPUTS + 1
            state._status = "Качает"
            return
        end
    end
    state._status = "Получатели заполнены или не подключены"
end

-- new settings from the window: {item, limit, mode, spread}
function this.configure(b, settings)
    local state = machines.of(b)
    if not state then
        return
    end
    for k, v in pairs(settings) do
        state[k] = v
    end
    state.stopped = false
end

return this
