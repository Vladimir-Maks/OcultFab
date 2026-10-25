-- Debug panel switches, see ocult:debug
local debug_flags = require "ocult:debug"
local fog = require "ocult:fog"

function get_free_build()
    return debug_flags.free_build
end

function set_free_build(flag)
    debug_flags.free_build = flag
end

function get_fog()
    return fog.is_enabled()
end

function set_fog(flag)
    fog.set_enabled(flag)
end
