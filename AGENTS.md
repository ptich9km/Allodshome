# AGENTS.md — заметки агента по проекту Allodshome_Godot

> Памятка для продолжения работы из любой сессии. Обновляй при каждом заметном шаге.
> Обновлено: **Сессия 21.09 (вечер+ночь)** — визуальный редактор переходов terrain-типов, расширение до 7+2 типов, исправлен рендер земли под объектами.
>
> Запуск головного headless-раннера мира: `godot --headless --path ... --script res://scripts/world/sim_runner.gd` (см. Слой-2 заметку ниже).

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

## Что сделано сегодня (главное)

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

## План / что осталось (в порядке приоритета)

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

## Статистика / производные (принятое решение)
- `hit_chance = clampi(50 + attack - defense, 5, 95)` (как в оригинале).
- `absorption` — броня/поглощение (физика), `protection_*` — защита стихий (магия).
- Шанс промаха `is_miss(attacker, attacker_defender)` через `hit_chance`. Промах = «тихий промах» без урона, для магии урона нет при промахе.
- Всё применение урона через `take_damage` (внутри — щит юнита: `shield_reduce`, затем HP).

## Файловая структура (ключевое)
- `scripts/game.gd` — автозагрузка, единые статы/математика боя (`deal_damage`, `is_miss`, `unit_*`, `tick_shields`, `deal_damage_area`), а также `unit_absorption`, `unit_protection` и т.д.
- `scripts/enemy.gd` (~304 строк) — класс врагов: `take_damage`, `deal_damage` подключение, `flee/chase/attack`, лут, статы `get_*`.
- `scripts/player.gd` — герой (ближний бой через deal_damage, магия, статы `get_attack/get_defense/etc`).
- `scripts/mercenary.gd` — наёмник (атака через deal_damage, `take_damage`).
- `scripts/projectile.gd` — снаряды (магия/область).
- `scripts/unit.gd` / `unit_db.gd` — база юнитов (статы монстров/героев).
- `scripts/spell_db.gd` — заклинания (сферы/магия).
- `scripts/ui.gd`, `scripts/character_select.gd` — UI (панель сфер мага вместо навыков оружия).

## Как проверять
- Godot headless через `--quit` (см. команду вверху) — главный контроль парсинга.
- Только `.gd`-файлы читать на русском; `assets/**` — бинарь/картинки, игнорировать.

---

## Процедурная генерация карт (сессия 21.09 — активно)

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

