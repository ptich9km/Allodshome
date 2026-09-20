# ============================================================================
# LAYER-2.5 SIM_RUNNER (headless). World lives on its own: 100 days, no scene.
#
# HEADLESS NOTES (critical, verified the hard way):
#  * `--script` in Godot does NOT register global class_name symbols, so any
#    `var x := w.new_*()` (type inference from Dictionary-returning methods)
#    and any global-class reference fail with "Parse Error".
#  * Remedy used below: ALL local vars untyped (`var x = ...`), both source
#    layers loaded by path into consts, no `:=`, no class references.
#
# Run:  godot --headless --path . --script res://scripts/world/sim_runner.gd
# ============================================================================
extends SceneTree

const WorldStateSc := preload("res://scripts/world/world_state.gd")
const WorldSimSc := preload("res://scripts/world/world_sim.gd")


func _initialize() -> void:
	var w = WorldStateSc.new()
	var sim = WorldSimSc.new(w)

	# Sandbox world: 2 factions, 2 cities, 2 units, 2 armies, 1 region, war.
	var f_h = w.new_faction("Human")
	var f_e = w.new_faction("Orc")
	var r = w.new_region("Region")
	var c_h = w.new_city("Keep", f_h.id, r.id)
	var c_e = w.new_city("Hideout", f_e.id, r.id)
	var u1 = w.new_unit(f_h.id, "fire")
	var u2 = w.new_unit(f_e.id, "fire")
	var a_h = w.new_army(f_h.id, Vector2(300, 500))
	var a_e = w.new_army(f_e.id, Vector2(700, 500))
	a_h["unit_ids"] = [u1.id]
	a_e["unit_ids"] = [u2.id]
	w.relations["%s:%s" % [f_h.id, f_e.id]] = -40
	w.relations["%s:%s" % [f_e.id, f_h.id]] = -40

	for i in 100:
		sim.tick()
		if i % 20 == 19:
			print("day %d: threat=%.2f, cities=%d, journal=%d" % [
				w.day, w.global_threat, w.cities.size(), w.journal.size()
			])
	print("RESULT: world survived 100 days. day=%d, threat=%.2f, journal=%d" % [
		w.day, w.global_threat, w.journal.size()
	])
	quit()
