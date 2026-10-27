extends SceneTree
##
## Календарь живой игры (28.10): день мира идёт по реальным секундам.
##
## ЗАЧЕМ
## -----
## До этого `state.day` тикал ТОЛЬКО в headless sim_runner (`advance()`), а в
## живой игре стоял на месте. Следствия были тихие: ротация заданий главы не
## срабатывала никогда ([quests] offer_ttl_days считает дни мира), лента мира
## показывала «день 0», угроза и журнал не росли.
##
## ЧТО ПРОВЕРЯЕМ
## -------------
##   1. `[world] day_seconds` есть в конфиге и читается (300 с);
##   2. tick_day копит дробные секунды: 150 + 150 = ровно один день;
##   3. день меняет state.day и шлёт day_changed РОВНО на переходе;
##   4. живой тик НЕ трогает SIM-героя (ложные «Герой окреп» в журнале);
##      headless advance() по-прежнему его трогает (эталон sim_runner);
##   5. reset_day_timer сбрасывает накопленное (загрузка слота не докручивает);
##   6. журнал ограничен JOURNAL_MAX записями (иначе сейв растёт без предела).
##
## Запуск: godot --headless --path . --script res://tests/world_clock_smoke.gd

const WorldBusClass := preload("res://scripts/world/world_bus.gd")

const DAY_SECONDS := 300.0
const JOURNAL_MAX := 400

var _checks := 0
var _fails: Array[String] = []
var _days: Array = []


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(what)
	print(("  OK  " if ok else "  FAIL") + " " + what)


func _initialize() -> void:
	_run.call_deferred()


func _make_bus() -> Node:
	var bus: Node = WorldBusClass.new()
	bus.day_changed.connect(func(d: int) -> void: _days.append(d))
	root.add_child(bus)
	return bus


func _run() -> void:
	print("-- конфиг --")
	GameConfig.load_all()
	var seconds := GameConfig.getf("world", "day_seconds")
	_check(is_equal_approx(seconds, DAY_SECONDS),
		"[world] day_seconds = %.0f (сейчас %.0f)" % [DAY_SECONDS, seconds])

	var bus := _make_bus()
	var state = bus.state
	_check(state != null and "day" in state, "мир собран (WorldState)")

	print("-- дробные секунды копятся --")
	state.day = 0
	_days.clear()
	var n1: int = bus.tick_day(150.0)
	var n2: int = bus.tick_day(150.0)
	_check(n1 == 0, "полдня — ещё не день")
	_check(n2 == 1, "вторые полдня дают ровно один день")
	_check(int(state.day) == 1, "state.day = %d" % int(state.day))
	_check(_days == [1], "day_changed сработал один раз, день %s" % str(_days))

	print("-- живой тик не трогает SIM-героя --")
	var journal_before: int = state.journal.size()
	for _i in range(10):
		bus.tick_day(DAY_SECONDS)
	var live_hero_logs := 0
	for rec in state.journal:
		if str(rec.get("kind", "")) == "hero" or str(rec.get("text", "")).contains("Герой"):
			live_hero_logs += 1
	_check(live_hero_logs == 0,
		"в живом тике нет ложных записей про героя (найдено %d)" % live_hero_logs)
	_check(int(state.day) == 11, "10 тиков = 10 дней (сейчас %d)" % int(state.day))
	_check(state.journal.size() >= journal_before, "журнал пишется, а не чистится")

	print("-- headless-эталон не сломан --")
	var bus2 := _make_bus()
	bus2.advance(8)
	var headless_hero_logs := 0
	for rec in bus2.state.journal:
		if str(rec.get("kind", "")) == "hero":
			headless_hero_logs += 1
	_check(headless_hero_logs > 0,
		"advance() по-прежнему поднимает уровень SIM-героя (%d записей)" % headless_hero_logs)
	_check(int(bus2.state.day) == 8, "advance(8) = день 8 (сейчас %d)" % int(bus2.state.day))

	print("-- сброс календаря --")
	bus2.reset_day_timer()
	var reset_days: int = bus2.tick_day(DAY_SECONDS - 1.0)
	_check(reset_days == 0, "после сброса неполный день не засчитывается")
	_check(int(bus2.state.day) == 8, "день не сдвинулся от сброса")

	print("-- предел журнала --")
	var st = _make_bus().state
	for i in range(JOURNAL_MAX + 50):
		st.log_entry("smoke", "строка %d" % i)
	_check(st.journal.size() == JOURNAL_MAX,
		"журнал обрезан до %d (сейчас %d)" % [JOURNAL_MAX, st.journal.size()])
	_check(str(st.journal[st.journal.size() - 1].get("text", "")).contains("449"),
		"в журнале остались последние записи")

	bus.queue_free()
	bus2.queue_free()
	print("")
	if _fails.is_empty():
		print("RESULT: OK world_clock_smoke (%d checks)" % _checks)
	else:
		print("RESULT: FAIL world_clock_smoke (%d checks, %d fails)" % [_checks, _fails.size()])
		for f in _fails:
			print("  - " + f)
	quit(0 if _fails.is_empty() else 1)
