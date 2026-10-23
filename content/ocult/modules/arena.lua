-- Playable area. The world generator reads it too.
--
-- SIZE x SIZE stone arena in the void. The PLATFORM x PLATFORM square in the
-- middle is open floor; everything around it is one block higher: a layer of
-- stone and ores the player digs into. That layer is at LEVEL, the same
-- height units walk at on the open floor.
local this = {}

this.SIZE = 1000
this.PLATFORM = 20
this.FLOOR_TOP = 8               -- top block of the solid floor
this.LEVEL = this.FLOOR_TOP + 1  -- walking level / the minable raised layer

function this.center()
    return this.SIZE / 2, this.LEVEL, this.SIZE / 2
end

function this.clamp(x, z)
    return math.clamp(x, 0, this.SIZE), math.clamp(z, 0, this.SIZE)
end

function this.inside(x, z)
    return x >= 0 and x < this.SIZE and z >= 0 and z < this.SIZE
end

function this.in_platform(x, z)
    local p0 = (this.SIZE - this.PLATFORM) / 2
    return x >= p0 and x < p0 + this.PLATFORM and z >= p0 and z < p0 + this.PLATFORM
end

return this
