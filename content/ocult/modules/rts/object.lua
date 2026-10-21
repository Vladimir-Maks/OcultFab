-- Master script for everything selectable in the RTS layer.
--
-- Units are entities: their main component is named like the entity
-- ("ocult:worker" -> scripts/components/worker.lua) and calls unit.extend(this, def).
-- Buildings are blocks with a model: their definition lives in
-- modules/buildings/<name>.lua and building.instance(x, y, z) wraps a placed block.
-- Both end up with the interface below, so selection/UI treat them the same.
--
-- def fields:
--   title       - display name
--   description - text for the info panel
--   preview     - {model = "name", center = {x, y, z}} 3D portrait in the panel;
--                 center is the point the portrait camera looks at (model space)
--   commands    - list of {id=, label=, hint=, slot=, place=}; slot is the cell
--                 of the 4x3 command grid (see rts/command_panel); a click calls
--                 command_<id>(...). With `place = "pack:block"` the player first
--                 picks a spot for that building; the handler gets its origin.

local object = {}

-- target: table that receives the interface (component env or building handle)
-- highlight(flag): visual feedback for selection
function object.extend(target, def, highlight)
    local selected = false

    target.is_rts_object = true
    target.def = def

    function target.get_title() return def.title or "?" end
    function target.get_description() return def.description or "" end
    function target.get_preview() return def.preview end
    function target.get_commands() return def.commands or {} end

    function target.find_command(id)
        for _, cmd in ipairs(target.get_commands()) do
            if cmd.id == id then
                return cmd
            end
        end
        return nil
    end

    function target.run_command(id, ...)
        local handler = target["command_" .. id]
        if not handler then
            print("no handler for command '" .. id .. "' in " .. target.get_title())
            return
        end
        return handler(...)
    end

    function target.set_selected(flag)
        if selected ~= flag then
            selected = flag
            highlight(flag)
        end
    end
    function target.is_selected() return selected end

    -- right click with this object selected; pos is the block position
    -- above the clicked surface, target_uid - clicked entity (if any)
    function target.on_order(pos, target_uid) end
end

return object
