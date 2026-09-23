# AGENTS.md — заметки агента по проекту Allodshome_Godot
# AGENTS.md — Godot Project Agent Contract

This file defines how AI coding agents must work in this repository.
Agents must read and follow this file before making any changes.

## 1. Project Overview

- **Project name:** <Allodshome>
- **Engine:** Godot <4.7>
- **Language:** GDScript / C# <GDScript>
- **Target platforms:** <Windows>
- **Main scene:** `res://scenes/main.tscn`
- **Repository root:** `res://`

## 2. Repository Structure

```text
- `addons`          # Third-party and local editor plugins (do not modify without approval)
- `assets`          # Art, audio, fonts, and other raw assets
- `resources`       # .tres resource files
- `scenes`          # .tscn scene files
- `scripts`         # GDScript/C# source files
- `tests`           # Automated tests (GUT / GdUnit4)
- `ui`              # UI scenes and scripts
- `scripts/game.gd` — автозагрузка, единые статы/математика боя (`deal_damage`, `is_miss`, `unit_*`, `tick_shields`, `deal_damage_area`), а также `unit_absorption`, `unit_protection` и т.д.
- `scripts/enemy.gd` (~304 строк) — класс врагов: `take_damage`, `deal_damage` подключение, `flee/chase/attack`, лут, статы `get_*`.
- `scripts/player.gd` — герой (ближний бой через deal_damage, магия, статы `get_attack/get_defense/etc`).
- `scripts/mercenary.gd` — наёмник (атака через deal_damage, `take_damage`).
- `scripts/projectile.gd` — снаряды (магия/область).
- `scripts/unit.gd` / `unit_db.gd` — база юнитов (статы монстров/героев).
- `scripts/spell_db.gd` — заклинания (сферы/магия).
- `scripts/ui.gd`, `scripts/character_select.gd` — UI (панель сфер мага вместо навыков оружия).
```

## 3. Agent Scope Rules

- **One task per prompt.** Do not bundle unrelated changes.
- **Smallest safe change.** Modify only what is required to complete the task.
- **No unsolicited refactoring.** Do not rename, reformat, or restructure code unless explicitly asked.
- **No new dependencies.** Do not add addons, plugins, or external libraries without approval.
- **Stay inside the allowed scope.** If the task says “edit `player.gd`”, do not touch other files unless strictly necessary. If necessary, ask first.
- **Ask when ambiguous.** If requirements are unclear, stop and ask for clarification instead of guessing.

## 4. Anti-Hallucination Rules

- Do not invent Godot APIs, classes, methods, signals, or properties.
- If an API is not present in the current Godot version or in the codebase, do not use it.
- Do not invent file paths, scene names, node names, or autoloads.
- Before using a node, signal, or resource, verify it exists in the project or in the official Godot documentation.
- If you are unsure, search the codebase or ask. Do not guess.

## 5. Godot Coding Conventions

- **Indentation:** tabs (Godot standard).
- **Naming:**
  - Classes / nodes: `PascalCase`
  - Files and folders: `snake_case`
  - Functions and variables: `snake_case`
  - Constants: `CONSTANT_CASE`
  - Signals: past tense, e.g. `health_changed`, `door_opened`
- **Typing:** Use typed GDScript where possible:
  ```gdscript
  var health: int = 100
  func take_damage(amount: int) -> void:
  ```
- **Node access:** Prefer `@onready` and unique names (`%NodeName`) over hardcoded `get_node()` paths.
- **Signals:** Prefer signals over direct parent/child references.
- **Composition over inheritance:** Use child nodes and resources instead of deep inheritance trees.
- **Data:** Use `Resource` files for configurable data, not hardcoded dictionaries.
- **Exports:** Use `@export` for inspector-facing variables.
- **Process functions:**
  - Use `_physics_process` for physics and movement.
  - Use `_process` only when frame-dependent logic is required.
  - Prefer timers or signals over polling.
- **Autoloads:** Do not add or remove autoloads without explicit approval. Current autoloads: `<list them>`.
- **Scenes:** Keep scene trees shallow. One root node per scene. Use instancing.
- **Resources:** Do not delete or rename `.tres` or `.tscn` files without approval.

## 6. Testing and Verification
## Как запустить Godot (важно!)

Проект (на этой машине): `C:\Work\Allodshome`
Консольный движок:
- `C:\Games\Godot_v4.7.2-stable_win64_console.exe`
- (обычный GUI-вариант рядом: `..._win64.exe`)
- На домашнем ПК пути были `D:\Work\UnityProjects\...` — пути в заметках могли сохраниться оттуда.

Быстрый тест «парсится ли всё» (headless, выход сразу):
```
& 'C:\Games\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Work\Allodshome' --quit 2>&1 | Select-String 'SCRIPT ERROR|Parse Error|ERROR:'
```
Отсутствие `SCRIPT ERROR` = скрипты компилируются. Эту команду используем как «контрольную точку» после любых правок. `ERROR: 1 resources still in use at exit` — безобидный «хвост», не ошибка скриптов.

