# TDD: Великий маг (пакет 3.0)

Вход: `docs/lore/gdd_archmage.md`. Роль: `architect`.

## 1. Допущения

1. **Раса героя = фракция его мага.** Подтверждено замером: `RACES` в
   `character_select.gd:10-15` = `human/necro/druid/ork`, и это ровно 4 фракции
   лора. Совпадение не случайно, на нём строится выбор стартового города.
2. **`Game.hero_race` уже существует** (`AGENTS.md` §12, миграция портретов) —
   нового поля не нужно.
3. **Город не «ищется по названию», а определяется фракцией.** Имя города —
   только текст в UI.
4. **`archmage` хранится в `factions[fid]`,** а не отдельным словарём в мире:
   `to_dict()` сериализует `factions` целиком (`world_state.gd:128`), поэтому
   поле уедет в сейв без изменения схемы и без миграции.
5. **Маг — не юнит.** Он не в `units`, не участвует в бою, не спавнится
   генератором. Это NPC без тела боя. Так проще и не ломает `UnitDB`.

## 2. Система целиком

Источник данных `WorldState.factions[fid]["archmage"]`, который тикает по
реальному времени. UI читает его и пишет в него по кнопке «Сдать». Панель
открывается кликом по магу в центре города. Никаких новых классов, кроме
одного скрипта загрузки лора и одной панели.

## 3. Компоненты

| Файл:строка | Что меняется | Зачем |
|---|---|---|
| `assets/config/game.cfg` + `scripts/game_config.gd:29-207` | новая секция `[archmage]`: `sim_interval`, `decay_base`, `decay_threat`, `stake_ingot`, `stake_gold`, `stake_potion`, `power_start`, `tier_1/2/3`, `gold_per_stake` | числа в конфиге, не в коде (§12) |
| `scripts/lore.gd` (**новый**, `class_name Lore`) | ленивая загрузка `assets/lore/world.json` + `npcs.json` | имена не дублируются в коде |
| `scripts/world/world_state.gd:82-85` | `new_faction()` создаёт `archmage` из `Lore` + `GameConfig` | маг появляется вместе с фракцией |
| `scripts/world/world_state.gd:97-104` | `get_archmage(fid) -> Dictionary` | доступ без `.get()` в коде UI |
| `scripts/world/world_sim.gd:42-52` | новая `TickArchmage(power, threat) -> float` | **чистая функция**, легко тестируется |
| `scripts/world/world_bus.gd` | `archmage_tick(delta)`: аккумулятор, раз в `sim_interval` тикает | тик по реальному времени, сим не трогаем |
| `scripts/alm_map.gd:1039` | лимит `bfs_max` клеток в `find_path` | обязателен для 192×192 |
| `scripts/world/map_generator.gd:18-19` | `W`/`H` 128 → 192 | размер следующей локации |
| `scripts/archmage_panel.gd` (**новый**) | панель сдачи, по образцу `inn_panel.gd` | UI |
| `scripts/ui.gd:1337-1354` | `open_archmage()` рядом с `open_inn()` | точка входа |
| `scripts/game.gd:784` | клик по магу → `_archmage_click()` | подход к двери-аналогу |
| `scripts/game.gd:1297` | `_process_pending_archmage()` | открытие при подходе |
| `tests/archmage_smoke.gd` (**новый**) | смоук всего пакета | §10.2 |

## 4. Поток данных

```
WorldBus._process(delta)
  → аккумулятор += delta; если >= sim_interval → archmage_tick()
      → для каждой фракции: power -= WorldSim.TickArchmage(power, threat)
      → смена tier → journal (ровно одна запись)
UI: клик по магу → подход → open_archmage()
  → ArchmagePanel читает WorldState.get_archmage(hero_race)
  → кнопка «Сдать»: берёт предмет из player.inventory
      → power += GameConfig.getf("archmage", "stake_ingot")
      → player.remove_item(key), ровно один раз
      → пишет реплику из Lore.npcs[...].speech
```

## 5. Интерфейсы

```gdscript
# scripts/lore.gd
static func world() -> Dictionary
static func npcs() -> Dictionary
static func npc(id: String) -> Dictionary
static func faction_city(race: String) -> String
static func faction_archmage(race: String) -> String

# scripts/world/world_sim.gd  (чистая функция, без состояния)
func TickArchmage(power: float, threat: float) -> float

# scripts/world/world_state.gd
func get_archmage(faction_id: String) -> Dictionary
func add_archmage_power(faction_id: String, amount: float) -> int   # сколько tier'ов изменилось

# scripts/world/world_bus.gd
func archmage_tick(delta: float) -> int   # сколько тиков прошло

# scripts/alm_map.gd
const BFS_MAX_CELLS := 12000   # при 192×192 = 36864 клеток
```

## 6. Риски

| Риск | Обнаружение | Что делаю |
|---|---|---|
| BFS без лимита убьёт кадр на 192×192 | замер: 16 384 → 36 864 клеток на клик | `BFS_MAX_CELLS`, обрыв → движение напрямую |
| `GRAY_ZONE` — количество, не плотность | на 4× большей карте будет 60-80 Серых | не трогаю сейчас, игрок увидит глазами |
| Фракция без `archmage` (старый сейв) | `.get()` вернёт пусто | панель не показывается, без ошибки |
| Повторная сдача списывает дважды | — | `remove_item` строго один раз, тест |
| `tier` скачет через 2 ступени | одна плата не может дать >100 | `clampf` до 100, тик один |
| Лор-файл отсутствует | `Lore.world()` пусто | маг создаётся без имени, не падает |
| Новая карта ломает `gen_seeds_smoke` | тест сверяет стороны | проверю перед коммитом |

## 7. Порядок работ

1. `game.cfg` + `GameConfig` (числа) — ни от чего не зависит.
2. `Lore` + тест на загрузку.
3. `TickArchmage` + тест мутацией (сломать спад → тест падает).
4. `WorldState.get_archmage` + `WorldBus.archmage_tick`.
5. Лимит BFS + тест на 192×192.
6. `W`/`H` = 192 + прогон `gen_seeds_smoke`, `map_seed_integration`.
7. `ArchmagePanel` + `ui.gd` + клик в `game.gd`.
8. Смоук + парсинг §3 + проверка 1280×800 и 1280×600.

Шаг 8 — единственный, который без вас не проверить. Пункты 1-7 проверяются
автоматически.

## 8. Что осознанно не делаем

- Не чиним тик сим-мира (решение игрока: тикает только маг).
- Не трогаем `production` в генераторе — отдельный пакет.
- Не делаем форпосты и квесты (3.1, 3.2).
- Не ставим спрайт мага в игру как юнит — только как NPC с панелью.