# Рекомендации по результатам аудита — план исправлений

> Документ: `Allodshome/docs/audit/02-recommendations.md`
> Связь: находки нумерованы по [`01-audit-report.md`](01-audit-report.md).
> Формат каждой рекомендации: **Проблема → Решение → Файлы → Проверка**.
> Порядок исполнения строго по приоритетам: P0 закрывает блокеры, P1 — логические ошибки, P2 — техдолг. Задачи P0/P1 по одной на запрос (AGENTS §9.1).

---

## P0 — закрыть блокеры (порядок важен)

### R-P0-1. Выключить тест-режим магии по умолчанию
**Проблема:** `Game.debug_magic = true` открывает всю магию, убирает ману/кулдауны (01-§3.1).
**Решение:**
1. `debug_magic` сделать читаемым из `ProjectSettings` (`settings/debug/magic`, default `false`), а не статической константой:
   ```gdscript
   static var debug_magic: bool = ProjectSettings.get_setting("settings/debug/magic", false)
   ```
2. Для разработки добавить запуск с аргументом: `-- --debug-magic` (обработать в `_ready` через `OS.get_cmdline_user_args()`).
3. Убрать раздачу всех заклинаний/сфер из `_grant_starter_set()` (оставить под флагом).
4. Обновить `magic_smoke` и `spell_*_smoke`: они должны **явно включать** флаг в тесте, а не полагаться на глобальное `true`.
**Файлы:** [`game.gd`](../../scripts/game.gd:35), [`player.gd`](../../scripts/player.gd:261), [`player.gd`](../../scripts/player.gd:978), `project.godot`, `tests/magic_smoke.gd`.
**Проверка:** headless-парсинг без SCRIPT ERROR; вручную: маг на старте имеет 1 книгу/1 заклинание и тратит ману; тесты зелёные с явным флагом.

### R-P0-2. Принять решение по порталу и связать зоны
**Проблема:** портал телепортирует на спавн; зоны Z1–Z4 не соединены (01-§3.2).
**Решение (минимальное):** превратить портал в **переход между зонами**:
1. В sidecar `.portal.json` добавить `target_zone` (или генерировать по правилу: следующая зона по цепочке start→mid→hard→faction).
2. `_on_portal_enter()`: `Game.request_map_by_seed(новый_сид, следующая_зона)` + пересборка сцены; сохранить автосейв перед переходом.
3. В `character_select` дать выбор стартовой зоны (или первый проход стартует в `start`).
**Файлы:** [`game.gd`](../../scripts/game.gd:1208), [`map_generator.gd`](../../scripts/world/map_generator.gd:464), [`character_select.gd`](../../scripts/character_select.gd), `tests/map_seed_integration.gd`.
**Проверка:** smoke-тест «портал меняет зону»; ручная: герой заходит в портал → новая карта другой зоны, сид сохранён.

### R-P0-3. Починить контракт данных WorldState ↔ WorldSim
**Проблема:** армии без `power` воюют вечно; экономика города вложена, а читается плоско; `felt()` — no-op (01-§3.3).
**Решение:**
1. **Единый источник правды для схемы**: завести `WORLD_SCHEMA.md` (или JSON-схему) с полями сущностей — армия обязана иметь `power`, город — плоские `gold/food/prod` (или SIM читает `economy.*` — выбрать одно и сделать везде).
2. `new_army()`: вычислять `power` из `unit_ids` (сумма attack/max_hp юнитов) при создании и при изменении состава.
3. `TickSettlements()`: читать `economy.gold/food/prod` из одной ветки (например, `var eco = c["economy"]; food += eco.prod - pop*0.15`).
4. `felt()` — удалить или сделать осмысленной (например, штраф продуктивности при голоде).
5. `reseed()` — либо подключить к генератору реальных фракций из `units_db.json`, либо вынести фикстуру в отдельный `world_fixture()` для тестов и держать `reseed()` игровым.
**Файлы:** [`world_state.gd`](../../scripts/world/world_state.gd:87), [`world_sim.gd`](../../scripts/world/world_sim.gd:93), [`world_sim.gd`](../../scripts/world/world_sim.gd:119), [`world_bus.gd`](../../scripts/world/world_bus.gd:26), `tests/save_smoke.gd`, `tests/test_simulation.gd`.
**Проверка:** `sim_runner` даёт осмысленный исход: армии сражаются и одна гибнет; город накапливает ресурсы; `save_smoke` round-trip зелёный.

