-- Core (block ocult:core, 3x2x3): the main building, spawned in the middle
-- of the arena when a world is created (scripts/world.lua). Workers bring
-- resources here (ocult:economy) and new workers are summoned here.
local economy = require "ocult:economy"

local WORKER = "ocult:worker"
local WORKER_COST = {["ocult:stone.item"] = 10}
local WORKER_LIMIT = 5

local function count_workers()
    local n = 0
    for _, e in pairs(entities.get_all()) do
        if e:def_name() == WORKER then
            n = n + 1
        end
    end
    return n
end

return {
    title = "Ядро",
    -- a function: the panel re-reads it every frame
    description = function(self)
        return string.format("Ядро проводящее через себя магию.\nПахнет виноградом...\n\n"
            .. "Склад: %d/%d, свободно %d",
            economy.total(), economy.CAPACITY, economy.free())
    end,
    preview = {model = "ocult_core", center = {1.5, 0.8, 1.5}},
    commands = {
        {id = "storage", label = "Склад", hint = "Открыть склад", slot = 1},
        {id = "market", label = "Рынок", hint = "Рынок (пока не работает)", slot = 2},
        {id = "worker", label = "Культ.", slot = 9,
         hint = "Призвать культиста: " .. economy.cost_text(WORKER_COST)
             .. " (не больше " .. WORKER_LIMIT .. ")"},
    },
    command_storage = function(self)
        hud.show_overlay("ocult:storage", false)
    end,
    command_market = function(self) end,
    command_worker = function(self)
        if count_workers() >= WORKER_LIMIT then
            return "Не больше " .. WORKER_LIMIT .. " культистов"
        end
        if not economy.spend(WORKER_COST) then
            return "Не хватает: " .. economy.cost_text(WORKER_COST)
        end
        -- in front of the south side
        local sx, _, sz = block.get_size(self.id)
        entities.spawn(WORKER, {self.x + sx / 2, self.y + 0.5, self.z + sz + 0.5})
    end,
    pipes = true,
}
