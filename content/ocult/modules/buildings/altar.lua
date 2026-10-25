-- Altar (block ocult:altar, 2x1x2; model exported with --footprint 2).
-- Summons cultists and mimics (only here): the price comes from the core
-- through the pipes into the altar's inputs (ocult:logistics), then the
-- creature appears.
local building = require "ocult:rts/building"
local economy = require "ocult:economy"
local logistics = require "ocult:logistics"
local workers = require "ocult:workers"

-- free cell next to the altar, preferably on the south side;
-- height = how high above the floor the entity centre goes
local function spawn_pos(self, height)
    local sx, _, sz = block.get_size(self.id)
    local cell = building.ring_cell({self.x, self.y, self.z}, sx, sz,
        {self.x + sx / 2, self.y, self.z + sz + 1})
    if cell then
        return {cell[1] + 0.5, cell[2] + height, cell[3] + 0.5}
    end
    return {self.x + sx / 2, self.y + height, self.z + sz / 2}
end

return {
    title = "Алтарь",
    description = function(self)
        local text = "Темный алтарь, воздвигнутый ценой жизни."
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
        {id = "mimic", label = "Мимик", slot = 2, cost = economy.MIMIC_COST,
         hint = "Призвать мимика: ходячий склад на " .. economy.MIMIC_CAPACITY
             .. ", общий склад +" .. economy.MIMIC_BONUS},
    },
    command_worker = function(self)
        local reason = workers.check_limit()
        if reason then
            return reason
        end
        local ok, err = logistics.import(self, workers.COST, function()
            workers.spawn_reserved(spawn_pos(self, 0.5))
        end)
        if not ok then
            return err
        end
        workers.reserve()
    end,
    command_mimic = function(self)
        local ok, err = logistics.import(self, economy.MIMIC_COST, function()
            -- taller hitbox than a cultist
            entities.spawn("ocult:mimic", spawn_pos(self, 0.6))
        end)
        if not ok then
            return err
        end
    end,
    pipes = true,
    -- cell = {x, z} from the north-west corner; both nozzles of the model
    -- are on the west side
    ports = {
        {cell = {0, 0}, side = "west", mode = "in"},
        {cell = {0, 1}, side = "west", mode = "in"},
    },
}