Парсинг GODOT по скриптам можно отличить от «картинок-мусора»: выводимая Unicode-каша из PNG/CJK-файлов в `assets/` — норма, читаем только `.gd`-файлы. НЕ запускай `Get-ChildItem` на весь `assets` с фильтром по CJK — там сотни картинок.

- Agents must run tests after code changes.
- Agents must not claim tests passed if they were not run.
- If no tests exist for the changed area, state that explicitly.
- Code must parse without errors. Check with:


## 7. Version Control Rules

- **Never commit directly to `main`.**
- **Branch naming:** `feature/agent-<short-task-name>`
- **Commit messages:** `<type>(<scope>): <description>`
  - Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`
- Do not rewrite git history, force-push, or delete branches without approval.

## 8. Approval Gates

The agent must stop and ask for explicit approval before:

- Modifying `project.godot`
- Adding/removing autoloads
- Changing the input map
- Adding/removing addons or plugins
- Deleting or renaming scenes, resources, or scripts
- Changing export presets
- Refactoring architecture or folder structure
- Running destructive commands (e.g., `rm -rf`, `git reset --hard`)

## 9. Workflow

1. Read `AGENTS.md` and the relevant files.
2. Propose a short plan:
   - What will change
   - Which files will be touched
   - How it will be tested
3. Wait for approval if the task is non-trivial or touches approval gates.
4. Implement the smallest possible change.
5. Run tests and static checks.
6. Report:
   - Summary of changes
   - Files modified
   - Test results
   - Any blockers or uncertainties

## 10. Definition of Done

A task is done only when:

- Code parses without errors.
- Relevant tests pass (or absence of tests is explicitly stated).
- No new warnings are introduced.
- Changes are limited to the requested scope.
- The agent provides a clear summary and test evidence.

## 11. Example Agent Prompts

Good:
- “Add a `take_damage(amount: int)` method to `player.gd`. Do not modify other files. Run tests.”
- “Fix the jump bug in `player.gd`. Show me the plan before editing.”

Bad:
- “Improve the game.”
- “Refactor everything and make it better.”
- “Add multiplayer.”

## 12. Notes for Humans

- Keep this file updated as the project evolves.
- If an agent repeatedly violates a rule, make the rule more explicit and add a check.
- Prefer small, reviewable changes over large autonomous rewrites.


> Памятка для продолжения работы из любой сессии. Обновляй при каждом заметном шаге.
> Обновлено: **Сессия 23.09 (вечер)** — дороги = связный коридор шириной 2 (A* по суше), берег извилистый (compactness 1.8).
> Обновлено: **Сессия 22.09** — доделан transition_editor: tile5/6/7 (PNG+BMP), import из pvm/ с диагоналями, transition_db 336/336.
>
> Запуск головного headless-раннера мира: `godot --headless --path ... --script res://scripts/world/sim_runner.gd` (см. Слой-2 заметку ниже).

## 13. Available Skills

| Skill | Scope |
|-------|-------|
| [`godot-gdscript`](skills/godot/godot-gdscript/SKILL.md) | GDScript language: typing, lifecycle, `@export`, signals, idioms |
| [`godot-nodes-scenes`](skills/godot/godot-nodes-scenes/SKILL.md) | Scene tree, node composition, instancing, autoloads, `PackedScene` |
| [`godot-signals-groups`](skills/godot/godot-signals-groups/SKILL.md) | Event-driven design with signals + groups |
| [`godot-2d-movement`](skills/godot/godot-2d-movement/SKILL.md) | `CharacterBody2D` kinematic movement, `move_and_slide`, slopes |
| [`godot-tilemap`](skills/godot/godot-tilemap/SKILL.md) | `TileMapLayer`/`TileSet`: autotiling, terrain, collision/nav layers |
| [`godot-physics`](skills/godot/godot-physics/SKILL.md) | Rigid/Area/Static bodies (2D+3D), collision layers, raycasts |
| [`godot-ui-control`](skills/godot/godot-ui-control/SKILL.md) | `Control` nodes: anchors, containers, themes, focus nav |
| [`godot-animation`](skills/godot/godot-animation/SKILL.md) | `AnimationPlayer`, `AnimationTree`, `Tween` |
| [`godot-shaders`](skills/godot/godot-shaders/SKILL.md) | Godot shading language: 2D `canvas_item` + 3D `spatial` shaders |
| [`godot-3d-essentials`](skills/godot/godot-3d-essentials/SKILL.md) | 3D nodes, cameras, lighting, environment/post, `GridMap` |
| [`godot-resources`](skills/godot/godot-resources/SKILL.md) | Custom `Resource` classes, `.tres`, data-driven design |
| [`godot-audio`](skills/godot/godot-audio/SKILL.md) | `AudioStreamPlayer`, buses, effects, sync-to-beat |
| [`godot-multiplayer`](skills/godot/godot-multiplayer/SKILL.md) | High-level multiplayer: `MultiplayerAPI`, RPCs, spawner/sync |
| [`godot-export`](skills/godot/godot-export/SKILL.md) | Export presets/templates, platform builds, headless CLI export |
| [`godot-csharp`](skills/godot/godot-csharp/SKILL.md) | C#/.NET in Godot: bindings, signals as events, GDScript interop |

