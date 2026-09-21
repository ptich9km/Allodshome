# ============================================================================
# LAYER-2.5 WorldBus (Autoload Node, headless-canon).
#
# HEADLESS CANON (шаг-3 AGENTS.md, «Ш2-вариант-1»; проверено на боли в
# sim_runner.gd): при global-кеше классов headless НЕ имеет резолва, поэтому
# в автолоаде ЗАПРЕЩЕНЫ `const X := preload(...)` и любые `:=` — каждый
# cross-layer доступ — ТОЛЬКО untyped + load-по-пути в _ready.
#
# Роль: тонкий бус-раннер, держит WorldState(ДАННЫЕ)+WorldSim(СИМ), умеет
# `advance(days)` и `snapshot()`. Вся логика — в RefCounted-слоях, НИКОГДА тут.
# ============================================================================
extends Node

var state   # WorldState  — слой-1 ДАННЫЕ (RefCounted)
var sim     # WorldSim    — слой-2 СИМ (RefCounted)


func _ready() -> void:
	var st_script: GDScript = load("res://scripts/world/world_state.gd")
	var sim_script: GDScript = load("res://scripts/world/world_sim.gd")
	state = st_script.new()
	sim = sim_script.new(state)
	reseed()


func reseed() -> void:
	var f_h: Dictionary = state.new_faction("Люди")
	var f_e: Dictionary = state.new_faction("Орки")
	var r: Dictionary = state.new_region("Черноземье")
	var c_h: Dictionary = state.new_city("Речной Пост", f_h.id, r.id)
	var c_e: Dictionary = state.new_city("Кровавый Бор", f_e.id, r.id)
	var u1: Dictionary = state.new_unit(f_h.id, "fire")
	var u2: Dictionary = state.new_unit(f_e.id, "fire")
	var a_h: Dictionary = state.new_army(f_h.id, Vector2(300, 400))
	var a_e: Dictionary = state.new_army(f_e.id, Vector2(700, 400))
	a_h["unit_ids"] = [u1.id]
	a_e["unit_ids"] = [u2.id]
	state.relations["%s:%s" % [f_h.id, f_e.id]] = -40
	state.relations["%s:%s" % [f_e.id, f_h.id]] = -40


func advance(days: int) -> void:
	for _i in days:
		sim.tick()


func snapshot() -> Dictionary:
	return {
		"day": state.day, "global_threat": state.global_threat,
		"cities": state.cities.size(), "armies": state.armies.size(),
		"units": state.units.size(), "journal": state.journal.size(),
	}
