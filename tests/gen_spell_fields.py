"""Дополняет assets/spells/spells_db.json полями каста и эффектов.

Раньше в базе были только damage/mana_cost/range/area/projectile/kind/sound.
Из-за этого: кулдаун был один на все заклинания (0.8 с в коде), время каста,
скорость снаряда и крит не существовали, а 12 «баффов» сводились в коде к
одному и тому же щиту (player._apply_buff_target).

Здесь каждому заклинанию проставляется:
  cooldown, cast_time, projectile_speed, target, power_coef,
  crit_chance, crit_mult, min_damage, effects[]
и чинятся kind у Wall_of_Fire (был attack вместо wall) и Animate_Dead.

Запуск: python tests/gen_spell_fields.py
"""
import json
import os

DB = os.path.join(os.path.dirname(__file__), "..", "assets", "spells", "spells_db.json")

# Типы эффектов: shield/resist/bless/haste/slow/invisibility/curse/vision/
#                vampirism/dot/raise
TABLE = {
    "Fire_Arrow":            dict(cd=0.8, cast=0.35, speed=420, target="enemy"),
    "Fire_Ball":             dict(cd=2.0, cast=0.55, speed=300, target="point", coef=1.0),
    "Wall_of_Fire":          dict(cd=8.0, cast=0.70, speed=0,   target="point", kind="wall",
                                   wall="damage", wwidth=72.0, wlife=6.0,
                                   wdamage=3),
    "Protection_from_Fire":  dict(cd=6.0, cast=0.30, speed=0,   target="ally", coef=1.2,
                                   eff=[("resist", {"sphere": "Fire", "amount": 20, "duration": 90})]),
    "Ice_Missile":           dict(cd=1.0, cast=0.40, speed=380, target="enemy"),
    "Poison_Cloud":          dict(cd=4.0, cast=0.60, speed=240, target="point",
                                   eff=[("dot", {"sphere": "Water", "dps": 4, "duration": 6})]),
    "Blizzard":              dict(cd=6.0, cast=0.70, speed=240, target="point",
                                   eff=[("dot", {"sphere": "Water", "dps": 3, "duration": 5}),
                                        ("slow", {"mult": 0.7, "duration": 3})]),
    "Acid_Stream":           dict(cd=2.0, cast=0.50, speed=340, target="enemy",
                                   eff=[("dot", {"sphere": "Earth", "dps": 3, "duration": 4})]),
    "Protection_from_Water": dict(cd=6.0, cast=0.30, speed=0,   target="ally", coef=1.2,
                                   eff=[("resist", {"sphere": "Water", "amount": 20, "duration": 90})]),
    "Lightning":             dict(cd=2.0, cast=0.45, speed=600, target="enemy", crit=0.10),
    "Prismatic_Spray":       dict(cd=3.0, cast=0.60, speed=0,   target="point"),
    "Invisibility":          dict(cd=12.0, cast=0.30, speed=0,  target="ally",
                                   eff=[("invisibility", {"duration": 20, "break_range": 40})]),
    "Darkness":              dict(cd=10.0, cast=0.50, speed=0,  target="point", kind="debuff",
                                   eff=[("vision", {"mult": 0.5, "duration": 20})]),
    "Protection_from_Air":   dict(cd=6.0, cast=0.30, speed=0,   target="ally", coef=1.2,
                                   eff=[("resist", {"sphere": "Air", "amount": 20, "duration": 90})]),
    "Diamond_Dust":          dict(cd=3.0, cast=0.60, speed=0,   target="point"),
    "Wall_of_Earth":         dict(cd=8.0, cast=0.70, speed=0,   target="point", kind="wall",
                                   wall="block", wwidth=64.0, wlife=8.0),
    "Protection_from_Earth":  dict(cd=6.0, cast=0.30, speed=0,   target="ally", coef=1.2,
                                   eff=[("resist", {"sphere": "Earth", "amount": 20, "duration": 90})]),
    "Stone_Curse":           dict(cd=6.0, cast=0.50, speed=0,   target="enemy", kind="debuff",
                                   eff=[("root", {"duration": 15}),
                                        ("curse", {"defense": -0.6, "duration": 30})]),
    "Stone_Missile":         dict(cd=1.2, cast=0.40, speed=400, target="enemy"),
    "Heal":                  dict(cd=1.5, cast=0.45, speed=0,   target="ally", coef=1.3),
    "Drain_Life":            dict(cd=2.0, cast=0.40, speed=360, target="enemy",
                                   eff=[("vampirism", {"ratio": 0.5})]),
    "Bless":                 dict(cd=5.0, cast=0.40, speed=0,   target="ally", coef=1.1,
                                   eff=[("bless", {"attack": 2, "defense": 2, "duration": 60})]),
    "Haste":                 dict(cd=10.0, cast=0.30, speed=0,  target="ally",
                                   eff=[("haste", {"mult": 1.4, "duration": 20})]),
    "Control_Spirit":        dict(cd=8.0, cast=0.60, speed=0,   target="point", kind="debuff",
                                   eff=[("slow", {"mult": 0.7, "duration": 15}),
                                        ("curse", {"defense": -0.3, "duration": 15})]),
    "Curse":                 dict(cd=4.0, cast=0.40, speed=0,   target="enemy", kind="debuff",
                                   eff=[("curse", {"defense": -0.4, "duration": 30})]),
    "Slow":                  dict(cd=4.0, cast=0.35, speed=0,   target="enemy", kind="debuff",
                                   eff=[("slow", {"mult": 0.55, "duration": 12})]),
    "Animate_Dead":          dict(cd=15.0, cast=0.80, speed=0,  target="enemy", kind="raise",
                                   eff=[("raise", {"lifespan": 30})]),
    "Shield":                dict(cd=10.0, cast=0.35, speed=0,  target="ally", coef=1.2,
                                   eff=[("shield", {"amount": 18, "duration": 60})]),
    "Summon":                dict(cd=20.0, cast=0.60, speed=0,  target="self"),
    "Teleport":              dict(cd=8.0, cast=0.25, speed=0,   target="self"),
    "Light":                 dict(cd=12.0, cast=0.30, speed=0,  target="self"),
}

