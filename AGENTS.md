# AGENTS.md — заметки агента по проекту Allodshome_Godot

> Памятка для продолжения работы из любой сессии. Обновляй при каждом заметном шаге.
> Обновлено: **Ш2 готово (вариант 1)** — автолоад `WorldBus` (`scripts/world/world_bus.gd`) зарегистрирован в `project.godot`; слои-2 убрали global-`class_name` (осталось только `extends RefCounted`) для headless-резолва. Headless-контроль проекта `0 SCRIPT ERROR` (см. ниже). — введены Слои 1-2 (чистый RefCounted-мир без сцены): `scripts/world/world_state.gd` (DATA, реестры по стабильным ID, to_dict/from_dict) и `scripts/world/world_sim.gd` (SIM, тик из 7 жёстких шагов, журнал событий в `state.journal`). Контроль: `--headless --quit` = **0 SCRIPT ERROR**.
>
> Запуск головного headless-раннера мира: `godot --headless --path ... --script res://scripts/world/sim_runner.gd` (см. Слой-2 заметку ниже).

## Как запустить Godot (важно!)

Проект: `D:\Work\UnityProjects\Allodshome_Godot`
Консольный движок (в PATH не прописан, есть в Root):
- `D:\Work\UnityProjects\Godot_v4.7.2-stable_win64_console.exe`
- (обычный GUI-вариант рядом: `..._win64.exe`)

Быстрый тест «парсится ли всё» (headless, выход сразу):
```
& 'D:\Work\UnityProjects\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'D:\Work\UnityProjects\Allodshome_Godot' --quit 2>&1 | Select-String 'SCRIPT ERROR|Parse Error'
```
Отсутствие `SCRIPT ERROR` = скрипты компилируются. Эту команду используем как «контрольную точку» после любых правок.

Парсинг GODOT по скриптам можно отличить от «картинок-мусора»: выводимая Unicode-каша из PNG/CJK-файлов в `assets/` — норма, читаем только `.gd`-файлы. НЕ запускай `Get-ChildItem` на весь `assets` с фильтром по CJK — там сотни картинок.

## Что сделано сегодня (главное)

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

## План / что осталось (в порядке приоритета)

### П0 Единая точка урона — сверено
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
- `scripts/ui.gd`, `scripts/character_select.gd` — UI (панель сфер мага вместо навыков оружия — TODO).

## Как проверять
- Godot headless через `--quit` (см. команду вверху) — главный контроль парсинга.
- Только `.gd`-файлы читать на русском; `assets/**` — бинарь/картинки, игнорировать.

