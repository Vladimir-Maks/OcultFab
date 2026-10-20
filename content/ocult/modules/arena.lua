-- Playable area bounds. Keep in sync with generators/flat_stone.files/script.lua
local this = {}

this.SIZE = 100
this.FLOOR_TOP = 8

function this.center()
    return this.SIZE / 2, this.FLOOR_TOP + 1, this.SIZE / 2
end

function this.clamp(x, z)
    return math.max(0, math.min(this.SIZE, x)), math.max(0, math.min(this.SIZE, z))
end

return this
