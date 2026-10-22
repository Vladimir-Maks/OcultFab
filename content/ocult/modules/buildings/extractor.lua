-- Extractor (block ocult:extractor, 2x2x2; model exported with --footprint 2).
local building = require "ocult:rts/building"

return {
    title = "Экстрактор",
    description = "Извлекает ресурсы. Подключается к трубам.",
    preview = {model = "ocult_extractor", center = {1, 0.8, 1}},
    commands = {
        {id = "demolish", label = "Разр.", hint = "Разрушить экстрактор", slot = 12},
    },
    command_demolish = function(self)
        building.demolish(self)
    end,
    pipes = true,
    -- cell = {x, z}: 0..1 from the north-west corner; sides follow the
    -- nozzles of the model. TODO: check which ones are inputs / outputs
    ports = {
        {cell = {0, 0}, side = "west", mode = "in"},
        {cell = {1, 0}, side = "east", mode = "in"},
        {cell = {0, 1}, side = "south", mode = "out"},
        {cell = {1, 1}, side = "south", mode = "out"},
    },
}
