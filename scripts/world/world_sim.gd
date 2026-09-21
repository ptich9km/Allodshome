# ============================================================================
# СЛОЙ 2 — SIM. «Мир живёт сам»: тик в ЖЁСТКОМ порядке из 7 шагов (эталон!):
#   1 TickGlobalThreat   глобальная угроза растёт со временем
#   2 TickFactions      фракции: энергия/ресурсы/отношения (utility-скоринг)
#   3 TickArmies        армии: находят врага, двигаются, воюют
#   4 TickSettlements   города: экономика/население/верность
#   5 TickEvents        события мира (бунт, знамение, караван…)
#   6 TickPlayer        «привилегированный» герой — регенерация/опыт
#   7 EmitWorldChanged  мир завершил тик — только ФАКТ, без ссылок на UI
#
# Слой 2 — чистый RefCounted. НИ ОДНОЙ Godot-ноды, как и WorldState.
# Сообщения только в state.journal (данные, сериализуются), UI их сам читает.
# ============================================================================
extends RefCounted
# NOTE (Слой-2 headless-canon): НЕТ `class_name WorldSim` и НЕТ типовых ссылок
# `WorldState` — headless `--quit`/`--script` парсит только по preload-путям.
# Всё взаимодействие слоёв — через const-пути в world_bus.gd, не по имени класса.

var state  # WorldState (данные), см. слой-1; здесь бестипово для headless-canon.


func _init(state_) -> void:
	state = state_


func tick() -> void:
	TickGlobalThreat()
	TickFactions()
	TickArmies()
	TickSettlements()
	TickEvents()
	TickPlayer()
	EmitWorldChanged()


# --- 1. Глобальная угроза -----------------------------------------------------
func TickGlobalThreat() -> void:
	state.global_threat = clampf(state.global_threat + 0.02, 0.0, 1.0)


# --- 2. Фракции (utility) ------------------------------------------------------
func TickFactions() -> void:
	for fid: String in state.factions:
		var f: Dictionary = state.factions[fid]
		var gold := int(f.get("gold", 0))
		var res := int(f.get("res", 0))
		f["gold"] = gold + 5 + randi_range(0, 5)
		f["res"] = res + 2
		f["threat_level"] = state.global_threat
		if randi_range(1, 20) == 1:
			f["mood"] = "_frai" if randi_range(0, 1) == 0 else "_hop"
		else:
			f["mood"] = "_calm"


# --- 3. Армии ------------------------------------------------------------------
func TickArmies() -> void:
	var killed: Array[String] = []
	for aid: String in state.armies:
		var a: Dictionary = state.armies[aid]
		var fid: String = a.get("faction_id", "")
		if fid == "" or not state.armies.has(aid):
			continue
		# Ищем ближайшего врага по отношению < 0.
		var eid := _find_enemy(aid, a, killed)
		if eid == "":
			continue
		a["enemy_id"] = eid
		_fight(aid, a)


func _find_enemy(aid: String, a: Dictionary, killed: Array) -> String:
	var my_fid: String = a.get("faction_id", "")
	var best := ""
	var best_d := 1.0e9
	for oid: String in state.armies:
		if oid == aid or oid in killed:
			continue
		var o: Dictionary = state.armies[oid]
		var ofid: String = o.get("faction_id", "")
		if ofid == my_fid:
			continue
		var rel: int = state.relations.get("%s:%s" % [my_fid, ofid], 0)
		if rel >= 0:
			continue
		var d: float = a.get("pos", Vector2.ZERO).distance_to(o.get("pos", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = oid
	return best


func _fight(aid: String, a: Dictionary) -> void:
	var eid: String = a.get("enemy_id", "")
	if not state.armies.has(eid):
		a["enemy_id"] = ""
		return
	var e: Dictionary = state.armies[eid]
	var my_p := int(a.get("power", 1))
	var e_p := int(e.get("power", 1))
	if my_p <= 0 or e_p <= 0:
		a["enemy_id"] = ""
		return
	var my_loss := int(float(my_p) / float(my_p + e_p) * 0.15 * my_p)
	var e_loss := int(float(e_p) / float(my_p + e_p) * 0.15 * e_p)
	a["power"] = maxi(0, my_p - my_loss)
	e["power"] = maxi(0, e_p - e_loss)
	var winner := ""
	if a["power"] <= 0:
		winner = eid
	elif e["power"] <= 0:
		winner = aid
	if winner != "":
		_log("battle", "Армия %s уничтожила %s" % [winner, (aid if winner == eid else eid)])
		state.armies.erase(winner if winner == eid else aid)


# --- 4. Города ------------------------------------------------------------------
func TickSettlements() -> void:
	for cid: String in state.cities:
		var c: Dictionary = state.cities[cid]
		var pop := int(c.get("population", 100))
		var food := float(c.get("food", 0.0))
		var prod := int(c.get("prod", 0))
		var gold := int(c.get("gold", 0))
		food += prod - pop * 0.15
		gold += prod
		c["population"] = pop + (1 if food > 0 else -1)
		c["food"] = food
		c["gold"] = gold
		var loyalty := float(c.get("loyalty", 50.0))
		if food < 0:
			loyalty = clampf(loyalty - felt(food) * 0.1, 0.0, 100.0)
		c["loyalty"] = loyalty
		if loyalty < 15.0:
			_log("revolt", "Жители %s бунтуют (верность %d%%)" % [c.get("name", cid), int(loyalty)])


func felt(v: float) -> float:
	return -v if v < 0.0 else v


# --- 5. События -----------------------------------------------------------------
func TickEvents() -> void:
	if state.day % 10 == 0 and randi_range(1, 3) == 1:
		_log("omen", "Угроза мира растёт (день %d)" % state.day)
	if state.day % 30 == 0:
		_log("faction", "Фракции обновляют дипломатию каждый месяц")


# --- 6. Игрок (но SIM знает про него как про юнита, не как про UI) -------------
func TickPlayer() -> void:
	var h: Dictionary = state.hero
	h["curr_hp"] = mini(int(h.get("max_hp", 100)), int(h.get("curr_hp", 100)) + 3)
	h["level"] = int(h.get("level", 1))
	if state.day % 7 == 0:
		h["level"] += 1
		_log("hero", "Герой окреп (ур. %d)" % h["level"])


# --- 7. Факт завершения тика (без ссылок на UI/ноды) ---------------------------
func EmitWorldChanged() -> void:
	state.day += 1


func _log(kind: String, text: String) -> void:
	state.journal.append({ "day": state.day, "kind": kind, "text": text })