## 14. Что сделано сегодня (главное)

### 0. Слои мира (Слой-2) — headless-канон, симулятор жив
- `world_state.gd` — убраны дублирующие объявления (day/global_threat/relations/hero/journal), остался типизированный `journal: Array[Dictionary]`; `_id()` переписан с `match`-присваиваний (`return "u-%d" % (_u += 1)` — Parse Error) на `if/elif` с телом.
- `world_bus.gd:reseed()` — 9 переменных `:=` → `: Dictionary` (f_h, f_e, r, c_h, c_e, u1, u2, a_h, a_e); инференция типов в невыводимых местах запрещена в autoload.
- `world_sim.gd:86/167` — `var d := a.get("pos")...distance_to()` → `var d: float`; `var m := state._u` → выпилен неиспользуемый (в `_log`).
- Контроль: `--headless --quit` = `0 SCRIPT ERROR`; симулятор 100 дней: `RESULT: world survived 100 days. day=100, threat=1.00, journal=208`.

### 1. Унифицирован весь урон через единую точку `Game`
Игра перешла на единую точку боевой математики — весь урон (герой ближнего боя, мгновенная магия героя, атака врагов, наёмники, магия по площади) идёт через **`Game.deal_damage(...)`**, а не напрямую через `enemy.take_damage`.

Все хелперы боя живут в `scripts/game.gd` (дубль математики выпилен, теперь строго по одному экземпляру каждого):
- `Game.hit_chance(attack, defense) -> int` — процент попадания (универсальная, тот самый `hit_chance` из плана):
  - `clampi(50 + attack - defense, 5, 95)` — либо 50 базовов + разность атаки и защиты.
- `Game.is_miss(attacker, attacker_unit, defender) -> bool` — промах с шансом `hit_chance(attack, defense)`.
  - Сигнатура приведена к `Game.is_miss(attacker, defender)` (сейчас в коде `is_miss(attacker, defender)`).
- `Game.unit_attack(unit) -> int`, `Game.unit_defense(unit) -> int`, `Game.unit_absorption(unit) -> int` — генерализованные до уровня `unit_*` (работают и для героя, и для врагов/наёмников через их `get_*`).
- `Game.unit_protection(unit, element) -> int` — защита от материала (стихии: fire/water/air/earth/astral).
- `Game.tick_shields(unit, delta)` — тикает щиты (снимает срок жизни).
- `Game.deal_damage(target, dmg, kind, sphere, attacker)` — ЕДИНАЯ точка нанесения урона:
  - `kind == "physical"` → применяется `unit_absorption` (броня/поглощение) + шанс промаха (из `is_miss`), затем `target.take_damage(...)`.
  - `kind == "magic"` → защита от стихии `unit_protection(target, sphere)`, затем `target.take_damage(...)`.
  - attacker — кто наносит (герой, наёмник, враг, снаряд).
- `Game.deal_damage_area(targets, dmg, kind, sphere, attacker)` — урон по площади (магия области/снаряды AoE).
- `Game.deal_damage` сам вызывает `target.take_damage(final_dmg, attacker)` — НЕ дублирует никакие щиты (щиты юнита живут ВНУТРИ `take_damage` героя/врага/наёмника и снимаются внутри `Game.tick_shields`).

Точки подключения (заменено напрямую на `Game.deal_damage`):
- `player.gd:594` — рукопашная героя (атака по врагу): `Game.is_miss` + `Game.deal_damage(target, damage, "physical", "", self)`.
- `player.gd:761` — магия героя (мгновенная/по прямой): `Game.deal_damage(target, final_dmg, "magic", sphere, self)`.
- `enemy.gd:125` — удар врага по герою (промах + урон): `Game.is_miss` + `Game.deal_damage(player, damage, "physical", "", self)`.
- `mercenary.gd:116` — атака наёмника: `Game.is_miss` + `Game.deal_damage(attack_target, damage, "physical", "", self)`.
- `game.gd:138` — **починена серьёзная поломка**: при удалении дубля математики был выпилен заголовок функции, а внутрь тела вклеилась CJK-порча `什么人` (китайские иероглифы в `return`), из-за чего:
  - враг `take_damage` потерял заголовок `func take_damage(dmg, attacker)` и его тело осталось «сиротой», а строки `dmg <= 0` / `current_hp -= dmg` попали внутрь `get_sight`.
  - файл `enemy.gd` перестал компилироваться и Godot валил «Could not resolve class Enemy» + «Cannot infer the type of e».
  - Восстановлены: строка про `func take_damage(dmg: int, attacker)` вернулась на своё место, убрана CJK-порча, все сцены/скрипты снова парсятся (проверено headless: `0 SCRIPT ERROR`).

Детали боевой формулы:
- Производные характеристики юнитов (`get_attack/get_defense/get_absorption/get_protection_*`) теперь в `enemy.gd`, `mercenary.gd` и расчитываются как у героя.
- `Game.deal_damage` применяет:
  - физика → `unit_absorption` (броня/поглощение) → потом `take_damage`
  - магия → `unit_protection` по стихии (sphere) → потом `take_damage`
  - снаряды/область → `deal_damage`/`deal_damage_area`