# Нежить/демоны/звери — дебаффы должны быть заметно сильнее по времени
NON_ATTACKING_KINDS = {"heal", "buff", "self", "wall", "debuff", "raise"}


def main():
    with open(DB, "r", encoding="utf-8") as f:
        db = json.load(f)

    missing = [k for k in db if k not in TABLE]
    if missing:
        raise SystemExit("нет данных в TABLE для: %s" % missing)

    for name, o in db.items():
        t = TABLE[name]
        kind = t.get("kind", o.get("kind", "attack"))
        attacking = kind not in NON_ATTACKING_KINDS

        o["kind"] = kind
        o["cooldown"] = t["cd"]
        o["cast_time"] = t["cast"]
        o["projectile_speed"] = t.get("speed", 0)
        o["target"] = t["target"]
        o["power_coef"] = t.get("coef", 1.0)
        o["crit_chance"] = t.get("crit", 0.05 if attacking else 0.0)
        o["crit_mult"] = 1.5
        o["min_damage"] = 1
        o["effects"] = [
            dict(type=t_, **params) for t_, params in t.get("eff", [])
        ]
        # Стены в оригинале разные: огонь жжёт непрерывно, земля —
        # непроходимая преграда (spells.txt: «Wall of Fire — Inflicts Fire
        # damage continuously», «Wall of Earth — unpassable wall»).
        if kind == "wall":
            o["wall_mode"] = t.get("wall", "damage")
            o["wall_width"] = t.get("wwidth", 64.0)
            o["wall_life"] = t.get("wlife", 6.0)
            o["damage"] = t.get("wdamage", o.get("damage", 0))
        else:
            o["wall_mode"] = ""
            o["wall_width"] = 0.0
            o["wall_life"] = 0.0

    with open(DB, "w", encoding="utf-8") as f:
        json.dump(db, f, ensure_ascii=False, indent=2)
        f.write("\n")

    with_eff = sum(1 for o in db.values() if o["effects"])
    print("spell fields: spells=%d with_effects=%d" % (len(db), with_eff))


if __name__ == "__main__":
    main()
