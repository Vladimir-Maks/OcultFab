-- Altar (block ocult:altar, 2x1x2; model exported with --footprint 2).
-- Summons cultists: the price comes from the core through the pipes into
-- the altar's inputs (ocult:logistics), then the cultist appears.
local building = require "ocult:rts/building"
local logistics = require "ocult:logistics"
local workers = require "ocult:workers"

return {
    title = "Алтарь",
    description = function(self)
        local text = "Темный алтарь, воздвигнутый ценой жизни культиста."
        local job = logistics.job(self)
        if job then
            text = text .. string.format("\n\nПризыв: доставлено %d из %d", job.arrived, job.total)
        elseif not logistics.can_import(self) then
            text = text .. "\n\nНет трубы к хранилищу"
        end
        return text
    end,
    preview = {model = "ocult_altar", center = {1, 0.15, 1}},
    commands = {
        {id = "worker", label = "Культ.", slot = 1, cost = workers.COST,
         hint = "Призвать прихвостня"},
    },
    command_worker = function(self)
        local reason = workers.check_limit()
        if reason then
            return reason
        end
        local ok, err = logistics.import(self, workers.COST, function()
            local sx, _, sz = block.get_size(self.id)
            local cell = building.ring_cell({self.x, self.y, self.z}, sx, sz,
                {self.x + sx / 2, self.y, self.z + sz + 1})
            local pos = cell and {cell[1] + 0.5, cell[2] + 0.5, cell[3] + 0.5}
                or {self.x + sx / 2, self.y + 0.5, self.z + sz / 2}
            workers.spawn_reserved(pos)
        end)
        if not ok then
            return err
        end
        workers.reserve()
    end,
    pipes = true,
    -- cell = {x, z} from the north-west corner; both nozzles of the model
    -- are on the west side
    ports = {
        {cell = {0, 0}, side = "west", mode = "in"},
        {cell = {0, 1}, side = "west", mode = "in"},
    },
}