Цель: единая точка урона — достигнута. Вредная магия, поглощение, защита стихий, щиты, промахи — всё через `Game`.

- Снаряды `projectile.gd` и `deal_damage_area` пока напрямую вызывали `enemy.take_damage(...)` — НО это уже через `Game.deal_damage`/`deal_damage_area` (потому что их вызывает `player.gd` через магию; см ниже). Убедись, что `projectile.gd` при попадании зовёт `Game.deal_damage(target, dmg, "magic", sphere, owner)` — если ещё нет, поправить (см. план П0).

### 2. Ближний бой, магия, снаряды, наёмники — через deal_damage
- `player.gd` (ближняя атака ~594, мгновенная магия ~761) — `Game.deal_damage(target, dmg, ...)`.
- `enemy.gd` (~125) — `Game.deal_damage(player, damage, "physical", "", self)` + промах.
- `mercenary.gd` (~116) — `Game.deal_damage(attack_target, damage, "physical", "", self)` + промах.
- `projectile.gd` (~92/101) — снаряд при попадании бьёт через `Game.deal_damage_area` / `Game.deal_damage` (урон мечуемой магии области). Проверить, что `sphere` передаётся (сфера → защита стихии).

### 3. Наёмник, AoE, заклинания (завершено в этой сессии)
- `mercenary.gd:_attack()` — переведён на `Game.is_miss(self, target)` + `Game.deal_damage(target, damage, "physical", "", self)`; добавлены `get_attack/get_defense/get_absorption/get_protection_*`.
- `mercenary.gd:take_damage()` — входящий урон через `Game.shield_reduce(self, dmg)` (как герой/npc).
- `player.gd:_damage_area_at()` — ушёл на `Game.deal_damage_area(targets, dmg, "magic", sphere, self)` (а не `enemy.take_damage` напрямую); неактуален (больше не вызывается) — мгновенный AoE убран, урон наносит только `projectile.gd` при прилёте (снят двойной урон для `range<=0`).
- `mercenary.gd` — добавлен `lifespan` (призванные миньоны исчезают по таймеру и покидают `Game.party`).
- `player.gd` — реализованы **Light** (`_cast_light()`: визуальная вспышка вокруг героя на 4 с) и **Summon** (`_cast_summon()`: союзный миньон `monsters/orc`/60hp/8dmg на 45 с в `Game.party`).
- `game.gd:22` — `debug_magic = false` (маг больше не стартует со всеми 24 заклинаниями).

## 15. План / что осталось (в порядке приоритета)

### П0-П2 — завершено (единая точка урона, снаряды/область, маг-тактика)
- [x] `deal_damage` единый в `Game`
- [x] герой (ближний + мгновенная магия), враг, наёмник — через deal_damage
- [x] снаряды `projectile.gd` — переведены на `Game.deal_damage(enemy, dmg, "magic", sphere, owner)` (одиночный) и `Game.deal_damage_area(targets, ...)` (AoE); `sphere` берётся из `SpellDB.sphere_of(spell_name)` — защита стихий работает у снарядов.
- [x] дубль математики выпилен, `_ready` восстановлен, enemy.gd починен (CJK-порча вычищена)

### П1 Магия героя — снаряды/область через deal_damage
- [x] `projectile.gd` при попадании: `Game.deal_damage(target, dmg, "magic", sphere, owner)` / `deal_damage_area` вместо прямых `take_damage`.
- [x] `player.gd` мгновенная магия/область → через deal_damage (сверено: `_cast_spell_effect` → `_fire_spell_projectile` → `deal_damage`; биндинг через `deal_damage_area` для AoE).

### П2 Маг (посох + сферы) — класс мага как отдельная тактика
- [x] Посох мага бьёт как мгновенная магия (как «сфера»): `player.gd:594-612` — для `weapon=="staff"` → магия сферы (`_active_sphere()`), урон по стихии + опыт сфере, а не физически.
- [x] Панель сфер мага вместо навыков оружия в UI: `ui.gd:895-905` — для `Game.hero_class=="mage"` показываем сферы/защиты стихий, для остальных — навыки оружия.
- [x] Стартовый набор мага: посох + книга (а не меч + щит): `player.gd:236-243`, `character_select.gd`.
- [x] Мана/опыт сферы за каст: `player.gd:_apply_spell_experience` + `_apply_spell_experience(sphere)` при касте/попадании посохом.

### Статистика / производные (принятое решение)
- `hit_chance = clampi(50 + attack - defense, 5, 95)` (как в оригинале).
- `absorption` — броня/поглощение (физика), `protection_*` — защита стихий (магия).
- Шанс промаха `is_miss(attacker, attacker_defender)` через `hit_chance`. Промах = «тихий промах» без урона, для магии урона нет при промахе.
- Всё применение урона через `take_damage` (внутри — щит юнита: `shield_reduce`, затем HP).


## 16. Процедурная генерация карт (сессия 21.09 — активно)

### Концепция игры (решения пользователя)
- **Не копия Аллодов II**, а духовный наследник. Песочница + тактический RPG.
- **Корень**: mmap-мир с тактическими боями, процедурная генерация карт, прогрессия через репутацию фракций.
- **Зона = процедурная карта-биом** (одна карта = один биом, переход между зонами = портал на новой карте).
- НЕ участки одной большой карты.

