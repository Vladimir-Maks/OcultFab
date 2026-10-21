-- Cultist: basic worker unit. Can sacrifice itself to become an altar
-- (like a zerg drone morphing into a building).
local unit = require "ocult:rts/unit"
local building = require "ocult:rts/building"

unit.extend(this, {
    title = "Культист",
    description = "Рабочий. Может принести себя в жертву и стать алтарём.",
    color = {0.55, 0.15, 0.2},
    preview = {model = "ocult_worker", center = {0, 0, 0}},
    commands = {
        {id = "stop", label = "Стоп", hint = "Остановиться", slot = 2},
        {id = "altar", label = "Алтарь", hint = "Стать алтарём (выбрать место)",
         slot = 9, place = "ocult:altar"},
    },
})

function command_stop()
    stop()
end

-- walk to the chosen spot, then turn into the building
function command_altar(origin)
    move_to(building.center_cell("ocult:altar", origin), function()
        if building.can_place("ocult:altar", origin) then
            building.place("ocult:altar", origin)
            remove()
        end
    end)
end
