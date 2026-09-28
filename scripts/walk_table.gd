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

# Дефолтная цена прохода по файлу тайла (file 1..7):
# 1 трава (8), 2 горы (14), 3 вода (0 — блок), 4 дорога (6),
# 5 почва (8), 6 песок (12), 7 грязь (14)
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

## Номер файла БИОМА клетки из byte[1] карты.
## У переходных тайлов (файлы 8..15) в младшем ниббле лежит номер файла
## перехода, а не биома, поэтому резолвить надо через AlmLoader: иначе файл
## 8..15 не находитcя в DEFAULT, цена падала на 8, и клетки воды на берегу
## становились проходимыми (замерено: 750 из 1638). Для файлов 1..7
## результат совпадает с прежним "file-1 + 1".
static func file_of(hflags_b: int) -> int:
	return AlmLoader.terrain_file_of(hflags_b)

## Вариация текстуры 0..15 из byte[0] карты (старшие 4 бита).
## У переходного тайла это поле хранит биом-владельца, а не вариацию
## текстуры, поэтому отдаём 0 - иначе оверрайд вида "2-12" применился бы
## к переходу с несуществующей текстурой 12.
static func variant_of(terrain_b: int, hflags_b: int = -1) -> int:
	if hflags_b >= 0 and terrain_file_is_transition(hflags_b):
		return 0
	return clampi((terrain_b >> 4) & 0xF, 0, 15)

## Переходный ли тайл (файлы 8..15).
static func terrain_file_is_transition(hflags_b: int) -> bool:
	var file_idx: int = hflags_b & 0xF
	return file_idx >= 7 and file_idx <= 14

## Спец-значения Nival в byte[1] (16..40: вода/барьер) — непроходимы.
##
## ИСКЛЮЧЕНИЕ: байты с младшим нибблом 7..14 - это НЕ Nival, а наши
## переходные тайлы (файлы 8..15, т.е. file_n-1 = 7..14), у которых старший
## ниббл хранит биом-владельца. Без исключения hf = A*16 + 7..14 попадал в
## 16..40, и кромки гор, воды, дороги, почвы, песка и грязи становились
## НЕПРОХОДИМЫМИ (785 клеток на gen_smart_01).
##
## Побочная потеря: на чужих картах (pvm/, Allods II) спец-значениями
## перестанут определяться 23 и 31..40. На игру это не влияет - в игру
## грузятся только наши карты, pvm/ читает только редактор.
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
## (чтобы не замораживать юнита, выходящего из своей непроходимой клетки).
static func speed_at(hflags_b: int, terrain_b: int) -> float:
	if not walkable_at(hflags_b, terrain_b):
		return 1.0
	return speed(file_of(hflags_b), variant_of(terrain_b, hflags_b))