### Фракции (5, на основе юнитов из units_db.json)
1. **Альянс Света** — humans/ (militia, swordsman, archer, mage)
2. **Орды Огня** — orc/goblin/troll/ogre (orc, orc_s, orc_sh, goblin, goblin_s, ogre, troll)
3. **Пожинатели** — undead (skeleton, zombie, necromant, ghost)
4. **Круг Друидов** — druid, nature spirits
5. **Серые** (враги) — monsters/ (bat, bee, wolf, spider, dino, turtle, squirrel, legg) — ВСЕГДА враги

### Отношения и репутация
- Герой по умолчанию воюет **только с Серыми**.
- С фракциями нейтралитет; можно улучшать/ухудшать до войны.
- Минимальные пресеты отношений, дальше фракции сами: война/мир/нейтралитет.
- Репутация → качество наёмников в тавернах + тир магазинов.

### Прогрессия зон
- **Z1** (стартовая): слабые Серые, обучение
- **Z2**: средние Серые, возможны войны фракций, аванпосты фракций
- **Z3**: тяжёлые Серые, разборки армий
- **Z4a-d**: ответвления — базовые территории фракций

### Боевая механика
- Отряд: герой + 2-3 наёмника.
- Наёмникам НЕЛЬЗЯ менять одежду/прокачивать навыки.
- Магия — да, если маг. Наёмники нанимаются в тавернах фракций.
- Активная пауза = полная пауза + выдача приказов.

### Миникарта и мир
- На карте героя = **реальный бой** с туманом войны, восклицательные знаки на миникарте.
- На остальных территориях = **SIM-эмуляция** (экономия ресурсов).
- Миникарта: точки/зоны с transparency 20-30 для нейтралов.
- Лог боя = только на текущей карте (SIM-бои не засоряют лог).

### Переход между зонами
- Объект-портал у конца карты; вся команда перемещается в стартовую зону следующей.

### Размеры карт
- Пока маленькие (48x48), вырастим после отработки генерации.

### Угроза
- Антагонист НЕ копия Урда (Alods II).
- Песочница без «конца мира» — вместо этого нарастающее давление/состояния мира.
- Варианты: Растворение (рекомендация), Цикл, Шёпот — финального решения нет.

### Юниты для фракций (из units_db.json, 89 наборов)
- humans 18, monsters 41, heroes 30.
- Ключевые怪物 типы: bat#70, bee#73, wolf#103, goblin#64, orc#65, orc_s#80, troll#68, spider#104.

---

### Анализ .alm карт разработчиков (40 файлов в assets/maps/pvm/)

#### Формат .alm (полный)
- Заголовок 0x14: magic `0x0052374D` "M7R\0", headersize 0x14, sectioncount.
- Секции: `[8 junk][size u32][id u32][4 junk][data]`.
  - id 0: info (660 байт данных; width/height/name)
  - id 1: tiles (uint16/клетка; file/variant/row编码)
  - id 2: heights (int8/клетка; 0-127)
  - id 3: obstacles (uint8/клетка)
  - id 4: structures, id 5: players, id 6: units, id 7: logic

#### Кодировка тайла (uint16)
- `tile_type = (tile & 0xFF0) >> 8` — индекс файла-1 (0=grass, 1=mountain, 2=water, 3=road)
- `tile_file = (tile & 0xFF0) >> 4` — file_n*16 + variant
- `tile_frame = tile & 0xF` — row/кадр
- `tile_from_spec({file:1-4, variant:0-15, row:0-13})` — сборка tile id

#### Структура BMP тайлов
- **tile1-XX.bmp** (трава): 32×448 px = **14 строк**, 16 файлов = 224 варианта
- **tile2-XX.bmp** (горы): 32×448 px = **14 строк**, 16 файлов = 224 варианта
- **tile3-XX.bmp** (вода): 32×256 px = **8 строк**, 16 файлов = 128 вариантов
- **tile4-XX.bmp** (дорога): 32×448 px = **14 строк**, 4 файла = 56 вариантов

#### Профили биомов (анализ 9 карт)
| Биом | Трава | Горы | Вода | Дорога | Ср.высота |
|------|------|------|------|--------|-----------|
| greenlnd (равнина) | 33% | 30% | 35% | 2.5% | 18 |
| tropic (тропики) | 27% | 9% | 60% | 4% | 10 |
| canyon (каньон) | 56% | 29% | 7% | 7% | 39 |
| orcish (орки) | 62% | 21% | 10% | 7% | 39 |
| gothic (тёмная) | 47% | 31% | 18% | 5% | 42 |
| som (пустыня) | 41% | 46% | 4% | 9% | 74 |
| nord (север) | 36% | 38% | 17% | 9% | 37 |
| islands (острова) | 33% | 18% | 35% | 14% | 64 |

#### Правила переходов terrain (ключевое для генератора!)

**Нет autotile!** Сценаристы ВРУЧНУЮ ставили过渡ные текстуры. Переходы = конкретные variant/row комбинации на клетках-границах.

