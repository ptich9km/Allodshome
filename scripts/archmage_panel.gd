class_name ArchmagePanel
extends CanvasLayer
## Панель великих магов: военная плата (GDD docs/lore/gdd_archmage.md).
##
## Маг в городе — капитан (NPC `is_archmage`), спрайт `ork_mage_a52/tN` по ступени.
## Источник данных — WorldBus.state.factions[...]["archmage"] (тик по реальному
## времени, sim-мир не тикает). Ставки: слиток / золото / зелье.

signal closed
signal inventory_changed

var player: Player
var _root: MarginContainer
var _panel: PanelContainer
var _name_label: Label
var _city_label: Label
var _portrait: TextureRect
var _power_bar: ProgressBar
var _power_label: Label
var _stance_label: Label
var _speech_label: Label
var _status_label: Label
var _btn_ingot: Button
var _btn_gold: Button
var _btn_potion: Button
var _close_button: Button
var _previous_focus: Control
var _last_tier := -1

const TIER_LABELS := ["Оборона", "Наступление", "Крепость", "Вершина"]


func setup(p: Player) -> void:
	player = p
	layer = 10
	_build_ui()


func _ready() -> void:
	_previous_focus = UiKit.save_focus(self)
	_last_tier = -1
	_refresh()
	_btn_ingot.call_deferred("grab_focus")


func _archmage() -> Dictionary:
	var bus := get_node_or_null("/root/WorldBus")
	if bus == null or bus.state == null:
		return {}
	return bus.state.get_archmage(Game.hero_race)


func _ws_script() -> GDScript:
	return load("res://scripts/world/world_state.gd") as GDScript


func _build_ui() -> void:
	var dim := UiKit.make_dim(0.58)
	add_child(dim)

	_root = MarginContainer.new()
	_root.name = "ArchmageRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.set_margins(_root, UiTheme.SCREEN_INSET, UiTheme.SCREEN_INSET,
		UiTheme.SCREEN_INSET, UiTheme.SCREEN_INSET)
	_root.theme = _make_theme()
	add_child(_root)

	var center := HBoxContainer.new()
	center.name = "Center"
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var side := Control.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(side)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.theme_type_variation = &"ArchmagePanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.custom_minimum_size = Vector2(520, 420)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	UiKit.set_margins(margin, UiTheme.SPACE_5, UiTheme.SPACE_4,
		UiTheme.SPACE_5, UiTheme.SPACE_4)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", UiTheme.SPACE_3)
	margin.add_child(content)

	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"ArchmageTitle"
	title.text = tr("ВЕЛИКИЙ МАГ")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	var head := HBoxContainer.new()
	head.name = "Head"
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", UiTheme.SPACE_4)
	content.add_child(head)

	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.custom_minimum_size = Vector2(72, 80)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_portrait)

	var head_col := VBoxContainer.new()
	head_col.name = "HeadCol"
	head_col.alignment = BoxContainer.ALIGNMENT_CENTER
	head_col.add_theme_constant_override("separation", UiTheme.SPACE_1)
	head_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_col)

	_name_label = Label.new()
	_name_label.name = "MageName"
	_name_label.theme_type_variation = &"ArchmageName"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head_col.add_child(_name_label)

	_city_label = Label.new()
	_city_label.name = "CityName"
	_city_label.theme_type_variation = &"ArchmageCity"
	_city_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head_col.add_child(_city_label)

	_power_bar = ProgressBar.new()
	_power_bar.name = "PowerBar"
	_power_bar.min_value = 0.0
	_power_bar.max_value = 100.0
	_power_bar.show_percentage = false
	_power_bar.custom_minimum_size = Vector2(0, 22)
	content.add_child(_power_bar)

	_power_label = Label.new()
	_power_label.name = "PowerLabel"
	_power_label.theme_type_variation = &"ArchmagePower"
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_power_label)

	_stance_label = Label.new()
	_stance_label.name = "StanceLabel"
	_stance_label.theme_type_variation = &"ArchmageStance"
	_stance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_stance_label)

	_speech_label = Label.new()
	_speech_label.name = "Speech"
	_speech_label.theme_type_variation = &"ArchmageSpeech"
	_speech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech_label.custom_minimum_size = Vector2(0, 72)
	content.add_child(_speech_label)

	var stakes := VBoxContainer.new()
	stakes.name = "Stakes"
	stakes.add_theme_constant_override("separation", UiTheme.SPACE_2)
	content.add_child(stakes)

	_btn_ingot = _make_stake_button("Сдать слиток", _on_stake_ingot)
	stakes.add_child(_btn_ingot)
	_btn_gold = _make_stake_button("Сдать золото (100)", _on_stake_gold)
	stakes.add_child(_btn_gold)
	_btn_potion = _make_stake_button("Сдать зелье", _on_stake_potion)
	stakes.add_child(_btn_potion)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.theme_type_variation = &"ArchmageStatus"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0, 36)
	content.add_child(_status_label)

	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", UiTheme.SPACE_2)
	content.add_child(row)

	_close_button = Button.new()
	_close_button.name = "Close"
	_close_button.text = tr("Закрыть")
	_close_button.theme_type_variation = &"ArchmageClose"
	_close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close_button.pressed.connect(close)
	row.add_child(_close_button)


