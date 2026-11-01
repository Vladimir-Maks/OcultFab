-- Troll: a slow, tough enemy (rts/enemy; stats: config/combat.json,
-- enemies.troll). Model and animations: .assets/troll/troll.bbmodel
-- (tools/bbmodel2rig.py, the model looks along +X); the damage lands when
-- the swing is over.
local enemy = require "ocult:rts/enemy"

enemy.extend(this, "troll", {
    title = "Тролль",
    model_yaw = 90,
    anim_walk = "ocult_troll_walk",
    walk_rate = 1.2,
    anim_attack = "ocult_troll_attack",
    attack_length = 1.5,
})