### R-P0-4. Восстанавливать позицию героя при загрузке (или убрать поле)
**Проблема:** `hero.position` пишется, но не читается (01-§3.4).
**Решение:** в `apply_payload()` после применения героя восстановить позицию через `AlmMap.is_walkable_world` с откатом на спавн при непроходимости (спираль `_nearest_walkable` уже есть в alm_map). Если сознательно «всегда со спавна» — удалить поле из `build_payload` и из схемы v1.
**Файлы:** [`save_system.gd`](../../scripts/save_system.gd:249), [`save_system.gd`](../../scripts/save_system.gd:290), `tests/save_smoke.gd`.
**Проверка:** сохраниться в точке X, загрузиться — герой в X (или ближайшей проходимой клетке).

### R-P0-5. Реализовать или честно отключить `damage_area()`
**Проблема:** AoE не разрушает объекты карты (01-§3.5).
**Решение (выбор за игроком):**
- *Вариант A (минимум):* убрать вызов `alm_map.damage_area()` из `player._damage_area_at` и пометить разрушаемость объектов как незаявленную фичу (обновить README/AGENTS).
- *Вариант B (полноценно):* разрушаемые объекты — `_obstacles` с HP в `alm_objects.json` (добавить поле `hp`), урон по радиусу списывает HP, при 0 — снять объект (очистить `_obstacles`, перестроить меш препятствий). Это же даст «Серые ломают деревья/город» в будущем.
**Файлы:** [`alm_map.gd`](../../scripts/alm_map.gd:915), [`player.gd`](../../scripts/player.gd:1469), `tests/spell_mechanics_smoke.gd`.
**Проверка (B):** огненный шар по дереву → дерево исчезает, клетка становится проходимой; smoke-тест на разрушение.

### R-P0-6. Привести `project.godot` в порядок
**Проблема:** повреждённый заголовок с BOM/дублями (01-§3.6).
**Решение:** руками (или скриптом) переписать первые строки в канонический вид:
```
; Engine configuration file.
...
config_version=5
```
Затем открыть проект в редакторе и сохранить один раз. ⚠️ Approval gate: изменение `project.godot` — по AGENTS §9.4 требуется согласование.
**Файлы:** [`project.godot`](../../project.godot:9).
**Проверка:** `godot --headless --path . --quit` без ошибок; git diff только первых строк.

---

## P1 — значимые исправления

### R-P1-1. Починить рельеф наёмников и миньонов
**Проблема:** `mercenary._apply_relief_stand()` берёт карту из `Game.hero` (01-§4.1).
**Решение:** заменить источник на `get_tree().get_first_node_in_group("alm_map")`, как в [`npc.gd`](../../scripts/npc.gd:38) и [`enemy.gd`](../../scripts/enemy.gd:167). Добавить health_bar в эту же функцию (у мерков бар смещён? — проверить и поправить).
**Файлы:** [`mercenary.gd`](../../scripts/mercenary.gd:204).
**Проверка:** нанять мерка, подойти к холму — спрайт поднят на высоту; визуально и smoke-тестом высоты.

### R-P1-2. Ставить `ZONE_HOUSES` домов, а не один
**Проблема:** `range(mini(houses_n, 1))` (01-§4.2).
**Решение:** `for i in range(houses_n)`. Прогнать `gen_seeds_smoke` и `city_layout_smoke` — количество зданий изменится; при необходимости поднять лимиты попыток в `_place_city_building`.
**Файлы:** [`map_generator.gd`](../../scripts/world/map_generator.gd:556).
**Проверка:** генерация без `CITY_CONTENT: missing`; в городе >1 жилого дома; `gen_seeds_smoke` OK.

