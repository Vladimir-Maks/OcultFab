-- dev bootstrap: skip the main menu and drop straight into a world
local WORLD_NAME = "ocult-dev"
local GENERATOR = "ocult:flat_stone"

app.tick()

if file.exists("user:worlds/" .. WORLD_NAME .. "/world.json") then
    app.open_world(WORLD_NAME)
else
    app.new_world(WORLD_NAME, "666", GENERATOR)
end
