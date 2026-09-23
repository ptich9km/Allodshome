# ============================================================================
# TEST: симуляция мира (Слой-2, headless) — «смотреть как идёт ход».
#
# Запуск из консоли:
#   & 'C:\Games\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Work\Allodshome' --script "res://tests/test_simulation.gd"
#
# Печатает каждую journal-запись по дню, раз в N дней — сводку мира.
# Канон: бестиповые var, без class_name/:= (не выводить через preload-пути).
# ============================================================================
extends SceneTree

const WorldStateSc := preload("res://scripts/world/world_state.gd")
const WorldSimSc := preload("res://scripts/world/world_sim.gd")

const DAYS := 100          # сколько дней симулируем
const SUMMARY_EVERY := 10  # сводка каждые N дней (0 = не печатать)

const DAY_HEAD_STEP := 5   # печатать «DAY n» каждые N дней (0 = никогда)


func _init() -> void:
	_run()


func _run() -> void:
	var w = WorldStateSc.new()
	var sim = WorldSimSc.new(w)

	# Песочница: 2 фракции (война), 2 города, 2 армии, 1 регион.
	var f_h = w.new_faction("Human")
	var f_e = w.new_faction("Orc")
	var r = w.new_region("Region")
	var c_h = w.new_city("Keep", f_h.id, r.id)
	var c_e = w.new_city("Hideout", f_e.id, r.id)
	f_h["color"] = Color(0.2, 0.6, 1.0)
	f_e["color"] = Color(1.0, 0.4, 0.2)

	# Городам — нормальная стартовая экономика (иначе голод → бунт каждый день).
	c_h["food"] = 500.0
	c_h["prod"] = 30
	c_h["gold"] = 500
	c_h["population"] = 100
	c_e["food"] = 500.0
	c_e["prod"] = 30
	c_e["gold"] = 500
	c_e["population"] = 100

	var u1 = w.new_unit(f_h.id, "fire")
	var u2 = w.new_unit(f_e.id, "fire")
	var u3 = w.new_unit(f_h.id, "earth")

	var a_h = w.new_army(f_h.id, Vector2(300, 500))
	var a_e = w.new_army(f_e.id, Vector2(700, 500))
	a_h["unit_ids"] = [u1.id, u3.id]
	a_e["unit_ids"] = [u2.id]
	a_h["power"] = 100
	a_e["power"] = 100

	w.relations["%s:%s" % [f_h.id, f_e.id]] = -40
	w.relations["%s:%s" % [f_e.id, f_h.id]] = -40

	print("=== МИР: %s vs %s, города %s и %s, армии %d и %d ===" % [
		f_h.name, f_e.name, c_h.name, c_e.name,
		a_h.unit_ids.size() + 1, a_e.unit_ids.size() + 1,
	])
	print("")

	for i in DAYS:
		var before: int = w.journal.size()
		sim.tick()
		if DAY_HEAD_STEP > 0 and (i + 1) % DAY_HEAD_STEP == 0:
			print("— день %d (угроза %.0f%%) —" % [w.day, w.global_threat * 100.0])

		# События дня (новые записи журнала).
		for j in range(before, w.journal.size()):
			var e: Dictionary = w.journal[j]
			print("  [%d] %s: %s" % [e.get("day", w.day), e.get("kind", "?"), e.get("text", "")])

		_after_tick(w)

	if SUMMARY_EVERY > 0 and (DAYS % SUMMARY_EVERY) != 0:
		_summary(w, DAYS)

	print("")
	print("=== ИТОГ после %d дней: day=%d, угроза=%.0f%%, городов=%d, армий=%d, журнал=%d ===" % [
		DAYS, w.day, w.global_threat * 100.0,
		w.cities.size(), w.armies.size(), w.journal.size(),
	])
	quit(0)


func _after_tick(w) -> void:
	if SUMMARY_EVERY > 0 and w.day % SUMMARY_EVERY == 0:
		_summary(w, w.day)


func _summary(w, day: int) -> void:
	var a_list := []
	for aid: String in w.armies:
		var a: Dictionary = w.armies[aid]
		a_list.append("%s(мощь %d)" % [a.get("id", aid), int(a.get("power", 0))])
	print("-- сводка день %d: угроза=%.0f%% | %d городов | армии: %s | журнал=%d" % [
		day, w.global_threat * 100.0,
		w.cities.size(), ", ".join(a_list), w.journal.size(),
	])