### R-P1-3. Инвентарь: одна ячейка на ключ предмета
**Проблема:** дубликаты рисуются отдельными ячейками (01-§4.3).
**Решение:** итерировать уникальные ключи (`counts.keys()`), ячейку дополнять счётчиком стака; клик «использовать/надеть» работает с ключом, как сейчас.
**Файлы:** [`inventory_panel.gd`](../../scripts/inventory_panel.gd:370).
**Проверка:** `inventory_ui_smoke` обновить под уникальные ячейки; визуально: 3 зелья = 1 ячейка «×3».

### R-P1-4. Эффекты зелий — в данные
**Проблема:** лечение по подстроке имени (01-§4.4).
**Решение:** в `item_db.json` у Potion добавить `{ "heal": 30, "mana": 0 }` (генератор `tests/gen_potion_fields.py`); `_on_item_clicked` читает поля, fallback — ноль с `push_warning` для неизвестных.
**Файлы:** `assets/items/item_db.json`, [`inventory_panel.gd`](../../scripts/inventory_panel.gd:472).
**Проверка:** smoke: зелья лечат по данным, неизвестное зелье не исчезает молча.

### R-P1-5. Перенести ввод на Input Map
**Проблема:** сырые keycodes вместо actions (01-§4.5).
**Решение:** добавить actions (`ui_inventory`, `ui_spells`, `toggle_pause`, `quick_cast_1..9`, `cancel_target`, `restart`, `move_click`), читать через `Input.is_action_*`/`event.is_action_pressed`. ⚠️ Approval gate: изменение input map — согласовать.
**Файлы:** `project.godot`, [`game.gd`](../../scripts/game.gd:640).
**Проверка:** все горячие клавиши работают как раньше (smoke по _input заменяется unit-проверкой action-ов).

### R-P1-6. Команды отряда — наёмникам
**Проблема:** follow/attack/guard двигают только героя (01-§4.6).
**Решение (этап 1):** `Game.action_mode` читать в `mercenary._physics_process`: при `attack` — целевой выбор из врагов в радиусе (как сейчас), при `guard` — не отходить дальше N px от героя, при `follow` — держаться за героем; `stop` — стоять. Формации/стойки — в vision (03).
**Файлы:** [`mercenary.gd`](../../scripts/mercenary.gd:34), [`game.gd`](../../scripts/game.gd:1216).
**Проверка:** smoke: после «Атак.» наёмник атакует ближайшего врага; после «Стоп» стоит.

### R-P1-7. Убрать магические числа боя
**Проблема:** `attack_cooldown = 1.0`, граница стражи 380 (01-§4.7).
**Решение:** константы в одном месте: `Game.ATTACK_COOLDOWN` уже есть — использовать; `GUARD_MAX_LEASH` — константа `Npc` (или в `units_db` поле `guard_leash`).
**Файлы:** [`enemy.gd`](../../scripts/enemy.gd:125), [`npc.gd`](../../scripts/npc.gd:160), [`mercenary.gd`](../../scripts/mercenary.gd:147).
**Проверка:** парсинг + `equipment_combat_smoke`/`spawn_smoke` зелёные.

### R-P1-8. Очистить `_SMELTABLE` от серебра и синхронизировать с данными
**Проблема:** мёртвый `"Silver"` (01-§4.8).
**Решение:** проверить наличие `Silver Ingot` в БД; если нет — убрать `"Silver"` из `_SMELTABLE`, добавить инвариант в `material_migration_smoke`: «каждый металл в _SMELTABLE имеет слиток в item_db».
**Файлы:** [`item_db.gd`](../../scripts/item_db.gd:181), `tests/material_migration_smoke.gd`.
**Проверка:** `blacksmith_smoke` + новый инвариант зелёные.

### R-P1-9. Сохранять hotbar
**Проблема:** назначения 1..9 теряются после загрузки (01-§4.9).
**Решение:** добавить `"hotbar": Game.hotbar.duplicate(true)` в `build_payload` и восстановление в `apply_payload` (версия схемы — bump до 2 с миграцией v1→v2, поле опционально).
**Файлы:** [`save_system.gd`](../../scripts/save_system.gd:231).
**Проверка:** `save_smoke`: назначил → сохранил → загрузил → хотбар на месте.

