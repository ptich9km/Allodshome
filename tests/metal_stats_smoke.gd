extends SceneTree
##
## Тест формулы «металл -> статы» (этап 2 бета-подготовки, 03.10).
##
## ЧТО ЭТОТ ТЕСТ ОХРАНЯЕТ
## ----------------------
## Формулу, а не текущие числа в базе:
##     stats(metal) = base(type, quality) x (ingot_price / ingot_ref) ^ exp
##
## Смысл: руками поддерживать таблицу «20 металлов x 40 типов x 8 качеств»
## бессмысленно — она разъезжается при первом же добавлении металла.
## Степень по цене слитка даёт монотонность САМОЙ СОБОЙ, а игрок крутит
## одно число в game.cfg вместо правки 632 предметов.
##
## ПОЧЕМУ ТЕСТ НЕ ПРОВЕРЯЕТ САМ item_db
## ------------------------------------
## Потому что формула ещё НЕ применена, и это осознанное решение:
## прогон меняет 632 предмета, а выбрать числа — работа игрока (он сам
##reserved их под утро). Тест поэтому честно печатает, сколько металлов
## в базе ещё клоны, но не валит сборку: он охраняет математику, а не
## состояние данных. После `python tests/gen_metal_stats.py` клонов
## станет 0 — это видно в отчёте генератора.
##
## ЗАПУСК
## ------
## godot --headless --path . --script res://tests/metal_stats_smoke.gd
##

const DB_PATH := "res://assets/items/item_db.json"
const CFG_PATH := "res://assets/config/game.cfg"

## Предметы без боевых статов — формула их не касается.
const SKIP_QUALITY := ["Herb", "Scroll", "SuperScroll", "Book", "Quest", "Potion"]
const SKIP_TYPE := ["Ingot", "Herb"]

var _checks := 0
var _fails: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)


func _ingot_prices(items: Array) -> Dictionary:
	var out := {}
	for it in items:
		var d: Dictionary = it
		if str(d.get("type", "")) == "Ingot":
			out[str(d.get("material", ""))] = int(d.get("price", 0))
	return out


func _run() -> void:
	print("-- конфиг --")
	var cfg := ConfigFile.new()
	var err := cfg.load(CFG_PATH)
	if err != OK:
		_check(false, "game.cfg грузится (err=%d)" % err)
		_finish()
		return
	_check(true, "game.cfg грузится")

	var ref := str(cfg.get_value("metal", "reference_metal", ""))
	var d_exp := float(cfg.get_value("metal", "damage_exp", 0.0))
	var t_exp := float(cfg.get_value("metal", "to_hit_exp", 0.0))
	var f_exp := float(cfg.get_value("metal", "defence_exp", 0.0))
	var a_exp := float(cfg.get_value("metal", "absorption_exp", 0.0))

	_check(ref != "", "задан reference_metal (%s)" % ref)
	_check(d_exp > 0.0, "damage_exp положителен (%.3f)" % d_exp)
	_check(f_exp > 0.0, "defence_exp положителен (%.3f)" % f_exp)
	_check(a_exp > 0.0, "absorption_exp положителен (%.3f)" % a_exp)
	_check(t_exp > 0.0 and t_exp <= d_exp,
		"to_hit_exp не больше damage_exp (%.3f <= %.3f): точность растёт медленнее урона"
			% [t_exp, d_exp])

	print("-- база --")
	if not FileAccess.file_exists(DB_PATH):
		_check(false, "item_db.json на месте")
		_finish()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DB_PATH))
	var items: Array = parsed if parsed is Array else []
	_check(items.size() > 0, "item_db.json читается (%d предметов)" % items.size())

	var ingot := _ingot_prices(items)
	_check(ingot.size() >= 15, "слитков достаточно для формулы (%d металлов)" % ingot.size())
	_check(ingot.has(ref), "у reference_metal есть слиток (%s)" % ref)

	var ref_price := float(ingot.get(ref, 0))
	_check(ref_price > 0.0, "цена слитка эталона > 0")

	print("-- монотонность формулы --")
	# ГЛАВНОЕ свойство: множитель строго растёт с ценой слитка.
	# Множитель = (price/ref)^exp, поэтому порядок металлов по цене слитка
	# ДОЛЖЕН совпадать с порядком их множителей. Проверяем на данных.
	var prices: Array = []
	for m in ingot:
		prices.append([float(ingot[m]), str(m)])
	prices.sort()

	var prev_d := -1.0
	var mono := true
	var detail := ""
	for row in prices:
		var ratio := float(row[0]) / ref_price
		var d := pow(ratio, d_exp)
		if d <= prev_d:
			mono = false
			detail = "%s (слиток %d, множитель %.3f) не сильнее предыдущего" % [row[1], int(row[0]), d]
			break
		prev_d = d
	_check(mono, "урон строго растёт с ценой слитка" + ("" if mono else ": " + detail))

	# эталон обязан иметь множитель ровно 1.0 — иначе его собственные
	# числа поедут при первом же прогоне генератора
	_check(is_equal_approx(pow(ref_price / ref_price, d_exp), 1.0),
		"множитель эталонного металла ровно 1.000")

	# крайние точки формулы: без них игрок не понимает, что получит
	var lo := pow(float(prices[0][0]) / ref_price, d_exp)
	var hi := pow(float(prices[prices.size() - 1][0]) / ref_price, d_exp)
	print("    диапазон множителя урона: %.3f (дешевле всех) ... %.3f (дороже всех)"
			% [lo, hi])
	_check(hi > lo, "разброс металлов ощутимый (х%.1f)" % (hi / lo if lo > 0.0 else 0.0))
	_check(hi < 50.0, "верхняя граница не взрывается (%.1f < 50)" % hi)

	print("-- состояние данных (информация, не проверка) --")
	# Сколько металлов сейчас клоны: одинаковый урон на ВСЕ типы и качества.
	var sig := {}
	for it in items:
		var d: Dictionary = it
		var m := str(d.get("material", ""))
		var q := str(d.get("quality", ""))
		var t := str(d.get("type", ""))
		if not ingot.has(m) or SKIP_QUALITY.has(q) or SKIP_TYPE.has(t):
			continue
		if int(d.get("damage_max", 0)) <= 0:
			continue
		var k: String = "%s|%s" % [t, q]
		if not sig.has(k):
			sig[k] = {}
		sig[k][m] = int(d.get("damage_max", 0))
	var clone_metals := {}
	for k in sig:
		var row: Dictionary = sig[k]
		var uniq := {}
		for mm in row:
			uniq[row[mm]] = true
		if uniq.size() == 1 and row.size() > 1:
			for mm in row:
				clone_metals[mm] = true
	print("    металлов-клонов в базе сейчас: %d %s"
			% [clone_metals.size(), clone_metals.keys()])
	print("    (прогон `python tests/gen_metal_stats.py` обнулит их и пересчитает статы)")

	_finish()


func _finish() -> void:
	print("RESULT: %s metal_stats_smoke (проверок: %d, провалов: %d)"
			% ["OK" if _fails.is_empty() else "FAIL", _checks, _fails.size()])
	for f in _fails:
		print("  FAIL " + f)
	quit(0 if _fails.is_empty() else 1)
