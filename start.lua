-- dev bootstrap: skip the main menu and drop straight into a world
local WORLD_NAME = "ocult-dev"
local GENERATOR = "ocult:flat_stone"
-- written by the pack when the player confirms the game over
-- (ocult:combat, GAME_OVER_FILE): then the world is deleted and the game
-- quits. Only this script can do that: pack scripts have no `app`.
local GAME_OVER_FLAG = "user:worlds/" .. WORLD_NAME .. "/data/ocult/game_over"

app.tick()

if file.exists("user:worlds/" .. WORLD_NAME .. "/world.json") then
    app.open_world(WORLD_NAME)
else
    app.new_world(WORLD_NAME, "666", GENERATOR)
end

while true do
    app.tick()
    if file.exists(GAME_OVER_FLAG) then
        app.close_world(false)
        app.delete_world(WORLD_NAME)
        app.quit()
        break
    end
end