### R-P1-10. Кэш пула дропа
**Проблема:** `_random_gear()` фильтрует 491 предмет на каждый труп (01-§4.10).
**Решение:** статический кэш `ItemDB.price_pool(budget)` — отсортированный список по цене + бинарный поиск верхней границы, случайный выбор из подмножества.
**Файлы:** [`enemy.gd`](../../scripts/enemy.gd:379), [`item_db.gd`](../../scripts/item_db.gd).
**Проверка:** `equipment_combat_smoke` зелёный; бенчмарк дропа 1000 раз.

### R-P1-11. Единый ховер-детектор цели
**Проблема:** два обхода юнитов на кадр (01-§4.11).
**Решение:** один `Game.unit_at_point(pos) -> Node2D` (для click/hover/tooltip), кэшировать цель на кадр в `ui` (`_hover_target_cache` + invalidate по позиции мыши), чтобы `_hover_portrait` и `_world_hover_target` не дублировали работу.
**Файлы:** [`ui.gd`](../../scripts/ui.gd:711), [`ui.gd`](../../scripts/ui.gd:802), [`game.gd`](../../scripts/game.gd:948).
**Проверка:** `hover_tooltip_smoke` зелёный; производительность — профилировщик.

---

## P2 — техдолг и полировка

### R-P2-1. Вычистить мёртвый код
Удалить (по одному коммиту): `player._create_lightning_effect`, `unit_db._unused`, `ui.cast_ability` (pass), поля крита в SpellDB (или реализовать крит — см. 03), `alm_map._add_vert`. После каждого удаления — парсинг + релевантные smoke.
**Файлы:** [`player.gd`](../../scripts/player.gd:1540), [`unit_db.gd`](../../scripts/unit_db.gd:214), [`ui.gd`](../../scripts/ui.gd:1332), [`spell_db.gd`](../../scripts/spell_db.gd:102), [`alm_map.gd`](../../scripts/alm_map.gd:557).

### R-P2-2. Вынести hover-карточки в UiKit
`_item_card_lines` + `_attach_item_card/_attach_slot_card` перенести в `UiKit.make_item_card_lines(item)` / `UiKit.attach_card(cell, item, bounds)`. Проверить, что панели не изменили вид (smoke-тесты UI).
**Файлы:** [`ui.gd`](../../scripts/ui.gd:583), [`inventory_panel.gd`](../../scripts/inventory_panel.gd:516), [`ui_kit.gd`](../../scripts/ui_kit.gd).

### R-P2-3. Кэш списка юнитов и spatial hash для separation
Ввести `Game.units_cache` (герой+враги+НПЦ+отряд), обновляемый при спавне/смерти; `movement_direction()` ограничить поиском в радиусе 24 px через spatial hash или минимум — проверкой расстояния после сортировки. `tick_shields`/`StatusEffects.tick` использовать кэш.
**Файлы:** [`game.gd`](../../scripts/game.gd:210), [`game.gd`](../../scripts/game.gd:253), [`status_effects.gd`](../../scripts/status_effects.gd:249).
**Проверка:** профилировщик: кадр с 60 юнитами без просадок; `fuzz_edge`/`runtime_errors_smoke` зелёные.

### R-P2-4. Единый pathfinding: A* с нормальной очередью
Заменить BFS `find_path` на A* (эвристика Manhattan, соседи 8 с диагональной проверкой — сохранить), очередь — `Array` с линейным минимумом заменить на двоичную кучу или, минимально, на `PriorityQueue`-подобную реализацию с `sort` по вставке. Покрыть инвариантами из `fuzz_edge`/`fuzz_water`.
**Файлы:** [`alm_map.gd`](../../scripts/alm_map.gd:825).
**Проверка:** те же пути, что и BFS (сравнить на 20 случайных парах), скорость выше на 256×256.

### R-P2-5. Переменный размер карты
`W/H` из параметров `generate(seed, zone, dir, size)`; профиль зоны задаёт размер (start 96, mid 128, hard 160, faction 192 — предложение); все внутренние циклы уже параметризованы (`W*H`, `range(H)`), кроме констант `W/H` в сигнатурах. Атлас/рендер приспособить.
**Файлы:** [`map_generator.gd`](../../scripts/world/map_generator.gd:18).
**Проверка:** `gen_seeds_smoke` + новый тест разных размеров.

