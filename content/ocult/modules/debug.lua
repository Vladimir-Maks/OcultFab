-- Debug switches (F6 panel, layouts/debug.xml), saved with the world:
--   free_build - buildings cost nothing (only buildings: summons, pumps...
--                still use the storage)
--   fog        - fog of war on/off (see ocult:fog)
local fog = require "ocult:fog"

local this = {}

local SAVE_FILE = "world:data/ocult/debug.json"

this.free_build = false

function this.load()
    this.free_build = false
    fog.set_enabled(true)
    fog.set_debug_cells({})
    if not file.exists(SAVE_FILE) then
        return
    end
    local data = json.parse(file.read(SAVE_FILE))
    this.free_build = data.free_build or false
    fog.set_enabled(data.fog ~= false)
    fog.set_debug_cells(data.fog_removed or {})
end

function this.save()
    file.mkdirs("world:data/ocult")
    file.write(SAVE_FILE, json.tostring({
        free_build = this.free_build,
        fog = fog.is_enabled(),
        fog_removed = fog.debug_cells(),
    }))
end

return this
