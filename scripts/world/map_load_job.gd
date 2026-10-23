# ============================================================================
# MapLoadJob — прогресс фоновой генерации карты.
#
# Поток-генератор пишет percent/phase, главный поток читает snapshot().
# Доступ к полям — только под Mutex: GDScript-контейнеры не потокобезопасны,
# а читатель и писатель живут в разных потоках.
#
# Без class_name: грузится load()-по-пути в headless-сценариях.
# ============================================================================
extends RefCounted

## Фазы генерации (индекс -> подпись берёт UI).
const PHASE_START := 0
const PHASE_TERRAIN := 1
const PHASE_CITIES := 2
const PHASE_ROADS := 3
const PHASE_RELIEF := 4
const PHASE_PORTALS := 5
const PHASE_CITY_CONTENT := 6
const PHASE_OBJECTS := 7
const PHASE_HERBS := 8
const PHASE_GREYS := 9
const PHASE_TILES := 10
const PHASE_SAVE := 11
const PHASE_DONE := 12
const PHASE_COUNT := 13

var _mutex := Mutex.new()
var _percent := 0
var _phase := PHASE_START
var _error := ""


func set_progress(percent: int, phase: int) -> void:
	_mutex.lock()
	_percent = clampi(percent, 0, 100)
	_phase = phase
	_mutex.unlock()


func set_error(text: String) -> void:
	_mutex.lock()
	_error = text
	_mutex.unlock()


func snapshot() -> Dictionary:
	_mutex.lock()
	var out := {"percent": _percent, "phase": _phase, "error": _error}
	_mutex.unlock()
	return out