### R-P2-6. Заменить `hash(Vector2i)` на стабильный
Во всех местах генератора использовать формулу `abs(t*73856093 ^ x*19349663 ^ y*83492791)` (как уже в `_interior_tile`) — убрать зависимость от движка.
**Файлы:** [`map_generator.gd`](../../scripts/world/map_generator.gd:1141), [`map_generator.gd`](../../scripts/world/map_generator.gd:1237).
**Проверка:** байтовая регрессия `seed=4242` — совпадение с эталоном (или пересчёт эталона разово, с записью в журнал).

### R-P2-7. Миникарта: слои вместо попиксельной перерисовки
Рендер terrain в `Image` один раз (при загрузке карты), затем поверх — точки юнитов (крошечный слой, обновление 4 Гц). Для будущих больших карт — LOD-шаг.
**Файлы:** [`ui.gd`](../../scripts/ui.gd:963).
**Проверка:** `lighting_smoke`/UI-тесты зелёные; визуально миникарта не отличается.

### R-P2-8. Обновить документацию
- README: рендерер Forward+ (+ hdr_2d), `MapGenerator` как ядро, актуальный раздел «Что реализовано», дорожная карта.
- HOW_TO_RUN.txt: актуальный путь, старт с `character_select.tscn`, текущее управление.
- AGENTS.md: журнал сессий — запись об аудите.
**Файлы:** [`README.md`](../../README.md), [`HOW_TO_RUN.txt`](../../HOW_TO_RUN.txt), [`AGENTS.md`](../../AGENTS.md).

### R-P2-9. Решить судьбу `assets/loot_icons/`
Или подключить (`loot_bag` рисует меш кодом — заменить спрайтом), или пометить в README как архив и удалить из рабочего дерева. Починить Linux-пути в `tests/recolor_*.py`/`generate_*_icons.py` или удалить нерабочие генераторы.
**Файлы:** `assets/loot_icons/`, `tests/generate_loot_icons.py`, `tests/recolor_*.py`.

### R-P2-10. Панели интерьера — декомпозиция на контейнеры (поэтапно)
Не рефакторить разом; при каждой следующей правке панели переводить блок на контейнеры с проверкой `*_ui_smoke` (уже заведены: `shop_ui_smoke`, `inn_ui_smoke`, `inventory_ui_smoke`).
**Файлы:** [`inventory_panel.gd`](../../scripts/inventory_panel.gd:97) и др.

---

## Контроль после каждого шага (AGENTS §3)

1. `godot --headless --path . --quit` — без `SCRIPT ERROR`.
2. `godot --headless --path . --script res://tests/runtime_errors_smoke.gd` — без рантайм-ошибок.
3. Релевантные smoke-тесты (список в [`AGENTS.md`](../../AGENTS.md:235)).
4. Ручная визуальная проверка 1280×800, где затронут UI.
5. Коммит — только после ручной проверки игроком (AGENTS §9.3).

---

## Сводная таблица задач

| # | Задача | Severity | Файлы | Зависит от |
|---|---|---|---|---|
| R-P0-1 | debug_magic → настройка | P0 | game.gd, player.gd, project.godot | — |
| R-P0-2 | Портал между зонами | P0 | game.gd, map_generator, character_select | — |
| R-P0-3 | Контракт WorldState↔WorldSim | P0 | world_* | — |
| R-P0-4 | Позиция героя в save | P0 | save_system | — |
| R-P0-5 | damage_area | P0 | alm_map, player | решение игрока A/B |
| R-P0-6 | project.godot | P0 | project.godot | approval gate |
| R-P1-1..11 | См. раздел P1 | P1 | — | частично P0 |
| R-P2-1..10 | См. раздел P2 | P2 | — | — |

*Приоритеты могут пересматриваться; главное правило — по одной задаче на запрос и без смешивания несвязанных изменений (AGENTS §9.1).*