**Правило: row 4 = «универсальный край» для травы.**
Все травяные клетки на границах с горами/водой/дорогами = `tile1 variant_any row=4`.
Внутри карты = `row=1` (12%) и `row=3` (5.5%).

**Таблица переходов (из анализа 9 карт, ~40K клеток на границах):**

| Граница | Тайл на стороне A | Тайл на стороне B | Доминирование |
|---------|------------------|------------------|---------------|
| GRASS↔MOUNTAIN | tile1:variant:row=4 | tile2:1:4 | 27% от mountain→grass |
| GRASS↔WATER | tile1:variant:row=4 | tile3:9:5 / 5:0 | ~3% каждый |
| GRASS↔ROAD | tile1:variant:row=4 | tile4:1:8 / 2:8 / 1:3 | ~7% каждый |
| MOUNTAIN↔WATER | tile2:1:4 | tile3:13:1 / 2:0 | 35% mountain→water |
| MOUNTAIN↔ROAD | tile2:1:4 | tile4:0:0 / 2:0 / 1:11 | ~8% каждый |
| WATER↔ROAD | tile3:5:2 / 1:2 | tile4:0:0 / 2:0 | ~6% каждый |

**Внутренние тайлы (не на границе):**
- GRASS: `1:1:1` (12%), `1:3:0` (5.5%), `1:3:1-4` (3% каждый)
- MOUNTAIN: `2:1:4` (6.7%), `2:15:3/5/1/4` (3.8-4%), `2:13:1` (3.8%)
- WATER: `3:9:1` (22%), `3:13:1` (20.6%), `3:1:1` (17.1%), `3:5:1` (16.7%)
- ROAD: `4:3:1/5/0/2/4` (5%), `4:1:1/3/5/0/2` (4.5%)

**Вывод для генератора:**
1. Для каждой клетки определить тип terrain (0-3)
2. Проверить 4 соседа — есть ли граница с другим типом
3. Если ГРАНИЦА → выбрать переходный variant/row по таблице выше
4. Если ВНУТРИ → выбрать внутренний variant/row (случайно из топ-N)

#### Запись .alm с нуля (tests/gen_alm_map.gd)
- Рабочий writer: `[header 0x14][info 680][tiles 20+W*H*2][heights 20+W*H][obstacles 20+W*H]`
- Файл открывается в редакторе карт (godot scenes/map_editor.tscn --open-alm=...)
- Файл открывается в игре (main.tscn alm_path)
- Формат проверен: magic, section count, tile encoding — всё корректно.

#### Тестовые скрипты
- `tests/analyze_alm_maps.gd` — анализ terrain/structures/units из .alm (9 карт)
- `tests/analyze_transitions.gd` — анализ переходов terrain-типов (9 карт)
- `tests/analyze_dir_transitions.gd` — анализ directional переходов (N/S/E/W) из 9 карт
- `tests/gen_biome.gd` — генератор terrain по профилю биома (noise + квантили + blur)
- `tests/gen_alm_map.gd` — генератор .alm файла (terrain + transitions + heights)
- `tests/gen_tile_placeholders.gd` — генератор placeholder PNG для tile5/6/7
- `tests/test_simulation.gd` — просмотрщик world_sim (100 дней)

#### Удалённые файлы
- `scripts/tile_directions.gd` — захардкоженные константы (заменены на transition_db.json)
- `assets/maps/tile_directions.json` — дубль
- `assets/maps/transition_rules.json` — пер-клеточные overrides (не нужны)

---

### Редактор переходов terrain-типов (сессия 21.09 вечер+ночь)

#### Система terrain-типов (расширена до 7+2)
| Тип | Tile-файл | Описание | WalkTable cost |
|-----|-----------|----------|----------------|
| 0 | tile1 (224 тайла) | Трава | 8 |
| 1 | tile5 (224 тайла) | Почва | 8 |
| 2 | tile6 (224 тайла) | Песок | 12 |
| 3 | tile3 (128 тайлов) | Вода | 0 (блок) |
| 4 | tile2 (224 тайла) | Горы | 14 |
| 5 | tile4 (56 тайлов) | Дорога | 6 |
| 6 | tile7 (224 тайла) | Грязь | 14 |
| 7 | — | Строение (цвет-плейсхолдер) | — |
| 8 | — | Спавн (цвет-плейсхолдер) | — |

#### Кодировка tile id (tile_from_spec, alm_loader.gd)
- `file_n` (1-7) × 16 + `variant` (0-15) → сдвиг на 4 бита → `| row` (0-15)
- `tile_from_spec({file, variant, row})`: `n = (file-1)*16 + variant`, результат `(n<<4)|row`
- `tile_type(tile)`: `(tile & 0xFF0) >> 8` — типterrain 0-6
- `tile_file(tile)`: `(tile & 0xFF0) >> 4` — индекс файла-1
- `tile_frame(tile)`: `tile & 0xF` — ряд/кадр

