-- Shows building pipe ports while the player is laying pipes: a coloured
-- floor marker on the cell where the pipe goes, with a letter lying on it:
--   И - input, Э - output, Л - both (buildings without `ports`)
local arena = require "ocult:arena"
local building = require "ocult:rts/building"
local markers = require "ocult:rts/markers"

local this = {}

-- letter size: world units per font pixel (default font line is ~16 px)
local LETTER_SCALE = 0.045
local LETTER_LIFT = 0.02 -- above the floor, so it isn't hidden by the marker
local SCAN_RADIUS = 48 -- buildings are looked up this far from the camera focus

local STYLES = {
    ["in"] = {letter = "И", marker = "blocks:green"},
    out = {letter = "Э", marker = "blocks:red"},
    [building.ANY] = {letter = "Л", marker = "blocks:blue"},
}

local shown = false
local texts = {}
local marks = {}

local function flat(v)
    local len = math.sqrt(v[1] * v[1] + v[3] * v[3])
    if len < 1e-6 then
        return {0, 0, -1}
    end
    return {v[1] / len, 0, v[3] / len}
end

-- x/y axes of a letter lying on the floor, readable from the camera:
-- its "up" points away from the camera
local function letter_axes(cam)
    return flat(cam:get_right()), flat(cam:get_front())
end

local function show_port(axis_x, axis_y, x, y, z, dx, dz, mode)
    local style = STYLES[mode] or STYLES[building.ANY]
    local cx, cz = x + dx, z + dz -- the cell where the pipe goes
    local ids = markers.rect(cx, y - 1, cz, 1, 1, style.marker)
    for _, id in ipairs(ids) do
        table.insert(marks, id)
    end
    -- the engine centres text horizontally; shift it back by half a line
    local half = 8 * LETTER_SCALE
    local id = gfx.text3d.show(
        {cx + 0.5 - axis_y[1] * half, y + LETTER_LIFT, cz + 0.5 - axis_y[3] * half},
        style.letter,
        {
            display = "static_billboard",
            color = {1, 1, 1, 1},
            scale = LETTER_SCALE,
            render_distance = 256,
        }
    )
    gfx.text3d.set_axis_x(id, axis_x)
    gfx.text3d.set_axis_y(id, axis_y)
    table.insert(texts, id)
end

-- cam: the RTS camera, focus: {x, y, z} it looks at
function this.show(cam, focus)
    this.hide()
    shown = true
    local axis_x, axis_y = letter_axes(cam)
    local y = arena.LEVEL
    local cx, cz = math.floor(focus[1]), math.floor(focus[3])
    local x0, z0 = math.max(0, cx - SCAN_RADIUS), math.max(0, cz - SCAN_RADIUS)
    local x1 = math.min(arena.SIZE - 1, cx + SCAN_RADIUS)
    local z1 = math.min(arena.SIZE - 1, cz + SCAN_RADIUS)
    for _, b in ipairs(building.find_all(x0, z0, x1, z1, y)) do
        for _, p in ipairs(building.ports(b.id, b.x, b.y, b.z)) do
            show_port(axis_x, axis_y, unpack(p))
        end
    end
end

function this.hide()
    for _, id in ipairs(texts) do
        gfx.text3d.hide(id)
    end
    markers.clear(marks)
    texts, marks = {}, {}
    shown = false
end

function this.set_visible(flag, cam, focus)
    if flag and not shown then
        this.show(cam, focus)
    elseif not flag and shown then
        this.hide()
    end
end

return this
