class_name WalkTable
## Таблица «цены прохода» по текстурам — прямо из данных разработчиков
## (UnityAllods, map.reg / NodeCosts, и оригинальные .alm-карты):
##   CostLand=8, CostGrass=8, CostFlowers=9, CostSand=14, CostCracked=6,
##   CostStones=12, CostSavanna=11, CostMountain=16, CostWater=8(БЛОК), CostRoad=6
## Скорость движения по клетке = 8 / cost (как у них: GetNodeSpeedFactor):
##   трава 1.0, дорога 1.333 (быстрее), песок/камни/горы 0.57..0.67 (медленнее,
##   НО проходимо), вода — блок (движение запрещено).
## Раскладка наших тайлов: byte[1]=file-1 (1..4: трава/земля·горы/вода/дорога),
## byte[0] старший полубайт = вариант текстуры (0..15).
## Редактируемая таблица: assets/maps/walk_speeds.json
##   {"2-5": 12, "2-7": 0, ...} — ключ "файл-вариант" → цена прохода (0 = нельзя).

const OVERRIDE_PATH := "res://assets/maps/walk_speeds.json"

# Дефолтная цена прохода по файлу тайла (file 1..4), как у разработчиков:
# 1 трава (Land/Grass=8), 2 земля/песок/горы (Sand=14), 3 вода (0 — блок),
# 4 дорога (Road=6 — быстрее)
const DEFAULT := {1: 8, 2: 14, 3: 0, 4: 6}

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

## Цена прохода тайла (файл 1..4, вариант 0..15). 0 — непроходимо.
static func cost(file: int, variant: int) -> float:
	_ensure()
	var key := "%d-%d" % [file, variant]
	if _overrides.has(key):
		return float(_overrides[key])
	return float(DEFAULT.get(file, 8))

## Множитель скорости по текстуре (как GetNodeSpeedFactor: 8 / cost).
static func speed(file: int, variant: int) -> float:
	return 8.0 / maxf(1.0, cost(file, variant))

## Проходима ли текстура (цена > 0).
static func walkable(file: int, variant: int) -> bool:
	return cost(file, variant) > 0.0

# --- Помощники для данных карты (byte[1] hflags, byte[0] terrain) ---

## Номер файла тайла (1..4) из byte[1] карты: file-1 в младших 4 битах.
static func file_of(hflags_b: int) -> int:
	return (hflags_b & 0xF) + 1

## Вариант текстуры 0..15 из byte[0] карты (старшие 4 бита).
static func variant_of(terrain_b: int) -> int:
	return clampi((terrain_b >> 4) & 0xF, 0, 15)

## Спец-значения Nival в byte[1] (16..40: вода/барьер) — всегда непроходимы.
static func is_special(hflags_b: int) -> bool:
	return hflags_b >= 16 and hflags_b <= 40

## Проходимость клетки из байтов карты (с учётом спец-значений).
static func walkable_at(hflags_b: int, terrain_b: int) -> bool:
	if is_special(hflags_b):
		return false
	return walkable(file_of(hflags_b), variant_of(terrain_b))

## Множитель скорости клетки из байтов карты; для непроходимых — 1.0
## (чтобы не замораживать юнита, выходящего из своей непроходимой клетки).
static func speed_at(hflags_b: int, terrain_b: int) -> float:
	if not walkable_at(hflags_b, terrain_b):
		return 1.0
	return speed(file_of(hflags_b), variant_of(terrain_b))