func _make_stake_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = &"ArchmageStake"
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(handler)
	return b


func _make_theme() -> Theme:
	var theme := UiTheme.app_theme()
	UiKit.add_panel(theme, &"ArchmagePanel",
		UiTheme.PANEL_BG, UiTheme.PANEL_EDGE, UiTheme.RADIUS_PANEL)
	UiKit.add_label(theme, &"ArchmageTitle", UiTheme.ACCENT, UiTheme.FONT_TITLE)
	UiKit.add_label(theme, &"ArchmageName", UiTheme.TEXT, UiTheme.FONT_SECTION)
	UiKit.add_label(theme, &"ArchmageCity", UiTheme.TEXT_MUTED, UiTheme.FONT_BODY)
	UiKit.add_label(theme, &"ArchmagePower", UiTheme.TEXT, UiTheme.FONT_SUBHEAD)
	UiKit.add_label(theme, &"ArchmageStance", UiTheme.TEXT_MUTED, UiTheme.FONT_BODY)
	UiKit.add_label(theme, &"ArchmageSpeech", UiTheme.TEXT, UiTheme.FONT_BODY)
	UiKit.add_label(theme, &"ArchmageStatus", UiTheme.TEXT_MUTED, UiTheme.FONT_MICRO)
	UiKit.add_button(theme, &"ArchmageStake",
		UiTheme.PANEL_INNER, UiTheme.ACCENT_DIM,
		UiTheme.PANEL_INNER.lightened(0.14), UiTheme.ACCENT,
		UiTheme.RADIUS_SLOT, UiTheme.SPACE_2)
	UiKit.add_button(theme, &"ArchmageClose",
		UiTheme.PANEL_INNER, UiTheme.PANEL_EDGE.darkened(0.25),
		UiTheme.PANEL_INNER.lightened(0.12), UiTheme.ACCENT_DIM,
		UiTheme.RADIUS_SLOT, UiTheme.SPACE_2)
	return theme


func _refresh() -> void:
	var am := _archmage()
	if am.is_empty():
		_name_label.text = tr("Маг недоступен")
		_power_label.text = ""
		_stance_label.text = ""
		_speech_label.text = tr("В этом городе великого мага нет.")
		_set_stake_enabled(false, false, false)
		if _portrait != null:
			_portrait.texture = null
			_portrait.visible = false
		return
	var power := float(am.get("power", 0.0))
	var tier := int(am.get("tier", 0))
	var max_power := 100.0
	var cfg := ConfigFile.new()
	if cfg.load("res://assets/config/game.cfg") == OK:
		max_power = float(cfg.get_value("archmage", "power_max", 100.0))
	_power_bar.max_value = max_power
	_power_bar.value = power
	_name_label.text = str(am.get("name", tr("Маг")))
	_city_label.text = str(am.get("city", ""))
	_power_label.text = tr("Могущество: %d / %d · ступень %d (%s)") % [
		int(round(power)), int(max_power), tier,
		str(TIER_LABELS[clampi(tier, 0, TIER_LABELS.size() - 1)]),
	]
	_stance_label.text = tr("Режим: %s") % ("наступление" if str(am.get("stance", "")) == "offensive" else tr("оборона"))
	if not _speech_label.text.begins_with(tr("Сдавайте")):
		_speech_label.text = tr("Сдавайте ресурсы: слитки, золото, зелья. Могущество держит фракцию.")
	_speak_if_tier_changed(tier)
	_set_portrait(tier)
	_sync_captain_sprite(tier)
	var full := power >= max_power - 0.01
	_set_stake_enabled(not full, not full and _has_gold_stake(), not full and _find_stake_key("potion") != "")
	if full:
		_status_label.text = tr("Маг не возьмёт больше.")
	else:
		_status_label.text = ""


