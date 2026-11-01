-- Skeleton: a strong enemy that joins the waves from night 3 on
-- (rts/enemy; stats: config/combat.json, enemies.skeleton). Model and
-- animations: .assets/skeleton/skeleton.bbmodel (tools/bbmodel2rig.py);
-- the blow lands when the swing is over.
local enemy = require "ocult:rts/enemy"

enemy.extend(this, "skeleton", {
    title = "Скелет",
    anim_walk = "ocult_skeleton_walk",
    anim_attack = "ocult_skeleton_attack",
    attack_length = 2.0,
})
