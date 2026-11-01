-- Extractor (block ocult:extractor, 2x2x2; model exported with --footprint 2).
-- Crafts by recipes (config/recipes.json, "extractor"): the ingredients come
-- from the storage through the pipes into its inputs (ocult:logistics
-- import), after `time` seconds the result goes out through its outputs back
-- to the storage. "Повтор" starts the same recipe again after each one.
-- Whatever is in the pipes when the world closes is lost: a recipe whose
-- ingredients were on the way is dropped.
local building = require "ocult:rts/building"
local machines = require "ocult:machines"
local logistics = require "ocult:logistics"
local economy = require "ocult:economy"

local RECIPES = json.parse(file.read("ocult:config/recipes.json")).extractor
local RETRY = 1.0 -- seconds between attempts while something is missing

local by_id = {}
for _, r in ipairs(RECIPES) do
    by_id[r.id] = r
end

local this = {
    title = "Экстрактор",
    preview = {model = "ocult_extractor", center = {1, 0.8, 1}},
    pipes = true,
    -- cell = {x, z}: 0..1 from the north-west corner; sides follow the
    -- nozzles of the model
    ports = {
        {cell = {0, 0}, side = "west", mode = "out"},
        {cell = {1, 0}, side = "east", mode = "out"},
        {cell = {0, 1}, side = "south", mode = "in"},
        {cell = {1, 1}, side = "south", mode = "in"},
    },
    machine = true,
}

function this.new_state()
    -- phase: idle / importing (ingredients on the way) / crafting / output
    return {phase = "idle", progress = 0, again = false}
end

local PHASES = {
    importing = "Везут ингредиенты",
    crafting = "Работает",
    output = "Отправляет результат",
}

function this.description(self)
    local text = "Перерабатывает ресурсы по рецептам. Ингредиенты приходят по трубе "
        .. "со склада во входы, результат уходит по трубе из выходов.\n\n"
    local state = machines.of(self)
    local recipe = state and state.recipe and by_id[state.recipe]
    if not recipe then
        return text .. "Рецепт не выбран"
    end
    text = text .. recipe.caption .. " (" .. economy.cost_text(recipe.inputs) .. ")"
    if state.again then
        text = text .. ", повтор"
    end
    if state.phase == "crafting" then
        text = text .. string.format("\nРаботает: %d%%", state.progress / recipe.time * 100)
    elseif PHASES[state.phase] then
        text = text .. "\n" .. PHASES[state.phase]
    end
    if state._status then
        text = text .. "\n" .. state._status
    end
    return text
end

function this.commands(self)
    local state = machines.of(self)
    local list = {}
    for i, r in ipairs(RECIPES) do
        table.insert(list, {id = "craft_" .. r.id, label = r.label, slot = i, cost = r.inputs,
            hint = r.caption .. " ×" .. r.count .. " за " .. r.time .. " с"})
    end
    table.insert(list, {id = "again", slot = 9,
        label = state and state.again and "Повт.: да" or "Повт.: нет",
        hint = "Повторять рецепт после каждого"})
    table.insert(list, {id = "cancel", label = "Стоп", slot = 10,
        hint = "Не начинать новый рецепт (текущий доделается)"})
    table.insert(list, {id = "demolish", label = "Разр.", hint = "Разрушить экстрактор", slot = 12})
    return list
end

-- asks the storage for the ingredients; nil or the reason it can't
local function start(self, state)
    local recipe = by_id[state.recipe]
    local ok, err = logistics.import(self, recipe.inputs, function()
        local s = machines.of(self)
        if s then
            s.phase = "crafting"
            s.progress = 0
        end
    end)
    if not ok then
        return err
    end
    state.phase = "importing"
    state._importing = true -- not saved: tells a fresh import from a lost one
    return nil
end

for _, r in ipairs(RECIPES) do
    this["command_craft_" .. r.id] = function(self)
        local state = machines.of(self)
        if state.phase ~= "idle" then
            return "Экстрактор занят"
        end
        state.recipe = r.id
        return start(self, state)
    end
end

function this.command_again(self)
    local state = machines.of(self)
    state.again = not state.again
end

function this.command_cancel(self)
    local state = machines.of(self)
    state.again = false
    if state.phase == "idle" then
        state.recipe = nil
    end
end

function this.command_demolish(self)
    building.demolish(self)
end

function this.update(self, state, dt)
    local recipe = state.recipe and by_id[state.recipe]
    if state.phase == "importing" and not state._importing then
        state.phase = "idle" -- the ingredients were in the pipes on save
    end
    if not recipe then
        state.phase = "idle"
        return
    end
    if state.phase == "crafting" then
        state.progress = state.progress + dt
        if state.progress >= recipe.time then
            state.phase = "output"
            state._retry = 0
        end
    end
    state._retry = (state._retry or 0) - dt
    if state._retry > 0 then
        return
    end
    if state.phase == "output" then
        local ok, err = logistics.export(self, recipe.output, recipe.count)
        if ok then
            state.phase = "idle"
            state._status = nil
        else
            state._status = err
            state._retry = RETRY
        end
    elseif state.phase == "idle" and state.again then
        state._status = start(self, state)
        state._retry = state._status and RETRY or 0
    end
end

return this
