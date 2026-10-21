-- Default commands, shown in the panel when nothing is selected.
-- Not a selectable object: only the command part of the rts/object interface.
local pipes = require "ocult:pipes"

local this = {}

this.commands = {
    -- continuous: LMB places, RMB removes (command_pipe_remove), Esc exits
    {id = "pipe", label = "Труба", slot = 9,
     hint = "Трубы: ЛКМ - установить, ПКМ - демонтировть, Esc - отменить",
     place = pipes.BLOCK, continuous = true},
}

function this.find_command(id)
    for _, cmd in ipairs(this.commands) do
        if cmd.id == id then
            return cmd
        end
    end
    return nil
end

function this.run_command(id, ...)
    return this["command_" .. id](...)
end

function this.is_alive() return true end

function this.command_pipe(origin)
    pipes.place(origin[1], origin[2], origin[3])
end

function this.command_pipe_remove(pos)
    pipes.remove(pos[1], pos[2], pos[3])
end

return this
