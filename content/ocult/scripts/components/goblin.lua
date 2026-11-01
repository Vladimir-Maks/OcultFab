-- Goblin: a fast, weak enemy (rts/enemy; stats: config/combat.json,
-- enemies.goblin). Model: .assets/goblin/goblin.bbmodel
-- (tools/bbmodel2rig.py), no animations yet.
local enemy = require "ocult:rts/enemy"

enemy.extend(this, "goblin", {
    title = "Гоблин",
})
