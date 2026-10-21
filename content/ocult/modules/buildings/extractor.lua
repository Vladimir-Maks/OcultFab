-- Extractor (block ocult:extractor, 2x3x2; model exported with --scale 2).
local building = require "ocult:rts/building"

return {
    title = "Экстрактор",
    description = "Извлекает ресурсы. Подключается к трубам.",
    preview = {model = "ocult_extractor", center = {1, 1.1, 1}},
    commands = {
        {id = "demolish", label = "Разр.", hint = "Разрушить экстрактор", slot = 12},
    },
    command_demolish = function(self)
        building.demolish(self)
    end,
    pipes = true,
}
