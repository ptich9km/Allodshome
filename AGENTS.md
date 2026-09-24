# AGENTS.md — Allods Home (Godot 4.7)

Этот файл — единая точка входа в проект для **любой ИИ-системы и человека**.
Агент обязан прочитать файл целиком перед любыми изменениями; человек правит его по ходу развития проекта.

> Правило: при каждом заметном шаге (фича/фикс/решение) — обновляй «Журнал сессий» (раздел 12).
> Последнее обновление: 24.09 — переработка UI таверны по `godot-ui-control` / `game-ui-ux` / `rpg`. Требуется ручная визуальная проверка.

## Содержание

1. [Паспорт проекта](#1-паспорт-проекта)
2. [Машины и запуск Godot](#2-машины-и-запуск-godot)
3. [Проверка после правок](#3-проверка-после-правок)
4. [Структура репозитория](#4-структура-репозитория)
5. [Конвенции кода](#5-конвенции-кода)
6. [Ключевая архитектура — единая точка урона](#6-ключевая-архитектура--единая-точка-урона)
7. [Слой мира (SIM-эмуляция)](#7-слой-мира-sim-эмуляция)
8. [Процедурная генерация карт](#8-процедурная-генерация-карт)
9. [Правила для агентов](#9-правила-для-агентов)
10. [Рабочий процесс агента](#10-рабочий-процесс-агента)
11. [Доступные скилы](#11-доступные-скилы)
12. [Журнал сессий](#12-журнал-сессий)
13. [Дорожная карта](#13-дорожная-карта)

---

## 1. Паспорт проекта

| Поле | Значение |
|------|----------|
| Название | Allods Home (`config/name = "Allods Home"`) |
| Движок | Godot 4.7, GDScript 2.0 |
| Главная сцена | `res://scenes/character_select.tscn` (старт игры); мир — `main.tscn` |
| Корень | `res://` |
| Autoload | `WorldBus` (единственный; `scripts/world/world_bus.gd`) |
| Глобальные классы (`class_name`) | `Game` (`game.gd`, Node2D + `static`-математика боя), `SoundDB`, `SpellDB`, `GameUI` (`ui.gd`) |
| Жанр | песочница + тактический RPG («духовный наследник» Аллодов II, не копия) |

## 2. Машины и запуск Godot

Проект ведётся на двух ПК; пути различаются.

| | Путь проекта | Консольный Godot |
|---|---|---|
| **Домашний (эта машина)** | `D:\Work\Allodshome` | `D:\Work\UnityProjects\Godot_v4.7.2-stable_win64_console.exe` |
| **Рабочий** | `C:\Work\Allodshome` | `C:\Games\Godot_v4.7.2-stable_win64_console.exe` |

- GUI-вариант движка лежит рядом (суффикс `_win64.exe`).
- Карты для обучения генератора — `assets/maps/pvm/`. Количество файлов на разных ПК может отличаться (импорт сканирует каталог, не хардкодит).

## 3. Проверка после правок

Контрольная точка после **любых** правок — headless-парсинг (команда для домашнего ПК):

```powershell
& 'D:\Work\UnityProjects\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'D:\Work\Allodshome' --quit 2>&1 | Select-String 'SCRIPT ERROR|Parse Error|ERROR:'
```

- **Нет `SCRIPT ERROR`** = скрипты компилируются.
- `ERROR: 1 resources still in use at exit` — безобидный «хвост», не ошибка.
- **Свежий клон**: без кэша `.godot/` глобальные классы (`Game`, `SoundDB`, …) не зарегистрированы → `--quit` показывает ложные `Identifier ... not declared`. Сначала один раз выполни `--headless --import` (долго — импортируются сотни картинок), потом парсинг.
- В выводе Godot бывает Unicode-каша из PNG/CJK-файлов в `assets/` — это норма. Читай только `.gd`. НЕ запускай полный обход `assets` с фильтром по CJK — там сотни картинок.
- Для изменённого UI обязательно запускать панель на референсном разрешении 1280×800 и проверить заполнение ячеек, отсутствие обрезания, кнопки, счётчики, закрытие, мышь и фокус.
- Если визуальный тест ещё не проводил пользователь, писать: «Требуется ручная визуальная проверка».
- Headless-раннер мира (100 дней симуляции): `godot --headless --path . --script res://scripts/world/sim_runner.gd`.

## 4. Структура репозитория

```text
addons/      — сторонние/локальные плагины (не менять без согласования)
assets/      — арт, звук, шрифты, карты (.alm/.bmp/.json)
resources/   — .tres ресурсы
scenes/      — .tscn (map_editor, main, character_select, ...)
scripts/     — GDScript
tests/       — автотесты и генераторы (GUT/GdUnit4 + analysis-скрипты)
ui/          — UI-сцены и скрипты
```

Ключевые скрипты:

| Файл | Назначение |
|------|------------|
| `scripts/game.gd` | `class_name Game`, `static`-математика боя: `deal_damage`, `is_miss`, `unit_*`, `tick_shields`, `deal_damage_area`, `shield_reduce`, `apply_shield` |
| `scripts/player.gd` | герой: ближний бой/магия через `Game.*`, статы `get_attack/get_defense/...`, `_active_sphere()` |
| `scripts/enemy.gd` | враги: `take_damage`, flee/chase/attack, лут, статы `get_*` |
| `scripts/mercenary.gd` | наёмники: атака через `Game.*`, `take_damage`, `lifespan` |
| `scripts/projectile.gd` | снаряды (магия/область): урон через `Game.deal_damage(_area)` |
| `scripts/unit.gd`, `unit_db.gd` | база юнитов (статы монстров/героев) |
| `scripts/spell_db.gd` | заклинания (сферы/магия), `sphere_of(spell_name)` |
| `scripts/ui.gd`, `scripts/character_select.gd` | UI; для мага — панель сфер вместо навыков оружия |
| `scripts/transition_editor.gd` | визуальный редактор переходов terrain (в редакторе карт) |
| `scripts/world/world_state.gd`, `world_bus.gd`, `world_sim.gd` | Слой-2, SIM-мир |
| `scripts/portal_marker.gd` | `class_name PortalMarker`, Sprite2D + анимация 4 кадра |

## 5. Конвенции кода

- **Отступы:** табы.
- **Именование:** классы/узлы `PascalCase`; файлы/папки/функции/переменные `snake_case`; константы `CONSTANT_CASE`; сигналы в прошедшем времени (`health_changed`).
- **Типизация:** типизированный GDScript (`var health: int`, `func f(a: int) -> void:`). `:=` только там, где тип выводится, — в autoload невыводимые места обязательны `: <тип>`.
- **Узлы:** `@onready` + уникальные имена (`%Node`) вместо жёстких `get_node()` путей.
- **Сигналы:** предпочитать события прямым ссылкам на родителей/детей.
- **Композиция** поверх глубокого наследования; **данные** — в `Resource`/JSON, не в хардкод-словарях; `@export` для инспектора.
- **Процессы:** движение/физика в `_physics_process`, `_process` только под frame-логику; таймеры/сигналы вместо опроса.
- **Autoload:** не добавлять/не удалять без явного согласования (сейчас один — `WorldBus`).
- **Сцены:** неглубокие деревья, один корень, инстансинг.
- **UI:** использовать `Control`, `Container`, anchors и size flags; не размещать каждый дочерний элемент вручную. Функциональные панели строить через `GridContainer`/`HBoxContainer`/`VBoxContainer`, общее оформление — через `Theme`.
- **UI-масштабирование:** одно референсное разрешение и равномерный масштаб всего интерфейса; не уменьшать отдельно фоновую текстуру через `Image.resize()` без необходимости. Иконки размещать в `TextureRect` с `STRETCH_KEEP_ASPECT_CENTERED` и проверять отсутствие обрезания.
- **UI-ввод:** панели должны работать мышью, клавиатурой и геймпадом; при открытии задавать начальный фокус, для регулярных сеток задавать предсказуемую навигацию.
- **Не удалять/не переименовывать** `.tres`/`.tscn` без согласования.

## 6. Ключевая архитектура — единая точка урона

Весь урон (герой, магия, враги, наёмники, снаряды, AoE) идёт через **`Game.deal_damage(...)`**, а не напрямую через `enemy.take_damage`. Математика живет в одном месте — `scripts/game.gd`.

| Хелпер | Назначение |
|--------|------------|
| `hit_chance(attack: int, defense: int) -> int` | `clampi(50 + attack - defense, 5, 95)` — процент попадания |
| `is_miss(attacker, defender) -> bool` | промах по шансу `hit_chance` |
| `unit_attack / unit_defense / unit_absorption(unit) -> int` | универсальные статы (герой/враг/наёмник через их `get_*`) |
| `unit_protection(unit, sphere: String) -> int` | защита от стихии (fire/water/air/earth/astral) |
| `tick_shields(delta)` | тикает срок жизни щитов |
| `deal_damage(target, dmg, kind, sphere, attacker) -> int` | **единая точка урона** |
| `deal_damage_area(targets, dmg, kind, sphere, attacker)` | урон по площади (AoE) |
| `shield_reduce(unit, dmg) -> int` | внутренний щит юнита |
| `apply_shield(unit, strength, seconds)` | наложить щит |

Правила внутри `deal_damage`:

- `kind == "physical"` → `unit_absorption` (броня) + шанс промаха (`is_miss`) → `target.take_damage(dmg, attacker)`.
- `kind == "magic"` → `unit_protection(target, sphere)` (защита стихии) → `target.take_damage(...)`.
- `deal_damage` сам вызывает `take_damage`; щиты живут **внутри** `take_damage` (`shield_reduce` → HP) и не дублируются.
- Промах магии = «тихий промах», урона нет.

Точки подключения:

- `player.gd` (~594) — рукопашная героя: `is_miss` + `deal_damage(target, damage, "physical", "", self)`. Посох мага bьёт как мгновенная сфера (`_active_sphere()`): `deal_damage(..., "magic", sphere, self)` + опыт сфере.
- `player.gd` (~761) — мгновенная магия: `deal_damage(target, dmg, "magic", sphere, self)`.
- `enemy.gd` (~125) — удар врага: `is_miss` + `deal_damage(player, damage, "physical", "", self)`.
- `mercenary.gd` (~116) — атака наёмника: `is_miss` + `deal_damage(..., "physical", "", self)`.
- `projectile.gd` (~92/101) — снаряд на прилёте: `deal_damage` (одиночный `"magic"`, sphere из `SpellDB.sphere_of`) или `deal_damage_area` (AoE).

## 7. Слой мира (SIM-эмуляция)

Глобальная SIM-логика (фракции, угроза, журнал) живёт в `scripts/world/`:

- `world_state.gd` — состояние мира: `day`, `global_threat`, `relations`, `hero`, типизированный `journal: Array[Dictionary]`, генератор id `_id()` через `if/elif` (не `match` с `_u += 1` — Parse Error).
- `world_bus.gd` — `class WorldBus` (autoload). В `reseed()` переменные объявлять `: Dictionary`, а не `:=` (инференция в autoload запрещена).
- `world_sim.gd` — симуляция дней; типы (`var d: float`) обязательны, где вывод неоднозначен.
- `sim_runner.gd` — headless-просмотр (100 дней): `RESULT: world survived 100 days ... journal=208`.

## 8. Процедурная генерация карт

### 8.1 Концепция (решения пользователя)

- Не копия Аллодов II, а духовный наследник: песочница + тактический RPG.
- **Зона = процедурная карта-биом** (одна карта = один биом); переход между зонами — портал на новой карте. НЕ участки одной большой карты.
- На карте героя — реальный бой с туманом войны и «!»-маркерами; на остальных территориях — SIM-эмуляция.
- Лог боя — только на текущей карте (SIM-бои не засоряют лог).
- Размеры карт пока 48×48 (в тестах 128×128), вырастут после отработки генерации.
- **Антагонист НЕ копия Урда.** Песочница без «конца мира» — нарастающее давление/состояние мира. Варианты: Растворение (рекомендация), Цикл, Шёпот — финального решения нет.

### 8.2 Фракции и репутация (на основе `units_db.json`, 89 наборов: humans 18, monsters 41, heroes 30)

1. **Альянс Света** — humans/ (militia, swordsman, archer, mage)
2. **Орды Огня** — orc/goblin/troll/ogre
3. **Пожинатели** — undead (skeleton, zombie, necromant, ghost)
4. **Круг Друидов** — druid, nature spirits
5. **Серые** — monsters/ (bat, bee, wolf, spider, dino, turtle, squirrel, ...) — **всегда враги**

- Герой по умолчанию воюет только с Серыми; с фракциями нейтралитет, можно ухудшать/улучшать до войны.
- Прекрасеты отношений минимальны, дальше — война/мир/нейтралитет сами.
- Репутация → качество наёмников в тавернах + тир магазинов.
- Прогрессия: **Z1** старт/обучение → **Z2** средние Серые + войны фракций → **Z3** тяжёлые + разборки армий → **Z4a-d** базовые территории фракций.
- Бой: отряд = герой + 2–3 наёмника (наёмникам нельзя менять экипировку/навыки); активная пауза = полная пауза + приказы.

### 8.3 Формат `.alm` (карты разработчиков, `assets/maps/pvm/`)

- Заголовок 0x14: magic `0x0052374D` "M7R\0", headersize, sectioncount.
- Секции: `[8 junk][size u32][id u32][4 junk][data]`:
  - id 0 info (660 Б; width/height/name), id 1 tiles (uint16/клетка), id 2 heights (int8; 0-127), id 3 obstacles (uint8), id 4 structures, id 5 players, id 6 units, id 7 logic.
- Запись с нуля: `[header 0x14][info 680][tiles 20+W*H*2][heights 20+W*H][obstacles 20+W*H]` (`tests/gen_alm_map.gd`).

### 8.4 Terrain-типы (расширено до 7 + 2)

| Тип | Tile-файл | Назначение | WalkTable cost |
|-----|-----------|------------|----------------|
| 0 | tile1 (224) | Трава | 8 |
| 1 | tile2 (224) | Горы | 14 |
| 2 | tile3 (128) | Вода | 0 (блок) |
| 3 | tile4 (56) | Дорога | 6 |
| 4 | tile5 (224) | Почва | 8 |
| 5 | tile6 (224) | Песок | 12 |
| 6 | tile7 (224) | Грязь | 14 |
| 7 | — | Строение (цвет-плейсхолдер) | — |
| 8 | — | Спавн (цвет-плейсхолдер) | — |

- Границы в коде: `t < 7` = terrain, `t >= 7` = объект/спавн; `_source_id_for(type_id, tex_idx)` → `type_id >= 9` → `-1`.

### 8.5 Кодировка тайла (uint16) и BMP-структуры

- `tile_from_spec({file, variant, row})`: `n = (file - 1) * 16 + variant`, результат `(n << 4) | row`.
- `tile_type(tile) = (tile & 0xFF0) >> 8` — тип terrain 0–6; `tile_file = (tile & 0xFF0) >> 4`; `tile_frame = tile & 0xF`.
- BMP: tile1/2/4 — 32×448 px = **14 строк**; tile3 (вода) — 32×256 = **8 строк**.
- Плейсхолдеры tile5/6/7: `tests/gen_tile_placeholders.gd` — PNG 32×32 для палитры и BMP 24-бит **bottom-up** (у Godot 4 нет `Image.save_bmp`; top-down не импортируется → `valid=false`). После генерации обязателен `--headless --import`, иначе `ResourceLoader.exists` = false.

### 8.6 Переходы между terrain-типами

**Autotile нет** — сценаристы ставили переходные текстуры вручную; переход = конкретный `variant/row` на клетках-границах.

- `row 4` = «универсальный край» травы/гор: все граничные клетки травы/гор берут краевой row (маска & CARDINAL) — итог 100% граничных клеток с кромкой (было 44%). Вода и дорога края не навязываются.
- База правил — `assets/maps/transition_db.json`: ключ `"типA:направление:типB"` → `{file, variant, row}`; interior — ключ `"тип"`. **336 правил** + interior для всех 7. Диагонали наследуются от кардинальных.
- Возможные пары переходов (анализ карт): см. `tests/analyze_transitions.gd`, `tests/analyze_dir_transitions.gd`.
- Редактор — `scripts/transition_editor.gd`: сетка 3×3 (центр A + 8 направлений), палитра только тайлов типа A, импорт из `.alm` (сканирует `assets/maps/pvm/`), центральная ячейка = interior.
- Палитра: `PALETTE_FILE {0:1, 1:2, 2:3, 3:4, 4:5, 5:1, 6:1}` (песок/грязь выбираются из tile1); `.alm`-рендер — `TERRAIN_FILE {0:1, 1:2, 2:3, 3:4, 4:5, 5:6, 6:7}`.
- Хранение земли под объектами (`under_tiles` в `custom_map.gd`): упаковка `тип * 256 + tex_idx`; при ластике восстанавливаются и тип, и текстура.

### 8.7 Генераторы и тесты (`tests/`)

| Файл | Назначение |
|------|------------|
| `analyze_alm_maps.gd` | анализ terrain/structures/units из `.alm` |
| `analyze_transitions.gd` / `analyze_dir_transitions.gd` | статистика переходов (cardinal/diagonal) |
| `analyze_shapes.gd` | аудит форм: 8-бит маски соседей `[N,NE,E,SE,S,SW,W,NW]`, топ-4 тайла → `assets/maps/shapes_db.json` (603 формы) |
| `gen_biome.gd` | terrain по профилю биома (noise + квантили + blur) |
| `gen_alm_map.gd` | запись `.alm` (terrain + transitions + heights) |
| `gen_smart_map.gd` | **главный генератор** (см. ниже) |
| `gen_tile_placeholders.gd` | placeholder PNG/BMP для tile5/6/7 |
| `render_alm_png.gd` | `.alm`→PNG для визуального контроля (`missing_tiles=0`) |
| `test_transitions.gd` | `RESULT:OK transition_editor+db` (336 правил, roundtrip, полнота 4↔5) |
| `test_import_smoke.gd` | `RESULT:OK import_smoke` (загрузка всех `.alm` из pvm/, edge-статистика) |
| `test_simulation.gd` | просмотр `world_sim` |

**Генератор умных карт (`gen_smart_map.gd`) — текущие решения:**

- `_pick_tile`: mask≠0 → (1) exact-форма, (2) hybrid для t≥4 (топология травы, файл из `TERRAIN_FILE[t]`), (3) ближайшая по Хэммингу, (4) rules-fallback. mask==0 → interior.
- Интерьер без «чанков»: `_interior_value` — низкочастотный FastNoiseLite ~1/14 + высокочастотный ~1/60, выбор в весовой диапазон топ-6 интерьера.
- **Дорога = сеть городов MST:** города — овалы ≈11×11 дорогой (type 3) по профилю зоны; дороги — MST (Прим) + A* коридоры ширины 2 (`_place_cities`/`_connect_cities`). Цены A*: трава 10, горы 18, штраф за поворот 6, шум `(hash%9)-4`, +3 у воды. `_is_road_cell` пропускает все не-водные типы.
- **Извилистый берег:** шум `base*0.55 + coastal(1/16, 4 октавы)*0.3 + ripple(1/7)*0.15`, box-blur 3×3. Метрика — компактность травы area/perim (ориг 1.5–1.8) и уникальные 8-бит-маски кромки (~230–245). Достигнуто: compactness **1.80**, маски **109**.
- **Voronoi-биомы:** база — только почва (трава/почва/песок/грязь), связные регионы вместо полос шума; горы/вода добавляются этапом 4 по экстремумам `_field` (`_water_thr`/`_mountain_thr`, ~10/90-й перцентили). `_field`, `_water_thr`, `_mountain_thr` — class variables.
- **Псевдо-высоты** `_pick_height`: вода 0–15, горы 40–127, трава 10–60, песок 5–35, грязь 8–33, дорога = интерполяция от соседей.
- **Portal + Spawn:** `portal_marker.gd`; генератор кладёт spawn у дороги, портал на противоположном краю; sidecar `.spawn.json`/`.portal.json`; `alm_map.gd` грузит маркеры, `game.gd` → телепорт на спавн.

## 9. Правила для агентов

### 9.1 Scope

- **Одна задача на запрос.** Не смешивать несвязанные изменения.
- **Минимально безопасное изменение** — только то, что нужно для задачи.
- **Без несанкционированного рефакторинга** (переименования/форматирование/реструктуризация).
- **Без новых зависимостей** (addons/плагины/внешние библиотеки) без согласования.
- Оставаться в рамках задачи; если нужно задеть другой файл — спросить.
- **При неоднозначности — спрашивать**, не гадать.

### 9.2 Антигалюцинации

- Не выдумывать Godot API, классы, методы, сигналы, свойства.
- Не использовать API, которых нет в текущей версии движка или в коде проекта.
- Не выдумывать пути, сцены, узлы, autoload.
- Перед использованием узла/сигнала/ресурса — проверить, что он существует (код или официальная документация).
- Не уверен — ищи в коде или спроси. Не догадывайся.

### 9.3 Версионирование (git)

- **Коммит — только ПОСЛЕ ручной проверки человеком** того, что сделано. Игра делается для людей: любой результат должен быть проверен в игре/визуально, прежде чем попадёт в историю. Без теста человеком коммит не делать (спросить, когда удобно протестировать).
- **Никогда не коммитить напрямую в `main`** (используется `master`; уточняй текущую ветку).
- Ветки: `feature/agent-<short-task-name>`.
- Сообщения коммитов: `<type>(<scope>): <description>`; типы `feat|fix|refactor|test|docs|chore`.
- Не переписывать историю, не force-push, не удалять ветки без согласования.

### 9.4 Approval gates — стоп и запрос одобрения перед

- изменением `project.godot`
- добавлением/удалением autoload
- изменением input map
- добавлением/удалением addons/плагинов
- удалением/переименованием сцен, ресурсов, скриптов
- изменением export presets
- рефакторингом архитектуры/структуры папок
- разрушительными командами (`rm -rf`, `git reset --hard`)

## 10. Рабочий процесс агента

### 10.1 Обязательный Skill-First workflow

Перед анализом, проектированием и реализацией агент обязан:

1. Прочитать `AGENTS.md` и релевантные файлы.
2. Определить домен задачи и загрузить через skill tool все подходящие skills **до составления плана и архитектурного решения**.
3. Для междисциплинарной задачи загрузить отдельный skill для каждого затронутого домена.
4. Перечислить использованные skills в начале плана и указать, какие требования из них повлияли на решение.
5. Проверить решение против типичных ошибок из skills; если архитектурный выбор неочевиден, сравнить минимум два варианта и объяснить выбор.
6. Короткий план: что изменится / какие файлы / как проверимся.
7. Дождаться одобрения, если задача нетривиальна или задевает approval gates.
8. Реализовать минимальное изменение.
9. Прогнать тесты и проверки (§3).
10. Отчёт: `Skills: <перечень>`, суть изменений, влияние требований skills, файлы, результаты тестов, блокеры/неопределённости.

Обязательная карта выбора skills:

| Задача | Skills |
|--------|--------|
| UI, панели, инвентарь, `Control` | `godot-ui-control` |
| UX, расположение, адаптивность, фокус | `game-ui-ux` |
| Фоны, иконки, визуальные ассеты | `create-game-assets` |
| Движение и физика | `godot-2d-movement`, `godot-physics` |
| Патрули, преследование, AI | `game-ai` |
| Процедурные карты и генерация | `procedural-gen` |
| RPG, инвентарь, экипировка, бой | `rpg` |
| Сохранения | `save-systems` |
| Аудио | `godot-audio`, `audio-design` |

Запрещено выдавать решение, нарушающее загруженный skill. Если требование skill намеренно неприменимо, агент обязан прямо объяснить это до реализации. Если подходящий skill не был загружен, агент обязан пересмотреть решение до продолжения работы.

### 10.2 Обязательный UI-чеклист

Перед реализацией интерфейса проверить:

- используются `Control`, `Container`, anchors и size flags;
- нет ручного размещения каждого дочернего элемента;
- фон и функциональные элементы масштабируются согласованно от одного референсного разрешения;
- фон не пересэмплируется через `Image.resize()` без реальной необходимости;
- иконки используют `STRETCH_KEEP_ASPECT_CENTERED` и не обрезаются;
- панель сохраняет работоспособность при изменении размера окна;
- есть управление мышью, клавиатурой и геймпадом;
- при открытии установлен начальный фокус, для регулярных сеток задана предсказуемая навигация;
- стили вынесены в `Theme`, а не заданы локальными override для каждого узла;
- текст и кнопки не имеют хрупких фиксированных размеров;
- UI проверен визуально на переполнение, обрезание и выравнивание (§3).

**Definition of Done** — задача готова только когда:

- код парсится без ошибок;
- релевантные тесты прошли (или явно заявлено их отсутствие);
- не внесены новые предупреждения;
- изменения ограничены задачей;
- есть чёткий отчёт с доказательствами (никаких «тесты прошли», если не запускались).

## 11. Доступные скилы

Скилы лежат в `.agents/skills/` (папка в `.gitignore`, в репо не коммитится). Каждый скил — папка с `SKILL.md`; frontmatter `description` задаёт, когда его подтягивать. Категории: `godot/`, `disciplines/`, `genres/`, `workflows/`. Проект — Godot 4.7 → основной набор: `godot/*`; по жанру актуальны `rpg` и `roguelike`.

### Godot

| Skill | Scope |
|-------|-------|
| [`godot-gdscript`](.agents/skills/godot/godot-gdscript/SKILL.md) | GDScript 2.0: типизация, lifecycle, `@export`/`@onready`, сигналы, `await` |
| [`godot-nodes-scenes`](.agents/skills/godot/godot-nodes-scenes/SKILL.md) | Scene tree, композиция узлов, `PackedScene`, autoloads |
| [`godot-signals-groups`](.agents/skills/godot/godot-signals-groups/SKILL.md) | Сигналы (Callable, `bind`, one-shot) + группы (`call_group`) |
| [`godot-2d-movement`](.agents/skills/godot/godot-2d-movement/SKILL.md) | `CharacterBody2D` + `move_and_slide()`, склоны, coyote time |
| [`godot-tilemap`](.agents/skills/godot/godot-tilemap/SKILL.md) | `TileMapLayer`/`TileSet`: слои, terrain, collision/nav, клетки |
| [`godot-physics`](.agents/skills/godot/godot-physics/SKILL.md) | Тела (2D+3D), collision layers vs masks, raycasts |
| [`godot-ui-control`](.agents/skills/godot/godot-ui-control/SKILL.md) | `Control`: anchors, Containers, Theme, focus |
| [`godot-animation`](.agents/skills/godot/godot-animation/SKILL.md) | `AnimationPlayer`, `AnimationTree`, `Tween` |
| [`godot-shaders`](.agents/skills/godot/godot-shaders/SKILL.md) | Godot Shading Language: `canvas_item` + `spatial` |
| [`godot-3d-essentials`](.agents/skills/godot/godot-3d-essentials/SKILL.md) | Node3D, Camera3D, свет, WorldEnvironment, `GridMap` |
| [`godot-resources`](.agents/skills/godot/godot-resources/SKILL.md) | Custom `Resource` + `.tres`, `ResourceLoader`/`Saver` |
| [`godot-audio`](.agents/skills/godot/godot-audio/SKILL.md) | `AudioStreamPlayer`, bus'ы, эффекты, sync-to-beat |
| [`godot-multiplayer`](.agents/skills/godot/godot-multiplayer/SKILL.md) | ENet, `@rpc`, authority, `MultiplayerSpawner`/`Synchronizer` |
| [`godot-export`](.agents/skills/godot/godot-export/SKILL.md) | Export presets, headless CLI, web COOP/COEP |
| [`godot-csharp`](.agents/skills/godot/godot-csharp/SKILL.md) | C#/.NET: partial-классы, `[Export]`, `[Signal]`, interop |

### Disciplines

| Skill | Scope |
|-------|-------|
| [`create-game-assets`](.agents/skills/disciplines/create-game-assets/SKILL.md) | Арт-дирекция, спрайты/тайлсеты/текстуры, пайплайн ассетов |
| [`ai-behavior-trees-utility-ai`](.agents/skills/disciplines/ai-behavior-trees-utility-ai/SKILL.md) | Поведенческие деревья + Utility AI |
| [`game-ai`](.agents/skills/disciplines/game-ai/SKILL.md) | FSM, steering, A*/navmesh, выбор архитектуры ИИ |
| [`procedural-gen`](.agents/skills/disciplines/procedural-gen/SKILL.md) | Seed-генерация, шум, данжи, loot-таблицы |
| [`shader-programming`](.agents/skills/disciplines/shader-programming/SKILL.md) | Шейдеры: vertex→fragment, UV, эффекты (GLSL/HLSL) |
| [`audio-design`](.agents/skills/disciplines/audio-design/SKILL.md) | Микшер, ducking, адаптивная музыка, SFX-вариации |
| [`game-ui-ux`](.agents/skills/disciplines/game-ui-ux/SKILL.md) | Responsive UI, safe areas, фокус, HUD |
| [`performance-optimization`](.agents/skills/disciplines/performance-optimization/SKILL.md) | Профилирование, frame budget, draw calls, pooling, GC |
| [`game-feel`](.agents/skills/disciplines/game-feel/SKILL.md) | Juice: shake, hit-stop, squash & stretch |
| [`physics-tuning`](.agents/skills/disciplines/physics-tuning/SKILL.md) | Timestep, CCD, jitter, collision layers |
| [`camera-systems`](.agents/skills/disciplines/camera-systems/SKILL.md) | Follow-камера, 3D orbit, shake |
| [`dialogue-systems`](.agents/skills/disciplines/dialogue-systems/SKILL.md) | Ветвящиеся диалоги, Ink/Yarn |
| [`input-systems`](.agents/skills/disciplines/input-systems/SKILL.md) | Action mapping, rebinding, deadzone, buffering |
| [`level-design`](.agents/skills/disciplines/level-design/SKILL.md) | Блокаут, метрики, pacing, critical path |
| [`save-systems`](.agents/skills/disciplines/save-systems/SKILL.md) | Сериализация, слоты, versioning, autosave |

### Genres

| Skill | Scope |
|-------|-------|
| [`rpg`](.agents/skills/genres/rpg/SKILL.md) | Статы, инвентарь, квесты, диалоги, save/load, бой |
| [`roguelike`](.agents/skills/genres/roguelike/SKILL.md) | Грид, процедурные данжи, permadeath, FOV, loot |
| [`platformer`](.agents/skills/genres/platformer/SKILL.md) | Ран/джамп, буферизация, variable jump |
| [`fps-shooter`](.agents/skills/genres/fps-shooter/SKILL.md) | Move+look, hitscan/projectile, оружие, TTK |
| [`card-game`](.agents/skills/genres/card-game/SKILL.md) | Карты, deck/hand/discard, эффекты |
| [`puzzle`](.agents/skills/genres/puzzle/SKILL.md) | Grid-головоломки, match-3, undo |
| [`tower-defense`](.agents/skills/genres/tower-defense/SKILL.md) | Лейны, волны, башни, экономика |
| [`survival-crafting`](.agents/skills/genres/survival-crafting/SKILL.md) | Крафт, нужды, tech tree |
| [`visual-novel`](.agents/skills/genres/visual-novel/SKILL.md) | Скрипт, текст, сейвы, skip/auto |

### Workflows

| Skill | Scope |
|-------|-------|
| [`prototype-fast`](.agents/skills/workflows/prototype-fast/SKILL.md) | Прототип за час, greybox, keep/kill |
| [`game-jam`](.agents/skills/workflows/game-jam/SKILL.md) | Скоп к дедлайну, кат фич, сабмит |
| [`steam-publish`](.agents/skills/workflows/steam-publish/SKILL.md) | Steamworks/SteamPipe, depots, steamcmd |
| [`itch-publish`](.agents/skills/workflows/itch-publish/SKILL.md) | itch.io, butler push, каналы |

## 12. Журнал сессий

Хронология изменений. **Новое — сверху.**

### 24.09 — переработка UI таверны

- **Skills-first:** задача выполнена по `godot-ui-control`, `game-ui-ux`, `rpg`, `godot-gdscript`: контейнерная сетка и общая тема вместо ручного размещения, единое масштабирование, полноценный focus/input и сохранение RPG-логики найма.
- **`scripts/inn_panel.gd`:** фон `taverna.jpeg` 1024×1024 загружается без `Image.resize()`; весь UI равномерно центрируется под текущий viewport. Зона `RECRUIT_PANEL` построена `GridContainer` 2×7 (14 ячеек), кандидат — `PanelContainer` + `MarginContainer` + `VBoxContainer`, портрет — `TextureRect` с `STRETCH_KEEP_ASPECT_CENTERED`.
- **Найм:** вместо трёх строк показываются все 10 допустимых наборов из `CANDIDATES`; сохраняются золото, случайные HP/урон/цена, лимит `Game.party` 4 и создание `Mercenary`. После найма кандидат удаляется, золото пересчитывается, кнопки блокируются при нехватке средств или полном отряде.
- **UX:** добавлены панель рекрутера со случайными слухами, подсказка размера отряда, единый `Theme`, начальный фокус, явные соседи сетки, мышь/клавиатура/геймпад, `Esc` и восстановление прежнего фокуса.
- **Контроль:** headless-парсинг без `SCRIPT ERROR`; временный smoke: slots=14, hire_before=10, portraits=10, talk=true; после найма party=1, золото 200→142, hire_after=9, `result=true`. Известный безобидный хвост `1 resources still in use at exit`. Требуется ручная визуальная проверка 1280×800.

### 24.09 — Skill-First workflow и исправление UI кузницы

- **Правила агентов:** в разделы 3/5/10 добавлены обязательный Skill-First workflow, карта выбора skills, UI-чеклист, единое масштабирование фона, проверки `TextureRect`, focus и ручная визуальная проверка 1280×800. Задачи этого изменения прочитаны skills `godot-ui-control`, `game-ui-ux`, `godot-gdscript`.
- **Проблема:** предыдущая кузница заранее уменьшала фон 1024×1024 через `Image.resize()` до 768×768 и вручную позиционировала каждый слот, из-за чего иконки выглядели слишком мелкими относительно ячеек и интерфейс не соответствовал UI-правилам проекта.
- **`scripts/blacksmith_panel.gd`:** исходный `blacksmith.jpeg` теперь загружается без пересэмплирования; единый `Control` 1024×1024 равномерно масштабируется под видимую область и центрируется. Зоны результата и инвентаря построены `GridContainer`; ячейки — `PanelContainer` + `MarginContainer`, содержимое — `VBoxContainer`/`HBoxContainer`; иконки используют `EXPAND_IGNORE_SIZE` + `STRETCH_KEEP_ASPECT_CENTERED`.
- **Theme/focus:** стили слотов, счётчиков и состояний кнопок вынесены в общий `Theme`; добавлены начальный фокус, явные соседи для сетки мыши/клавиатуры/геймпада, `Esc`, восстановление прежнего фокуса и реакция на изменение размера окна.
- **Функциональность сохранена:** переплавка удаляет выбранный экипируемый предмет, создаёт слиток в OUTPUT, использует тот же маппинг материалов и звук.
- **Контроль:** headless `--import`; парсинг `--quit` без `SCRIPT ERROR`; временный smoke открыл реальную панель с 5 предметами: output=7, inventory=12, buttons=5, icons=5, `sizes_fit=true`; после «Плавить» output_icons=1, buttons_after=4, `result=true`. Требуется ручная визуальная проверка.

### 24.09 — спавн на gen_smart_01: здания городов, НПЦ (стражи/жители), Серые, деревья

- **Генератор (`tests/gen_smart_map.gd`), новые этапы 6–8 в `_generate`:** `_place_city_content` (здания + НПЦ) → `_place_objects` (деревья в `_obstacles`) → `_place_greys` (кластеры Серых). Результат — sidecar-ы `gen_smart_01.structures.json` (`{structures:[{x,y,type_id}]}`) и `gen_smart_01.npcs.json` (`{npcs:[{x,y,set,role,patrol,post,hp_max,damage}]}`), грузит `alm_map.gd:_load_sidecars`, спавнит `game._spawn_map_units`.
- **Города:** в каждый город — магазин, таверна, кузница (`blacksmith1|2` — только размещение, клик не обработан: механика «разбитая броня → переплавка» в фоллоу-апе), тренировочные, жильё и декор (колодец/костёр/мельница) по `ZONE_HOUSES`. Здания ставятся в кольцо d 2–4 вокруг площади через `_footprint_fits` (только дорога, не площадь/спавн/портал/посты).
- **НПЦ городов:** стражи (3–5, первые 2 — патруль по городу, остальные стоят на постах), капитан (`heroes/swordsman`, 120HP) и жители 4–10 (стоят, 30HP, не дерутся). НПЦ ставятся ДО зданий, здания обходят посты; `patrol_radius` 1 для стоящих / 4 для патрульных.
- **Серые:** `GRAY_ZONE` по зоне (count/hp/dmg/pool — только `palette=5`, чтоб `is_hostile`); 50/50 кластеры 2–4 особей у дорог (`_side_road_cell` от `_road_anchor`, ≥24 от спавна) и в лесу (`_forest_anchor`, ≥2 деревьев вокруг, ≥20 от спавна).
- **Деревья:** по биому (`TREE_GRASS/SOIL/SAND/MUD`), ID объектов из `alm_objects.json` в `_obstacles` (клетка непроходима), кластерный шум (~2.3%), клиренс от дороги 1 клетка, не в городах (≥6 от центра) и не у спавна/портала.
- **Runtime:** `game.gd:_spawn_map_units`/`_spawn_npc`/`_spawn_monster` пробрасывают `role/post/patrol/hp_max/damage`. `npc.gd`: поле `role` (citizen|guard), `post`, `is_patrol`, `damage`, `aggro_radius`; страж атакует Серых (взаимный бой через `Game.deal_damage`, `is_miss`, `unit_sound`; не уходит от города дальше 380px), героя не трогает; добавлены `get_attack/defense/absorption/protection_*`. `enemy.gd`: `_combat_target()` — приоритет игроку (в агро, в погоне до deaggro), иначе ближайший страж из `Game.npcs`; `_chase_move(delta, target)` — по цели, а не хардкод `player`.
- **Баг найден в поле:** пул стражи содержал `humans/pikeman` — такого набора в `units_db.json` нет (есть `humans/pikeman_`), 5 стражей не спавнились. Исправлено на `humans/pikeman_`.
- **Контроль:** парсинг `--quit` → `0 SCRIPT ERROR`; генератор: зданий=18, НПЦ=49 (стражи=15/патруль=6, жители=19), Серые=15, 15/13 (кластер может чуть перевыполнить target); `spawn_smoke.gd` — recs=49 missing-sets=[], НПЦ=34, «серый повреждён=true серый отвечает=true» → **RESULT: OK** (взаимный бой); рендер `missing_tiles=0`.
- **Ручная проверка пользователем:** «с большего хорошо» (24.09) → закоммичено и запушено.

### 24.09 — кузница (blacksmith), спрайты портала/спавна, реорганизация скриптов

- **Кузница (`scripts/blacksmith_panel.gd`):** новый класс `BlacksmithPanel extends CanvasLayer`. Фон `blacksmith.jpeg` (1024×1024) уменьшен до 768×768 через `Image.resize()` + `ImageTexture.create_from_image()`, отцентрирован в 1280×800 (offset 256, 16). Зоны из README: `BLACKSMITH_OUTPUT` (7×1 слева), `PLAYER_INVENTORY` (2×6 снизу). Логика: клик «Плавить» → предмет из инвентаря → слиток в OUTPUT. Маппинг материалов: Iron→iron, Bronze→bronze, Steel→steel, Silver→argentum и т.д. (15 маппингов). Fallback: если `*_ingot.png` не найден → `*_weapon.png`.
- **Подключение:** `game.gd:_structure_kind()` — добавлена проверка `folder.contains("blacksmith")` → `"blacksmith"`. `game.gd:_building_click()` + `_process_pending_building()` — case `"blacksmith"` → `ui.open_blacksmith()`. `ui.gd` — `_blacksmith` переменная, `open_blacksmith()`, обновлены `_on_panel_closed()` и `is_editor_open()`.
- **Спрайты портала/спавна:** скопированы из `import/portal/` и `import/spawn/` в `assets/sprites/portal/` и `assets/sprites/spawn/` (по 5 PNG: 4 кадра + spritesheet). `portal_marker.gd` — добавлена проверка `ResourceLoader.exists()` перед `load()` (убирает ошибки при отсутствии файлов).
- **Реорганизация:** скрипты генерации иконок/разметки (`markup_barracks.py`, `markup_blacksmith.py`, `recolor_*.py`, `split_herbs.py`, `generate_potion_icons.py`) перенесены из корня в `tests/`. Добавлены новые: `tests/markup_shop.py`, `tests/generate_loot_icons.py`, `tests/remap_inventory.py`, `tests/remodel_weapon.py`.
- **План (следующие шаги):**
  1. Таверна (обновление `inn_panel.gd`) — фон `taverna.jpeg`, зона `RECRUIT_PANEL` (7×2)
  2. Магазин (обновление `shop_panel.gd`) — фон `shop_human.jpeg`, зоны из README
  3. Травничество — добавить 8 трав в `item_db.json`, система сбора/крафта
  4. Loot icons — обновить `_make_loot()` в `enemy.gd`, использовать `{material}_weapon/armor.png`
- **Контроль:** `--quit` → 0 SCRIPT ERROR. Кузница работает: переплавка оружия → слитки из `assets/professions/blacksmith/`.

### 24.09 — «бегает по воде» на gen_smart_01 (клик в озеро)

- **Симптом:** на gen_smart_01 герой реально пересекает озеро (консоль `DEBUG: герой в непроходимой клетке (58,47) file=3` и далее по ходу движения). Данные подтверждены headless-дампом: вода (file3) — блок (WalkTable cost 0), дебаг-клетки — честная вода, ряды в пределах BMP-листов.
- **Истинная причина (найдена трассировкой `_move_checked`/`fuzz_water.gd`):** клик вглубь озера → `find_path` возвращал `[]` → `move_to_target` шёл в прямую трассировку к цели в воде. Гейт `_can_move_to` считает разрешённым шаг **внутри** непроходимой клетки (исключение `nxt == cur` — для «выхода из дерева»), а `move_and_slide` на кадре срабатывания гейта всё равно проезжает ~2px по текущей инерции `velocity` → нога «проваливается» за берег. Дальше герой в водной клетке движется на полной скорости (гейт доволен: `nxt == cur`), на каждой границе — снова провал → ходьба через всё озеро к цели. Раньше описано как «бег на месте» — это было неверно.
- **Фикс 1 (player.gd `move_to_target`, прямая трассировка):** если пути нет (`find_path` = `[]`) и цель непроходима → `state="idle"` у кромки, а не марш в воду. Прямая трассировка остаётся только для ПРОХОДИМОЙ цели (доводка).
- **Фикс 2 (alm_map.gd `find_path`):** при непроходимой цели и всех 4 непроходимых соседях — спираль `_nearest_walkable(goal, 24)` → герой идёт к ближайшей суше (обход озера по берегу). Ранее 12; оставлено 24 для крупных озёр.
- **Верификация:** `tests/fuzz_water.gd` — 8 кликов (в т.ч. в центр озера), герой никогда не попадает в воду: **0 hits** (до фикса — 6, с `HIT cell=(58,48)` и движениями по воде). `--quit` → 0 SCRIPT ERROR.
- **Debug (временный, удалить после ручной проверки):** player.gd `_dbg_walk_t` — печать `DEBUG: герой в непроходимой клетке` раз в 0.5 с в движении.
- **Ручная проверка:** клик в озеро — герой обходит по берегу и останавливается; консоль без «DEBUG…». Пользователь подтвердил (24.09), debug-код удалён, закоммичено.

### 23.09 (вечер) — движение/удар: панель-клики, physics interpolation, импакт

- **Баг «вниз не идёт»:** `BottomPanel` (x 0–720, y 625–800) перехватывал клики — геометрически любые клики внизу экрана считались «по UI» и не двигали героя. **Фикс:** `main.tscn` → `mouse_filter = 2` (IGNORE); `ui.gd:_control_contains` — узлы с IGNORE не блокируют сами, но их дети-кнопки по-прежнему блокируются.
- **Physics interpolation** (высокий refresh ступал по 60 Гц физике): `project.godot` → `physics/common/physics_interpolation=true`. После телепортов/спавна — `reset_physics_interpolation()` (спавн, портал, выход из здания, `_teleport_to`), чтобы не было «streaking». Снаряды — `Node2D`, интерполяция их не трогает.
- **Звук/урон раньше анимации:** урон и звук срабатывали на кадре 0 замаха. Теперь — «кадр удара» через `UnitDB.attack_delay(набор)` (из units.txt): герой (player), враги (enemy), наёмники (mercenary) хранят `_impact_timer`/`_pending_*` и применяют урон+звук в момент удара. Анимация атаки — `speed_scale=1.0` (стабильный каденс).
- **Мах по трупу:** `attack_enemy` прекращает бить мёртвую цель (нет в `Game.enemies`) → `state="idle"`; `enemy.take_damage` игнорирует труп/разложение (нет повторного лута); враг не сбрасывает замах при получении урона в состоянии `attack` (не прерывается на каждый хит).
- **Каденс шагов:** `_anim.speed_scale` считается от КОМАНДНОЙ скорости (`_height_speed_factor`), а не мгновенной `velocity` — ровные шаги на разгоне/торможении.
- **Контроль:** `--quit` → 0 SCRIPT ERROR; smoke `main.tscn` без SCRIPT ERROR/инвалидов (только отсутствующие PNG-кадры портала/спавна — предсуществующее). Ручная проверка — 24.09, закоммичено.

### 23.09 — починка «редактор → игра» (F9 грузил Kids3.alm)

- **Баг:** при «Назад в игру (F9)» всегда грузилась захардкоженная `Kids3.alm` — правая карта из редактора не приезжала. Причины: (1) `main.tscn` жёстко зашивал `alm_path`; (2) `_remember_last_alm` писал `user://last_alm_path.txt`, но никто его не читал; (3) клавиша F9 в редакторе не была обработана (только надпись на кнопке).
- **Фикс:** `alm_map.gd:_ready` первым делом читает `user://last_alm_path.txt` и, если карта валидна, грузит её (`AlmMap: загрузка карты из редактора: ...`); fallback — экспортированный `alm_path`. В `map_editor.gd:_unhandled_input` добавлен `KEY_F9` → `_on_back()`.
- **Контроль:** `--quit` → `0 SCRIPT ERROR`; headless `main.tscn` → `AlmMap: загрузка карты из редактора: gen_smart_01.alm` (128×128).

### 23.09 (середина ночи) — города + MST-дороги + горы/вода поверх (§13)

- `_generate` разбит на этапы: `_place_terrain` (только база 0/4/5/6, без гор/воды/дороги) → `_place_cities` → `_connect_cities` → `_place_mountains_water` → `_place_portal_spawn` → тайлы → высоты.
- `_place_cities`: овалы дорогой ≈11×11 (type 3) по профилю зоны (`ZONE`: start 1 / mid 1–3 / hard 4–5 / faction 2–3), центры на базовой земле, мин. разнос 20 клеток. Городам — метки фракций.
- `_connect_cities`: MST (Прим, ближайший сосед) + A*-коридоры ширины 2. Дорога теперь **дважды связна городами**: `ROAD: cells=365 comps=[365]` (было 1 коридор на края).
- `_place_mountains_water`: горы/вода по `_field` и порогам `_water_thr`/`_mountain_thr`, клетки дороги (3) не перетираются.
- `_place_portal_spawn`: спавн у города №0, портал на противоположном краю (уже на суше).
- Удалён мёртвый код: `_place_roads`, `_carve_road`, `_largest_land`, `_anchor_in`, `_to_land`, `_detect_active_types`.
- Контроль: парсинг `--quit` → `0 SCRIPT ERROR`; проверила связность дороги и спавн; рендер `missing_tiles=0`.
- Исправлена таблица §8.4 (привязка типов к tile-файлам совпала с `TERRAIN_FILE`).

### 23.09 (ночь) — Voronoi-биомы, псевдо-высоты, portal/spawn

- Voronoi-биомы в `_place_terrain`: связные регионы (grass 28%, mountain 13%, water 8%, road 5%, soil 12%, sand 19%, mud 3%) вместо полос шума.
- Песок/грязь: interior rules из transition_db, BMP tile5/6/7 скопированы из tile1; `_spec_for_type` перезаписывает file через `TERRAIN_FILE` для типов ≥4.
- Псевдо-высоты `_pick_height` (диапазоны по биому), `_field`/`_water_thr`/`_mountain_thr` — class variables.
- Portal + Spawn: `portal_marker.gd` (Sprite2D, 4 кадра), sidecar JSON, `alm_map.gd` загружает, `game.gd` телепортирует.
- Коммит `4c3f0983` (60 файлов, +968).

### 23.09 (вечер) — дороги-коридоры, извилистый берег

- Дорога раньше: шумовые пятна (6 компонентов, ширина 1). Теперь: **один связный A*-коридор** шириной 2 по суше (трава 10 / горы 18 / штраф поворот 6 / шум / +3 у воды). `ROAD: cells≈690 comps=[690]`, water-adj ~11%.
- Берег: shape-основанная кромка, компактность травы **1.80** (ориг 1.5–1.8), уникальных масок кромки **109**. Рендер `missing_tiles=0`, `--quit` → `0 SCRIPT ERROR`.

### 23.09 (день) — shape-based генератор и visual-фиксы

- `analyze_shapes.gd` → `shapes_db.json` (603 формы, interior для 0–3).
- `gen_smart_map.gd`: `_pick_tile` — exact → hybrid → Хэмминг → rules-fallback.
- Край травы/гор = row 4 на границах (100% кромки, было 44%).
- Интерьер без «чанков» через двухчастотный FastNoiseLite.

### 22.09 — transition_editor: tile5/6/7

- Плейсхолдеры tile5/6/7 (PNG 32×32 + BMP 24-бит bottom-up, после генерации `--import`).
- transition_db: **336 правил** + interior; диагонали наследуются; импорт сканирует `assets/maps/pvm/`.
- Рендер: `vmax_by_file` включает 5/6/7; `_load_tile_region` кламп 0..7 (было 0..4).
- `test_transitions` → OK; `test_import_smoke` → OK (410974 клеток, 96 ключей).

### 21.09 (вечер+ночь) — система terrain 7+2 и редактор переходов

- Terrain 0–6 + объекты 7/спавн 8; `transition_editor.gd` (сетка 3×3, interior, импорт из .alm).
- `transition_db.json` — 96 правил для 0–3 + дефолты 4–6; ключ `типA:направление:типB`.
- `under_tiles` в `custom_map.gd` — упаковка `тип*256+tex_idx`, восстановление при ластике.

### 20.09 — анализ .alm и первый генератор

- Полный разбор формата `.alm` (см. §8.3), структуры BMP, профили биомов (8 карт), правила переходов (row 4, таблица ребер).
- `gen_alm_map.gd` — рабочий writer .alm, открывается в редакторе карт и в игре.
- Удалены дубли: `scripts/tile_directions.gd`, `assets/maps/tile_directions.json`, `assets/maps/transition_rules.json`.

### 19.09 — единая точка урона `Game` + маг-тактика (П0–П2)

- Всё через `Game.deal_damage(...)`: герой (ближний + мгновенная магия), враги, наёмники, снаряды, AoE. Математика боя — один раз в `game.gd` (см. §6).
- Посох мага бьёт как сфера (`"magic"` + sphere, опыт сфере); UI мага — панель сфер (`ui.gd`); стартовый набор мага: посох + книга.
- Призванные миньоны (Light/Summon): визуальная вспышка / `monsters/orc` 60hp на 45 с в `Game.party`.
- `debug_magic = false` (маг стартует не со всеми 24 заклинаниями).
- Починена CJK-порча в `enemy.gd`/`game.gd` (метка «люди» в `return` ломала `take_damage` и парсинг) — всё снова парсится.

### 18.09 — Слой мира (Слой-2), симулятор жив

- `world_state.gd`: типизированный `journal`, `_id()` через `if/elif`.
- `world_bus.gd:reseed()`: `:=` → `: Dictionary` в невыводимых местах.
- `world_sim.gd`: явные типы `var d: float`.
- Контроль: `--headless --quit` → `0 SCRIPT ERROR`; симулятор: `RESULT: world survived 100 days. day=100, threat=1.00, journal=208`.

## 13. Дорожная карта

### Генерация карт — новый пайплайн (в работе: этап `_place_terrain`→`_place_cities`→`_connect_cities`→`_place_mountains_water`→`_place_city_content`→`_place_objects`→`_place_greys` готов и проверен)

- **Порядок:** (1) почва Voronoi без гор/воды → (2) города (овалы ~11×11 из дорог) → (3) дороги MST + A* → (4) горы/вода Voronoi поверх (не перетирая type 3) → (5) portal/spawn → (6) здания + НПЦ городов → (7) деревья/объекты → (8) Серые → (9) тайлы → (10) высоты.
- **Параметры:** городов 1–5 (от сложности), oval ~11×11, MST (ближайший сосед), горы/вода защищают дороги.
- **Файл:** `tests/gen_smart_map.gd` — этапы + sidecar-ы `structures/npcs` (24.09).
- **Осталось:** шумные профили городов, арт городов, механика кузницы (переплавка разбитой брони), фракции городов по зонам.

### Мир и фракции (дальний план)

- SIM-эмуляция для территорий вне карты героя, «!»-маркеры на миникарте.
- Таверны/наёмники по репутации, тиры магазинов.
- Threat-система: финальный выбор между Растворение/Цикл/Шёпот.