#### Визуальный редактор переходов (`scripts/transition_editor.gd`)
- Кнопка «Transitions» в редакторе карт → открывает окно
- Два OptionButton: Тип A (клетка) / Тип B (сосед)
- Сетка 3×3: центр = тип A, 8 ячеек = направления (N/NE/E/SE/S/SW/W/NW)
- Клик по ячейке → палитра **только тайлов типа A** (из его tile-файла)
- Кнопки: Сохранить / Импорт из .alm / Перечитать / Закрыть
- База: `assets/maps/transition_db.json`

#### База переходов (`assets/maps/transition_db.json`)
- Ключ: `"типA:направление:типB"` → `{file, variant, row}`
- Interior: `"тип"` → `{file, variant, row}` — тайл «внутри» без перехода
- 96 правил для типов 0-3 (из 9 карт разработчиков) + дефолтные для типов 4-6
- Импорт: анализ `analyze_dir_transitions.gd` → самый частотный тайл для каждой комбинации

#### Генератор карт (`tests/gen_alm_map.gd`)
- Читает `transition_db.json` вместо хардкода
- `_edge(t, s, x, y)`: ищет cardinal правила, потом diagonal, fallback interior
- `_interior(t, x, y)`: читает из DB `interior.type`

#### Хранение земли под объектами (`under_tiles` в custom_map.gd)
- Формат: `тип * 256 + tex_idx` (упаковано в один int)
- `_under_pack(type, tex)` / `_under_type(v)` / `_under_tex(v)` — хелперы
- Старый формат (0-6 = просто тип) совместим: при загрузке конвертируется
- При размещении объекта (type >= 7): `under_tiles[i] = _under_pack(tiles[i], tex_ids[i])`
- При рендере: `tilemap.set_cell(cell, _source_id_for(_under_type(under), _under_tex(under)))`
- При ластике: восстанавливается и тип, и tex_idx

#### Важные границы в коде
- Terrain: 0-6, объекты: 7-8
- `t < 7` = terrain, `t >= 7` = объект/спавн
- `_source_id_for(type_id, tex_idx)`: проверка `type_id >= 9` → return -1
- `texture_sets[type]` — набор текстур для типа; объекты хранятся в `texture_sets[7]`
- `DEFAULT_TEX` в custom_map.gd — дефолтные текстуры для каждого типа

---

### Transition editor — доделка (сессия 22.09)

#### Плитки tile5/6/7 (почва/песок/грязь)
- `tests/gen_tile_placeholders.gd` — генерирует **и PNG** (224 ячейки 32×32 в `assets/terrain/tiles/tileN-VV_RR.png` для палитры редактора), **и BMP** (16 полос 32×448 в `assets/terrain/tileN-VV.bmp` для AlmMap/CustomMap).
- BMP пишется **вручную 24-бит bottom-up** (у Godot 4 нет `Image.save_bmp`; top-down с отрицательной высотой Godot **не импортирует** → `valid=false`).
- После генерации обязательно `godot --headless --path ... --import` — иначе `ResourceLoader.exists` = false.
- Текстуры — процедурный шум по базовому цвету (не плоская заливка).

#### transition_editor.gd
- `TERRAIN_FILE := {0:1, 1:2, 2:3, 3:4, 4:5, 5:6, 6:7}` — тип → tile-файл **для .alm/рендера** (генераторы пересчитывают по типу A).
- `PALETTE_FILE := {0:1, 1:2, 2:3, 3:4, 4:5, 5:1, 6:1}` — что показывать в палитре. **Песок (5) и грязь (6) выбираются из tile1**; в transition_db у них file=1.
- Палитра: `max_rows = 8` для tile3 (вода), `max_vars = 4` для tile4 (дорога), иначе 14×16.
- **Центральная ячейка (interior) редактируется**: клик по «A» открывает палитру interior типа A; «Сбросить interior» чистит запись.
- **Импорт из .alm**: сканирует `DirAccess` папку `assets/maps/pvm/` (все `*.alm`/`*.ALM`), импортирует **8 направлений** + interior.

#### transition_db.json
- **336 правил** + interior для всех 7.
- `file` в правиле = **палитра** (для типов 5/6 это 1 = tile1). Генераторы `.alm` вызывают `_spec_for_type(type_a, spec)` → `file = TERRAIN_FILE[type_a]`, variant/row из правила.
- Диагонали заполняются наследованием от кардинальных; format UTF-8 без BOM, TAB.

#### Рендер tile5/6/7
- `alm_map.gd:_build_atlas` — файлы `[1..7]`, `vmax_by_file` включает 5/6/7 (16 вариантов).
- `custom_map.gd:_load_tile_region` — кламп `0..7` (был `0..4` → почва/песок/грязь рендерилась как дорога).
- `texture_settings.gd` — вкладки tile1..tile7 + «Объекты».

#### Тесты
- `tests/test_transitions.gd` → `RESULT:OK transition_editor+db`: 336 правил, file-маппинг, 224 PNG × 3, BMP 32×448, roundtrip `tile_from_spec`/`tile_type` для типов 4/5/6, полнота пары 4↔5 (почва↔песок).
- `tests/test_import_smoke.gd` → `RESULT:OK import_smoke`: сканирует `assets/maps/pvm/`, грузит все `.alm` (на домашнем 11 карт, только типы 0-3), считает edge-статистику (410974 клеток, 96 уникальных ключей) — та же логика, что `_on_import_alm`.
- `tests/gen_alm_map.gd` / `gen_smart_map.gd` — читают 336 rules, генерируют карты OK.

