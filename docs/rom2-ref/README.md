# ROM2 Reference — справочники оригинальной игры

Оригинальные текстовые ресурсы, выгруженные из Rage of Mages II (Allods 2) —
**источник формул, баланса и механик** для переноса в Allods Home (Godot).

## Где брать формулы характеристик

| Файл | Содержимое |
|---|---|
| `main.txt` | Описания характеристик персонажа: **Mind → сила магии и обучение**, **Spirit → количество маны (только для магов)** и магическая защита воинов, Body → здоровье/урон, Agility → скорость/защита. Также тексты игровых окон (Mana cost, Damage, Spellbook...) и сферы магии (Fire/Water/Air/Earth/Astral с их заклинаниями). |
| `stats.txt` | Настройки/строки панели характеристик |
| `spells.txt`, `spell.txt` | Описания и названия всех заклинаний |
| `itemserv.txt` / `itemname.txt` | Сервисные имена и русские/английские названия предметов |
| `Description Checks.ini` | Команды-**условия** скриптов миссий (дистанции, параметры юнитов, "Spell on Unit/Tile") |
| `Description Instants.ini` | Команды-**эффекты** скриптов миссий ("Make spell effect" с параметрами Spell и Power/skill) |
| `building.txt`, `town.txt`, `npcnames.txt`, `unitname.txt` | Здания/города/имена для контента |
| `mission*.txt` | Сценарии и диалоги кампаний |

## Как формулы применяются в коде проекта

- `scripts/player.gd`
  - `_calc_max_hp()` = `20 + body*8` (Body → здоровье)
  - `_calc_max_mana()` = `10 + spirit*4`, **0 для воина** (Spirit → мана, только маг)
  - `magic_damage(base, sphere)` = `base + mind/2 + skill*2/5` (Mind + навык сферы → урон магии)
  - `sphere_skill(sphere)` — навыки fire/water/air/earth/astral_skill
  - `get_magic_power()` = `mind/2` — множитель силы заклинаний
- `scripts/spell_db.gd` — база заклинаний (урон, мана, сфера) из `assets/spells/spells_db.json`
- `scripts/character_select.gd` — стартовые характеристики 4 персонажей (воины без маны, маги с маной)

## Также полезно

- `assets/projectiles/projectiles.reg` — реестр снарядов (анимации магии, папки кадров)
- `assets/spells/spells_db.json` — числовые параметры магии
- `assets/structures/structures.txt`, `assets/units/units.txt`, `assets/map-objects/objects.txt` — реестры оригинальной игры