class_name WalkTable
## Таблица «цены прохода» по текстурам — прямо из данных разработчиков
## (UnityAllods, map.reg / NodeCosts, и оригинальные .alm-карты):
##   CostLand=8, CostGrass=8, CostFlowers=9, CostSand=14, CostCracked=6,
##   CostStones=12, CostSavanna=11, CostMountain=16, CostWater=8(БЛОК), CostRoad=6
## Скорость движения по клетке = 8 / cost (как у них: GetNodeSpeedFactor).
##
## 05.10 (решение игрока): ГОРЫ (file 2) непроходимы для ВСЕХ пеших — как вода.
## Летающие (UnitDB.fly_z > 0: bat/dragon/succubus) обходят проверку земли
## в enemy.gd и идут над водой и над горами. Цена гор 14 сохранена —
## если режим/юнит спросит скорость на горе, она останется прежней.
## Редактируемая таблица: assets/maps/walk_speeds.json
##   {"2-5": 12, "2-7": 0, ...} — ключ "файл-вариант" → цена прохода (0 = нельзя).

const OVERRIDE_PATH := "res://assets/maps/walk_speeds.json"

## Файл тайла гор в наших BMP (tile2 = biome 1).
const MOUNTAIN_FILE := 2
## Файл воды.
const WATER_FILE := 3

# Дефолтная цена прохода по файлу тайла (file 1..7):
# 1 трава (8), 2 горы (14 — см. блок про walkable), 3 вода (0 — блок),
# 4 дорога (6), 5 почва (8), 6 песок (12), 7 грязь (14)
const DEFAULT := {1: 8, 2: 14, 3: 0, 4: 6, 5: 8, 6: 12, 7: 14}

static var _overrides: Dictionary = {}
static var _loaded := false

static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(OVERRIDE_PATH):
		return
	var f := FileAccess.open(OVERRIDE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		for key in parsed:
			if not str(key).begins_with("_"):
				_overrides[key] = parsed[key]

## Цена прохода тайла (файл 1..7, вариант 0..15). 0 — непроходимо.
static func cost(file: int, variant: int) -> float:
	_ensure()
	var key := "%d-%d" % [file, variant]
	if _overrides.has(key):
		return float(_overrides[key])
	return float(DEFAULT.get(file, 8))

## Множитель скорости по текстуре (как GetNodeSpeedFactor: 8 / cost).
static func speed(file: int, variant: int) -> float:
	return 8.0 / maxf(1.0, cost(file, variant))

## Проходима ли текстура для пеших (герой, НПЦ, обычные враги).
## Горы (file 2) и вода (file 3) — блок. Летающие здесь не ходят.
static func walkable(file: int, variant: int) -> bool:
	if file == MOUNTAIN_FILE or file == WATER_FILE:
		return false
	return cost(file, variant) > 0.0

# --- Помощники для данных карты (byte[1] hflags, byte[0] terrain) ---

## Номер файла БИОМА клетки из byte[1] карты.
static func file_of(hflags_b: int) -> int:
	return AlmLoader.terrain_file_of(hflags_b)

## Вариация текстуры 0..15 из byte[0] карты (старшие 4 бита).
static func variant_of(terrain_b: int, hflags_b: int = -1) -> int:
	if hflags_b >= 0 and terrain_file_is_transition(hflags_b):
		return 0
	return clampi((terrain_b >> 4) & 0xF, 0, 15)

## Переходный ли тайл (файлы 8..15).
static func terrain_file_is_transition(hflags_b: int) -> bool:
	var file_idx: int = hflags_b & 0xF
	return file_idx >= 7 and file_idx <= 14

## Спец-значения Nival в byte[1] (16..40: вода/барьер) — непроходимы.
static func is_special(hflags_b: int) -> bool:
	if hflags_b < 16 or hflags_b > 40:
		return false
	return (hflags_b & 0xF) < 7

## Проходимость клетки из байтов карты (с учётом спец-значений и переходов).
static func walkable_at(hflags_b: int, terrain_b: int) -> bool:
	if is_special(hflags_b):
		return false
	return walkable(file_of(hflags_b), variant_of(terrain_b, hflags_b))


## Множитель скорости клетки из байтов карты; для непроходимых — 1.0
static func speed_at(hflags_b: int, terrain_b: int) -> float:
	if not walkable_at(hflags_b, terrain_b):
		return 1.0
	return speed(file_of(hflags_b), variant_of(terrain_b, hflags_b))