func _speak_if_tier_changed(tier: int) -> void:
	if _last_tier < 0:
		_last_tier = tier
		return
	if tier == _last_tier:
		return
	_last_tier = tier
	var lines: Array = Lore.archmage_speech(Game.hero_race, "idle")
	if lines.is_empty():
		lines = Lore.archmage_speech(Game.hero_race, "greet")
	if lines.is_empty():
		return
	_speech_label.text = tr("«%s»") % str(lines[randi() % lines.size()])


func _set_portrait(tier: int) -> void:
	if _portrait == null:
		return
	var set_name := "ork_mage_a52/t%d" % clampi(tier, 0, 3)
	var path := UnitDB.frame_path(set_name, "sprites", 1)
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_portrait.texture = tex
	_portrait.visible = tex != null


func _sync_captain_sprite(tier: int) -> void:
	var set_name := "ork_mage_a52/t%d" % clampi(tier, 0, 3)
	var scene := get_tree().current_scene
	if scene == null:
		return
	for child in scene.get_children():
		if child is Npc and bool(child.get("is_archmage")):
			if str(child.anim_set) != set_name:
				child.anim_set = set_name
				var anim = child.get_node_or_null("UnitAnim")
				if anim != null and anim.has_method("setup"):
					anim.setup(set_name)


func _set_stake_enabled(ingot: bool, gold: bool, potion: bool) -> void:
	_btn_ingot.disabled = not ingot
	_btn_gold.disabled = not gold
	_btn_potion.disabled = not potion


func _has_gold_stake() -> bool:
	if not is_instance_valid(player):
		return false
	var gps := 100
	var ws := _ws_script()
	if ws != null:
		gps = int(ws.archmage_gold_per_stake())
	return player.gold >= gps


func _find_stake_key(kind: String) -> String:
	if not is_instance_valid(player):
		return ""
	for raw in player.inventory:
		var key := str(raw)
		var item := ItemDB.find(key)
		if item.is_empty():
			continue
		if kind == "ingot" and str(item.get("type", "")) == "Ingot":
			return key
		if kind == "potion" and str(item.get("quality", "")) == "Potion":
			return key
	return ""


func _stake_amount(kind: String) -> float:
	var ws := _ws_script()
	if ws == null:
		return 0.0
	return float(ws.archmage_stake(kind))


func _do_stake(kind: String) -> void:
	var bus := get_node_or_null("/root/WorldBus")
	if bus == null or bus.state == null or not is_instance_valid(player):
		return
	var am: Dictionary = bus.state.get_archmage(Game.hero_race)
	if am.is_empty():
		return
	if float(am.get("power", 0.0)) >= 100.0:
		_status_label.text = tr("Маг не возьмёт больше.")
		return
	var amount := _stake_amount(kind)
	if amount <= 0.0:
		_status_label.text = tr("Ставка не настроена.")
		return
	if kind == "gold":
		var gps := 100
		var ws := _ws_script()
		if ws != null:
			gps = int(ws.archmage_gold_per_stake())
		if player.gold < gps:
			_status_label.text = tr("Не хватает золота.")
			return
		player.gold -= gps
	else:
		var key := _find_stake_key(kind)
		if key == "":
			_status_label.text = tr("Нечего отдавать.")
			return
		player.remove_item(key)
	var tier_delta: int = bus.state.add_archmage_power(Game.hero_race, amount)
	SoundDB.play(6)
	if tier_delta > 0:
		_status_label.text = tr("Маг окреп (ступень +%d)." % tier_delta)
	elif tier_delta < 0:
		_status_label.text = tr("Маг слабеет.")
	else:
		_status_label.text = tr("Плата принята.")
	_last_tier = int(bus.state.get_archmage(Game.hero_race).get("tier", _last_tier))
	_refresh()
	inventory_changed.emit()


func _on_stake_ingot() -> void:
	_do_stake("ingot")


func _on_stake_gold() -> void:
	_do_stake("gold")


func _on_stake_potion() -> void:
	_do_stake("potion")


func _input(event: InputEvent) -> void:
	if UiKit.esc_pressed(event):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	UiKit.restore_focus(_previous_focus)
	closed.emit()
	queue_free()
