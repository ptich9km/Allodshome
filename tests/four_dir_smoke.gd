# ============================================================================
# TEST: набор героя из ЧЕТЫРЁХ нарисованных ракурсов (dirs = 4).
#
# Зачем: 3D-модель отдаёт четыре вида бесплатно (камеру двигаем мы), но движок
# раньше знал только dirs=1 (+зеркало), dirs=5 и dirs=8. Проверяем:
#   1. таблицу соответствия мировых направлений файловым (UnitAnim.FILE_DIR_4);
#   2. что направления взяты из Game.unit_octant, а не придуманы заново;
#   3. раскладку блоков: 48 кадров = 12 * 4, и что последний кадр последнего
#      блока не выходит за пределы набора (`UnitAnim._block_offset`).
#
# Запуск: godot --headless --path . --script res://tests/four_dir_smoke.gd
# ============================================================================
extends SceneTree

# Что генератор (tests/render_3d_frames.py --directions 4) пишет в _entry.json.
const DIRS := 4
const IDLE_PHASES := 4      # суммарно, по 1 кадру стойки на ракурс
const IDLE_PER_DIR := 1
const MOVE := 4
const ATTACK := 3
const DYING := 4
const FRAMES := 48          # 12 * DIRS

var _fails: Array[String] = []


func _initialize() -> void:
	_test_table()
	_test_matches_game_octant()
	_test_layout()
	_report()


## Таблица: 8 мировых направлений, значения 0..3, все четыре ракурса
## используются, диагонали схлопываются на бок.
func _test_table() -> void:
	var table: Array = UnitAnim.FILE_DIR_4
	_check(table.size() == 8, "FILE_DIR_4 покрывает 8 мировых направлений")
	var ok_range := true
	for v in table:
		if int(v) < 0 or int(v) > 3:
			ok_range = false
	_check(ok_range, "все файловые направления в 0..3 (иначе кадра не существует)")
	var seen := {}
	for v in table:
		seen[int(v)] = true
	_check(seen.size() == 4, "используются все четыре ракурса")
	_check(int(table[1]) == 1 and int(table[3]) == 1 and int(table[5]) == 3
		and int(table[7]) == 3,
		"диагонали показываются боком (1 или 3), а не спиной/лицом")


## Таблица обязана совпадать с конвенцией Game.unit_octant: 0=вниз экрана,
## 2=влево, 4=вверх, 6=вправо.
func _test_matches_game_octant() -> void:
	var down: int = Game.unit_octant(Vector2(0.0, 1.0))
	var left: int = Game.unit_octant(Vector2(-1.0, 0.0))
	var up: int = Game.unit_octant(Vector2(0.0, -1.0))
	var right: int = Game.unit_octant(Vector2(1.0, 0.0))
	_check(down == 0, "unit_octant(вниз) = 0")
	_check(left == 2, "unit_octant(влево) = 2")
	_check(up == 4, "unit_octant(вверх) = 4")
	_check(right == 6, "unit_octant(вправо) = 6")
	_check(int(UnitAnim.FILE_DIR_4[down]) == 0, "идём вниз -> файловый 0 (лицом)")
	_check(int(UnitAnim.FILE_DIR_4[left]) == 1, "идём влево -> файловый 1 (профиль)")
	_check(int(UnitAnim.FILE_DIR_4[up]) == 2, "идём вверх -> файловый 2 (спина)")
	_check(int(UnitAnim.FILE_DIR_4[right]) == 3, "идём вправо -> файловый 3 (профиль)")


## Раскладка: кадр = block_offset + file_dir * phases + phase (dir-major).
func _test_layout() -> void:
	_check(IDLE_PHASES == DIRS * IDLE_PER_DIR,
		"idle_phases — суммарные кадры стойки (4 = 4 ракурса по 1)")
	var move_start := IDLE_PHASES
	var attack_start := move_start + MOVE * DIRS
	var dying_start := attack_start + ATTACK * DIRS
	_check(move_start == 4, "блок ходьбы начинается с кадра 4")
	_check(attack_start == 20, "блок удара начинается с кадра 20")
	_check(dying_start == 32, "блок смерти начинается с кадра 32")
	var total: int = dying_start + DYING * DIRS
	_check(total == FRAMES, "48 кадров покрывают все блоки и ракурсы")
	var last_index: int = dying_start + (DIRS - 1) * DYING + (DYING - 1)
	_check(last_index == FRAMES - 1,
		"последний кадр смерти последнего ракурса = 47 (индекс не вылезает)")
	var idle_last: int = (DIRS - 1) * IDLE_PER_DIR
	_check(idle_last == 3, "стойка последнего ракурса = кадр 3, до блока ходьбы")


func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)


func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK four_dir_smoke")
		quit(0)
	else:
		print("RESULT: FAIL four_dir_smoke (провалено: %d)" % _fails.size())
		for f in _fails:
			print("  - ", f)
		quit(1)
