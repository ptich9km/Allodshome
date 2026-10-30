# ============================================================================
# TEST: контракт данных SIM-мира (Слой-2, headless).
#
# Закрывает долг аудита 30.09 (01-§3.3):
#   1. экономика города живёт в `cities[].economy` и читается оттуда,
#      а не из плоских ключей, которых там никогда не было;
#   2. плоские ключи старых сейвов поглощаются один раз и удаляются;
#   3. голод считается по ДЕФИЦИТУ дня: изобилие не понижает верность
#      (старый `felt()` возвращал `abs` и наказывал за избыток так же, как
#      за голод);
#   4. амбар не уходит в минус;
#   5. армии с `power` реально воюют и одна гибнет (иначе бой был вечным).
#
# Запуск: godot --headless --path . --script res://tests/world_sim_smoke.gd
# ============================================================================
extends SceneTree

const WorldStateSc := preload("res://scripts/world/world_state.gd")
const WorldSimSc := preload("res://scripts/world/world_sim.gd")

var _fails: Array[String] = []


func _initialize() -> void:
	_test_economy_block()
	_test_legacy_flat_keys()
	_test_surplus_does_not_punish()
	_test_deficit_punishes()
	_test_granary_floor()
	_test_balanced_city()
	_test_armies_fight()
	_test_armies_without_power()
	_report()


## Свежий город: экономика из вложенного блока, плоских ключей не появляется.
func _test_economy_block() -> void:
	var w = WorldStateSc.new()
	var c = w.new_city("Тест")
	var sim = WorldSimSc.new(w)
	sim.TickSettlements()

	var eco: Dictionary = c.get("economy", {})
	# 100 еды + 5 производства − 100 * 0.15 = 90
	_check(is_equal_approx(float(eco.get("food", -1.0)), 90.0),
		"еда читается из economy и тикает (90.0)")
	_check(is_equal_approx(float(eco.get("gold", -1.0)), 55.0),
		"золото читается из economy и растёт на prod (55.0)")
	_check(not c.has("food") and not c.has("prod") and not c.has("gold"),
		"плоских ключей еды/золота/производства город не заводит")


## Сейв старой версии: значения лежат плоско. Их надо ПРОЧИТАТЬ один раз и
## перенести в economy, а не молча потерять.
func _test_legacy_flat_keys() -> void:
	var w = WorldStateSc.new()
	var c = w.new_city("Старый")
	c.erase("economy")
	c["food"] = 500.0
	c["prod"] = 30.0
	c["gold"] = 500.0
	var sim = WorldSimSc.new(w)
	sim.TickSettlements()

	var eco: Dictionary = c.get("economy", {})
	# 500 + 30 − 15 = 515
	_check(is_equal_approx(float(eco.get("food", -1.0)), 515.0),
		"плоские ключи старого сейва поглощены (еда 515.0)")
	_check(is_equal_approx(float(eco.get("gold", -1.0)), 530.0),
		"плоское золото старого сейва поглощено (530.0)")
	_check(not c.has("food") and not c.has("prod") and not c.has("gold"),
		"после поглощения плоские ключи удалены")


## Изобилие не должно понижать верность.
func _test_surplus_does_not_punish() -> void:
	var w = WorldStateSc.new()
	var c = w.new_city("Сытый")
	c["economy"]["food"] = 500.0
	c["economy"]["prod"] = 30.0
	c["loyalty"] = 50.0
	var sim = WorldSimSc.new(w)
	sim.TickSettlements()
	_check(float(c.get("loyalty", 0.0)) > 50.0,
		"при избытке верность растёт, а не падает (старый abs наказывал)")
	_check(is_equal_approx(sim.hunger_of(15.0), 0.0),
		"hunger_of(избыток) = 0")


