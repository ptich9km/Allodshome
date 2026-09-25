extends SceneTree
## Проверка отсева битых фаз анимации зданий (scripts/structure_node.gd).
##
## Баг: у школы (train1/2/3) вторая фаза анимации — заглушки. Верхний ряд
## (house-013/014/015 = 190/118/83 байта) почти пуст, поэтому на фазе 2 крыша
## исчезала и здание выглядело разрушенным.
##
## Старая проверка смотрела ТОЛЬКО на первый тайл фазы (house-013 = 190 б ≥ 160)
## и пропускала битые 014/015. Теперь сравнивается каждый тайл фазы с базовым.
##
## Тест строит StructureNode для всех зданий с анимацией и проверяет, что:
##   — активированная фаза не содержит заглушек (иначе здание мигает);
##   — здания с битыми фазами (train/inn/blacksmith/tower_m) остались статичными;
##   — здания со здоровыми фазами (tower/castle/campfire/druid) сохранили анимацию.
##
## Запуск: godot --headless --path . --script res://tests/structure_anim_smoke.gd

## Ожидаемо поражённые (единственная фаза битая -> остаётся только база).
const EXPECTED_STATIC := [
	"train1", "train2", "train3",
	"inn1", "inn2",
	"blacksmith1", "blacksmith2",
	"tower_m",
]
## Ожидаемо здоровые (анимация осталась, ни одна фаза не отброшена).
const EXPECTED_ANIMATED := [
	"tower1", "tower2", "castle", "campfire", "well3",
	"mill1", "mill3",
	"druidshop1", "druidinn1", "druidhouse1",
]
## Частично поражённые: битые фазы вычёркиваются, остальные крутятся.
## У mill2 биты фазы 3 и 4 (house-030 = 83 б и house-039 = 93 б против базовых
## 325 б — оба пустые), поэтому остаётся 4 блока из 6: [0, 1, 2, 5].
const EXPECTED_PARTIAL := {"mill2": 4}
const EXPECTED_DROPPED := {"mill2": [3, 4]}

var _fails: Array[String] = []
var _checked := 0

func _init() -> void:
	for id in StructureDB.ids():
		var rec: Dictionary = StructureDB.get_by_id(id)
		var folder := str(rec.get("folder", ""))
		if folder == "":
			continue
		var phases := int(rec.get("phases", 1))
		if phases <= 1:
			continue
		_check_folder(id, folder, rec, phases)
	print("ПРОВЕРЕНО зданий с анимацией: %d" % _checked)
	_report()

func _check_folder(id: int, folder: String, rec: Dictionary, phases: int) -> void:
	_checked += 1
	var node := StructureNode.new()
	node.folder = folder
	node.fw = int(rec.get("tile_width", 1))
	node.th = int(rec.get("tile_height", 1))
	node.fh = int(rec.get("full_height", 1))
	node.use_anim = phases > 1
	node.max_blocks = phases
	# _ready() сам вызывает _build(); узел вне дерева — вызываем явно.
	node.call("_build")
	var blocks: int = int(node.get("_blocks"))
	var active: bool = bool(node.get("_active"))
	var grid: int = node.fw * node.fh
	var valid: Array = node.get("_valid_blocks")

	# 1. Ни в одной УДЕРЖАННОЙ фазе не должно быть заглушек — иначе здание мигает.
	if active:
		var bad: int = _find_broken_tile(node, valid, grid)
		_check(bad == 0, "%s (id %d): удержанные фазы без заглушек%s"
			% [folder, id, "" if bad == 0 else " — битый тайл кадра %d" % bad])
		_check(valid.size() >= 2, "%s (id %d): анимация активна (фаз: %d из %d)"
			% [folder, id, valid.size(), blocks])

	# 2. Поражённые здания остаются статичными (только база).
	if folder in EXPECTED_STATIC:
		_check(not active, "%s (id %d): битая фаза отключена, осталась база" % [folder, id])
		_check(valid == [0], "%s (id %d): удержан только блок 0 (получено %s)" % [folder, id, str(valid)])
	# 3. Частично поражённые: битая фаза вычеркнута, остальные работают.
	elif EXPECTED_PARTIAL.has(folder):
		var want: int = int(EXPECTED_PARTIAL[folder])
		_check(active, "%s (id %d): анимация частично сохранена" % [folder, id])
		_check(valid.size() == want,
			"%s (id %d): удержано %d фаз из %d (ожидалось %d)" % [folder, id, valid.size(), blocks, want])
		for dropped in EXPECTED_DROPPED.get(folder, []):
			_check(not (dropped in valid), "%s (id %d): битая фаза %d вычеркнута" % [folder, id, dropped])
		_check(0 in valid, "%s (id %d): база (блок 0) всегда удержана" % [folder, id])
	# 4. Здоровые — ни одна фаза не отброшена.
	elif folder in EXPECTED_ANIMATED:
		_check(active, "%s (id %d): анимация сохранена (фаз: %d из %d)" % [folder, id, valid.size(), blocks])
		_check(valid.size() == blocks,
			"%s (id %d): ни одна фаза не отброшена (%d из %d)" % [folder, id, valid.size(), blocks])

	node.free()

## Номер первого битого тайла среди УДЕРЖАННЫХ фаз (0 — все чисты).
func _find_broken_tile(node, valid_blocks: Array, grid: int) -> int:
	for b in valid_blocks:
		var block: int = int(b)
		if block == 0:
			continue  # база — эталон, её не проверяем
		for i in range(grid):
			var base_size: int = int(node.call("_house_size", i + 1))
			var phase_size: int = int(node.call("_house_size", block * grid + i + 1))
			if base_size <= 0 or phase_size < 0:
				continue
			if float(phase_size) / float(base_size) < StructureNode.BROKEN_PHASE_RATIO:
				return block * grid + i + 1
	return 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)

func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK structure_anim_smoke")
		quit(0)
	else:
		print("RESULT: FAIL structure_anim_smoke (провалено: %d)" % _fails.size())
		for x in _fails:
			print("  - ", x)
		quit(1)