#### Два ПК
- Рабочий ПК: `C:\Work\Allodshome`, Godot `C:\Games\Godot_...`.
- Домашний ПК: `D:\Work\UnityProjects\Allodshome_Godot`, Godot `D:\Work\UnityProjects\Godot_v4.7.2-stable_win64_console.exe`.
- Карты для обучения генератора — `assets/maps/pvm/` (на домашнем: 11 шт; на рабочем может отличаться — импорт сканирует каталог, не хардкод).

#### Shape-based генератор и visual-фиксы (сессия 23.09)
- **`tests/analyze_shapes.gd`** — аудит форм: для каждой border-клетки 8-бит маска соседей (битовые индексы `[N,NE,E,SE,S,SW,W,NW]`), копит топ-4 тайла по частоте → `assets/maps/shapes_db.json`: `{"shapes": {"тип:maskstr": {tiles[...top4, w], total}}, "interior": {"тип": {tiles[...top6], total}}}`. 603 формы, interior для типов 0-3.
- **`tests/gen_smart_map.gd`** — `_pick_tile`: mask≠0 → (1) exact-форма, (2) hybrid для t≥4 (топология травы 0, файл из `TERRAIN_FILE[t]`), (3) ближайшая по Хэммингу, (4) rules-fallback. mask==0 → interior.
- **Fix «квадрат почвы» на границе**: `_compute_edge_rows` — для типов 0 (трава) и 1 (горы) «универсальный край» row=4; в `_shape_tile` граничные клетки (mask & CARDINAL) берут ТОЛЬКО тайлы с краевым row, иначе → empty → rules-fallback. Итог: **100% граничных клеток травы/гор — краевая кромка** (было 44%). {edge: 0:4, 1:4}. Вода (2) и дорога (3) не навязываются (у них края зависят от соседа).
- **Fix «чанков одной текстуры»**: `_interior_tile` вместо worley-сетки 8×8 (давала блоки одного тайла) → `_interior_value`: низкочастотный FastNoiseLite ~1/14 + слабый высокочастотный ~1/60, выбор по непрерывному значению в весовой диапазон топ-6 интерьера. Связные поля без жёстких границ, без шахматки. Интерьер травы: 5 разных тайлов, гор — 4, вода — 4.
- **`tests/render_alm_png.gd`** — рендер .alm→PNG для визуального контроля (`missing_tiles=0`).
- Соотношение: `Shapes: exact≈3850 subset≈437 rules-fallback≈300`; terrain трава 44.5% / горы 20% / вода 32% / дорога 3.5%.
- Проверка: `--headless --quit` → `0 SCRIPT ERROR`.

#### Дороги-коридоры и извилистый берег (сессия 23.09, вечер)
- **Проблема дороги**: раньше дорога = шумовые пятна (578 клеток, 6 компонентов по 49/39/36/..., 228 прогонов ширины 1). В оригинале (greenlnd) — ОДИН связный коридор 1078 клеток, ширина ~2, не касается краёв карты, примыкание к воде 0–9%.
- **Проблема берега**: «угловатость» = форма береговой линии (длинные прямые лестничные участки), не текстура кромки. Метрика: компактность травы area/perim (ориг ~1.5, было 7.1), уникальные 8-бит маски кромки (ориг ~230–245, было 42).
- **Фикс дороги** в `tests/gen_smart_map.gd`:
  - `_caw_roads` переписан на **A\*** по суше (`_a_star` + `_largest_land` + `_anchor_in`): якоря берутся из крупнейшего связного «материка», поэтому путь математически гарантирован и дорога НЕ рвётся у воды.
  - Цены A*: шаг по траве 10, по горам 18 (горы дороже → дорога ложится на траву), штраф за поворот 6 (плавность), пер-клеточный шум `(hash%9)-4` (извилистость), +3 за соседство с водой (отталкивание).
  - `_is_road_cell` пускает и тип 3 (дорога по дороге), чтобы второй коридор не блокировался первым.
  - Запись ленты: по каждому пути `p` рисуются `p` и `p+lane` (lane = перпендикуляр сегмента) → ширина ровно 2.
- **Фикс берега**: шум в `_place_terrain` = `base*0.55 + coastal(1/16, 4 октавы)*0.3 + ripple(1/7)*0.15`, box-blur 5×5 → 3×3. Дорога (тип 3) исключена из `mid_types` (рисуется отдельным проходом).
- **Результат**: `ROAD: cells≈690 comps=[690]` (1 компонент, bbox почти на весь 128×128, ширины доминируют 2 и 4), water-adj ~11%. Трава compactness **1.80** (ориг 1.5–1.8), маски кромки **109**. Рендер `missing_tiles=0`, `--quit` → `0 SCRIPT ERROR`.
- Диагностика в логе: `_road_stats()` печатает `ROAD: cells/comps/bbox/widths/adj`; статы травы — через python-скрипт по .alm (compactness, masks).