## Дефицит: верность падает пропорционально голоду, население уменьшается.
func _test_deficit_punishes() -> void:
	var w = WorldStateSc.new()
	var c = w.new_city("Голодный")
	c["economy"]["food"] = 100.0
	c["economy"]["prod"] = 0.0
	c["loyalty"] = 50.0
	c["population"] = 100
	var sim = WorldSimSc.new(w)
	sim.TickSettlements()
	# дефицит 15 в день * 0.1 = 1.5 верности
	_check(is_equal_approx(float(c.get("loyalty", 0.0)), 48.5),
		"голод снимает верность по дефициту (48.5)")
	_check(int(c.get("population", 0)) == 99, "голод уменьшает население (99)")
	_check(is_equal_approx(sim.hunger_of(-15.0), 15.0),
		"hunger_of(дефицит) = величина дефицита")


## Амбар не уходит в минус, даже если дефицит огромный.
func _test_granary_floor() -> void:
	var w = WorldStateSc.new()
	var c = w.new_city("Пустой")
	c["economy"]["food"] = 0.0
	c["economy"]["prod"] = 0.0
	var sim = WorldSimSc.new(w)
	sim.TickSettlements()
	_check(is_equal_approx(float(c["economy"].get("food", -1.0)), 0.0),
		"амбар упирается в ноль, а не уходит в долг")


## Сбалансированный город: население и еда стоят, верность восстанавливается.
func _test_balanced_city() -> void:
	var w = WorldStateSc.new()
	var c = w.new_city("Ровный")
	c["economy"]["food"] = 100.0
	c["economy"]["prod"] = 15.0   # ровно 100 * 0.15
	c["loyalty"] = 50.0
	c["population"] = 100
	var sim = WorldSimSc.new(w)
	sim.TickSettlements()
	_check(int(c.get("population", 0)) == 100, "при балансе население стоит на месте")
	_check(is_equal_approx(float(c["economy"].get("food", -1.0)), 100.0),
		"при балансе еда стоит на месте")
	_check(float(c.get("loyalty", 0.0)) > 50.0, "без голода верность восстанавливается")


## Армии с `power` воюют: за конечное число тиков одна уничтожена.
func _test_armies_fight() -> void:
	var w = WorldStateSc.new()
	var f_a = w.new_faction("A")
	var f_b = w.new_faction("B")
	var a = w.new_army(f_a.id, Vector2(0, 0))
	var b = w.new_army(f_b.id, Vector2(10, 0))
	a["power"] = 100
	b["power"] = 400
	w.relations["%s:%s" % [f_a.id, f_b.id]] = -40
	w.relations["%s:%s" % [f_b.id, f_a.id]] = -40
	var sim = WorldSimSc.new(w)
	var ticks := 0
	while w.armies.size() > 1 and ticks < 500:
		sim.TickArmies()
		ticks += 1
	_check(w.armies.size() == 1,
		"бой армий заканчивается гибелью одной (тиков: %d)" % ticks)


## Армии как их создаёт WorldBus.reseed(): только `unit_ids`, `power` не задан.
## Мощность должна вывестись из состава, иначе потери = 0 и бой вечный.
func _test_armies_without_power() -> void:
	var w = WorldStateSc.new()
	var f_a = w.new_faction("A")
	var f_b = w.new_faction("B")
	var u_a = w.new_unit(f_a.id)
	var u_b = w.new_unit(f_b.id)
	var a = w.new_army(f_a.id, Vector2(0, 0))
	var b = w.new_army(f_b.id, Vector2(10, 0))
	a["unit_ids"] = [u_a.id]
	b["unit_ids"] = [u_b.id]
	w.relations["%s:%s" % [f_a.id, f_b.id]] = -40
	w.relations["%s:%s" % [f_b.id, f_a.id]] = -40
	var sim = WorldSimSc.new(w)
	var ticks := 0
	while w.armies.size() > 1 and ticks < 500:
		sim.TickArmies()
		ticks += 1
	_check(w.armies.size() == 0,
		"равные армии уничтожают друг друга, а не оставляют «мощь 0» (тиков: %d)" % ticks)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)


func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK world_sim_smoke")
		quit(0)
	else:
		print("RESULT: FAIL world_sim_smoke (провалено: %d)" % _fails.size())
		for f in _fails:
			print("  - ", f)
		quit(1)
