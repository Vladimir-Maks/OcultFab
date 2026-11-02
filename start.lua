-- Bootstrap: skip the main menu and drop straight into the world; the game
-- has no main menu of its own, so closing the world quits the game.
local WORLD_NAME = "ocult-dev"
local GENERATOR = "ocult:flat_stone"
local WORLD_DIR = "user:worlds/" .. WORLD_NAME
-- written by the pack when the player confirms the game over
-- (ocult:combat, GAME_OVER_FILE): then the world is deleted and the game
-- quits. Only this script can do that: pack scripts have no `app`.
-- Deleting needs the "write-to-user" permission (project.toml):
-- app.delete_world only asks the player in a dialog.
local GAME_OVER_FLAG = WORLD_DIR .. "/data/ocult/game_over"

app.tick()

if file.exists(WORLD_DIR .. "/world.json") then
    app.open_world(WORLD_NAME)
else
    app.new_world(WORLD_NAME, "666", GENERATOR)
end

local was_open = false
while true do
    app.tick()
    was_open = was_open or world.is_open()
    if file.exists(GAME_OVER_FLAG) then
        app.close_world(false)
        -- let the engine let go of the world before removing its files
        for _ = 1, 3 do
            app.tick()
        end
        file.remove_tree(WORLD_DIR)
        app.quit()
        break
    elseif was_open and not world.is_open() then
        -- "Save and Quit to Menu" in the pause menu (the world is saved)
        app.quit()
        break
    end
end
