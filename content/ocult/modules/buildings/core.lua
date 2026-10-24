-- Core (block ocult:core, 3x2x3): the main building, spawned in the middle
-- of the arena when a world is created (scripts/world.lua). Workers bring
-- resources here (ocult:economy) and new workers are summoned here.
-- It is also the storage pipes import from / export to (ocult:logistics).
local economy = require "ocult:economy"
local workers = require "ocult:workers"

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
        {id = "worker", label = "Прихв.", slot = 9, cost = workers.COST,
         hint = "Призвать прихвостня (не больше " .. workers.LIMIT .. ")"},
    },
    command_storage = function(self)
        hud.show_overlay("ocult:storage", false)
    end,
    command_market = function(self) end,
    command_worker = function(self)
        local reason = workers.check_limit()
        if reason then
            return reason
        end
        if not economy.spend(workers.COST) then
            return "Не хватает: " .. economy.cost_text(workers.COST)
        end
        -- in front of the south side
        local sx, _, sz = block.get_size(self.id)
        workers.reserve()
        workers.spawn_reserved({self.x + sx / 2, self.y + 0.5, self.z + sz + 0.5})
    end,
    pipes = true,
    storage = true,
}
