-- Pipe (block ocult:pipe). Placement and shapes: ocult:pipes
local pipes = require "ocult:pipes"

return {
    title = "Труба",
    description = "Соединяется с соседними трубами.",
    preview = {model = "ocult_pipe_k", center = {0.5, 0.25, 0.5}},
    commands = {
        {id = "remove", label = "Убрать", hint = "Разобрать трубу", slot = 12},
    },
    command_remove = function(self)
        pipes.remove(self.x, self.y, self.z)
    end,
}
