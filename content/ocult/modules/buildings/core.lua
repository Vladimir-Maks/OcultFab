-- Core (block ocult:core, 3x2x3): the main building, spawned in the middle
-- of the arena when a world is created (scripts/world.lua).
return {
    title = "Ядро",
    description = "Ядро проводящее через себя магию.\nПахнет виноградом...",
    preview = {model = "ocult_core", center = {1.5, 0.8, 1.5}},
    commands = {
        {id = "storage", label = "Склад", hint = "Хранилище (пока не работает)", slot = 1},
        {id = "market", label = "Рынок", hint = "Рынок (пока не работает)", slot = 2},
    },
    command_storage = function(self) end,
    command_market = function(self) end,
    pipes = true,
}
