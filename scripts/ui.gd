extends CanvasLayer
class_name GameUI

@onready var spell_grid: GridContainer = $BottomPanel/SpellPanel/SpellGrid
@onready var bottom_panel: Control = $BottomPanel
@onready var spell_panel: Control = $BottomPanel/SpellPanel
@onready var pause_label: Label = $PauseLabel
@onready var coords_label: Label = $CoordsLabel
@onready var minimap_rect: ColorRect = $MinimapPanel/MinimapMargin/MinimapRect
@onready var hud_gold_label: Label = $HudSide/GoldRow/GoldLabel
@onready var hud_cmd_row: HBoxContainer = $HudSide/HudCmdRow

var show_coords := GameConfig.geti("debug", "show_coords") != 0
var cmd_buttons: Array = []
var _stats_toggle_btn: Button = null

var minimap_camera: Camera2D
var alm_map = null
var player: Player

var minimap_image: Image
var minimap_texture: ImageTexture
var _minimap_size := Vector2.ZERO
var _minimap_timer := 0.0
const MINIMAP_INTERVAL := 0.25

func setup_ui(p: Player):
	player = p

	_apply_hud_theme()
	_setup_spells()
	refresh_spell_book()

	var gold_icon := get_node_or_null("HudSide/GoldRow/GoldIcon") as TextureRect
	if gold_icon != null:
		var gp := LootIcons.gold_icon()
		if gp != "":
			gold_icon.texture = load(gp)

	alm_map = get_tree().get_first_node_in_group("alm_map")

	_setup_minimap()
	_setup_action_buttons()
	_layout_panels()
	get_tree().root.size_changed.connect(_layout_panels)
	_update_gold(int(player.gold) if player != null else 0)
	_update_bottom_panel_visibility()

## Адаптивная раскладка: правая панель закреплена якорями справа в main.tscn,
## нижние панели (магия/инвентарь) — по центру игрового окна любого разрешения.
func _layout_panels() -> void:
	_update_bottom_panel_visibility()

# Панель заклинаний с иконками
const SPELL_CELL := 36              # ячейка магии = spellback.bmp (36x36)
const SPELL_COLS := 12              # колонок в книге (как сетка 12 в tscn)
const SPHERE_RU := {"Fire": "Огонь", "Water": "Вода", "Air": "Воздух",
	"Earth": "Земля", "Astral": "Астрал"}
var spell_buttons: Array = []       # ВСЕ ячейки (включая пустые квадратики)
var _spell_buttons_filled: Array = []  # только ячейки с заклинаниями (аляйно с names)
## заклинание -> последнее показанное ЧИСЛО секунд кулдауна. Ключ нужен,
## чтобы не трогать узлы каждый кадр: пока целое число не изменилось,
## картинка та же.
var _cd_shown: Dictionary = {}
var spells_visible: bool = true

func _setup_spells():
	if not spell_grid:
		print("WARNING: SpellGrid not found, skipping spell setup")
		return
	spell_grid.columns = SPELL_COLS
	spell_grid.add_theme_constant_override("h_separation", 2)
	spell_grid.add_theme_constant_override("v_separation", 2)

## Перестроить книгу магии: всегда 2 ряда по 12 ячеек = 24 книжных заклинания
## (порядок docs/rom2-ref/spells.txt). Слот 1 (1-й ряд, левая ячейка) … слот 24
## (2-й ряд, 12-я ячейка). Иконка каждой магии — каноничная иконка из книги
## (assets/spells/spell_NN.png, нарезаны из spellbook.bmp). Выучено — иконка +
## подсказка с названием; не выучено — пустой квадрат spellback с подсказкой,
## какая магия здесь учится.
func refresh_spell_book() -> void:
	if not is_instance_valid(player):
		return
	for b in spell_buttons:
		if is_instance_valid(b):
			b.queue_free()
	spell_buttons.clear()
	_spell_buttons_filled.clear()
	_spell_button_names.clear()
	_cd_shown.clear()

	# Каноничная таблица из 24 книжных заклинаний: порядок = порядок иконок
	# assets/spells/spell_NN.png (нарезаны из spellbook.bmp, слот книги = индекс)
	var slots: Array = []
	for i in range(SpellDB.BOOK_SPELLS.size()):
		slots.append({
			"name": str(SpellDB.BOOK_SPELLS[i]),
			"icon": SpellDB.book_icon_path(i),
		})
	# Прочие выученные заклинания (их дают Книги Сфер — напр. Curse/Slow/Light)
	# идут следом за каноничными 24, с иконкой свитка из базы.
	for name in player.known_spells:
		if SpellDB.book_index(str(name)) < 0:
			var ch := player.spell_charges(str(name))
			if (player.has_mana and ch == -1) or (not player.has_mana and ch > 0):
				slots.append({"name": str(name), "icon": SpellDB.icon_of(str(name))})

	for s in slots:
		var name: String = str(s["name"])
		var ch := player.spell_charges(name)
		var known: bool = (player.has_mana and ch == -1) or (not player.has_mana and ch > 0)
		_make_spell_cell(name, str(s["icon"]), known)

## Ячейка книги: StyleBoxFlat с цветной полосой стихии снизу; выучено — иконка;
## не выучено — приглушённый border. Вместо spellback.bmp — кастомный стиль.
func _make_spell_cell(name: String, icon: String, known: bool) -> void:
	var spell := SpellDB.get_spell(name)
	var title := str(spell.get("ru", name))
	var sphere_name := SpellDB.sphere_of(name)
	var sphere := str(SPHERE_RU.get(sphere_name, sphere_name))
	var charges := player.spell_charges(name)
	var mana := SpellDB.mana_cost(name)
	var sphere_color: Color = UiKit.SPHERE_COLORS.get(sphere_name, Color(0.5, 0.5, 0.5))
	var border_base := UiTheme.PANEL_EDGE.darkened(0.45)

	if not known:
		# Пустой слот книги: приглушённый border цвета стихии
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(SPELL_CELL, SPELL_CELL)
		var style := StyleBoxFlat.new()
		style.bg_color = UiTheme.BG_DEEP
		style.border_color = sphere_color.darkened(0.5)
		style.set_border_width_all(1)
		style.set_corner_radius_all(UiTheme.RADIUS_SLOT)
		cell.add_theme_stylebox_override("panel", style)
		cell.tooltip_text = "%s\nСфера: %s\n(не выучено — выучите Книгой Магии)" % [title, sphere]
		spell_grid.add_child(cell)
		spell_buttons.append(cell)
		return

	var b := Button.new()
	b.custom_minimum_size = Vector2(SPELL_CELL, SPELL_CELL)
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL

	# Стиль ячейки: тёмный фон + цветной border стихии снизу (2px)
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.SLOT_BG
	style.set_border_width_all(UiTheme.BORDER_HAIRLINE)
	style.set_border_width(SIDE_BOTTOM, 2)
	style.border_color = sphere_color.lerp(border_base, 0.4)
	style.set_corner_radius_all(UiTheme.RADIUS_SLOT)
	style.set_content_margin_all(UiTheme.SPACE_1)
	b.add_theme_stylebox_override("normal", style)

	var hover_style := style.duplicate()
	hover_style.border_color = sphere_color
	hover_style.bg_color = UiTheme.PANEL_INNER.lightened(0.08)
	b.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := style.duplicate()
	pressed_style.bg_color = UiTheme.BG_DEEP
	b.add_theme_stylebox_override("pressed", pressed_style)

	# Иконка нужной магии из каталога assets/spells
	if icon != "":
		var ic := TextureRect.new()
		ic.texture = load(icon)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.set_anchors_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 3.0
		ic.offset_top = 3.0
		ic.offset_right = -3.0
		ic.offset_bottom = -3.0
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)

	# Тултип: сфера, стоимость, урон/лечение, радиус, длительность эффектов
	b.tooltip_text = _spell_tooltip(name, title, sphere, charges, mana)

	# Число зарядов свитка в ячейке (чётко читается поверх иконки)
	if charges > 0:
		var lbl := Label.new()
		lbl.text = str(charges)
		lbl.add_theme_font_size_override("font_size", UiTheme.FONT_MICRO)
		lbl.add_theme_color_override("font_color", UiTheme.ACCENT)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		lbl.add_theme_constant_override("outline_size", 3)
		lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		lbl.offset_left = -18.0
		lbl.offset_top = -17.0
		lbl.offset_right = -1.0
		lbl.offset_bottom = -1.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(lbl)

	b.pressed.connect(func(sn: String = name): _cast_spell_button(sn))
	spell_grid.add_child(b)
	spell_buttons.append(b)
	_spell_buttons_filled.append(b)
	_spell_button_names.append(name)
	# Метка обратного отсчёта кулдауна.
	var cd := Label.new()
	cd.name = "Cooldown"
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd.add_theme_font_size_override("font_size", UiTheme.FONT_SUBHEAD)
	cd.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	cd.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	cd.add_theme_constant_override("outline_size", 4)
	cd.visible = false
	b.add_child(cd)
	# Иконку запоминаем, чтобы гасить только её, а не кнопку целиком
	if icon != "":
		b.set_meta("icon", b.get_child(0))
	_set_cooldown_visual(b, 0.0, SpellDB.cooldown_of(name))


## Обновить вид клетки под текущим кулдауном: left секунд, либо 0 = готово.
## Работает и для отрицательного total (неизвестно), тогда total = 0.
func _set_cooldown_visual(b: Button, left: float, total: float) -> void:
	if not is_instance_valid(b):
		return
	var cd := b.get_node_or_null("Cooldown") as Label
	var on := left > 0.0
	if cd != null:
		cd.visible = on
		# Целое число секунд: «3» читается как «осталось 3 секунды», а «2.7»
		# мигает и не говорит ничего. Показываем ceil, чтобы не показывать 0
		# при положительном остатке.
		cd.text = str(int(ceil(left))) if on else ""
	var icon_node := b.get_meta("icon") as CanvasItem
	if icon_node != null:
		# Плавное гашение по мере восстановления: чем меньше осталось, тем
		# светлее иконка. Прыжок из тёмной в светлую раз в 3 секунды читается
		# как «сломанная кнопка», а не как «готово».
		var t := 0.0
		if total > 0.0:
			t = clampf(left / total, 0.0, 1.0)
		icon_node.modulate = Color(1, 1, 1, 1.0 - 0.65 * t)


## Тултип заклинания. Раньше показывал только имя/сферу/заряды/ману —
## было невозможно понять, что заклинание делает и насколько оно далеко.
func _spell_tooltip(name: String, title: String, sphere: String, charges: int, mana: int) -> String:
	var spell := SpellDB.get_spell(name)
	var lines: Array = [title, "Сфера: " + sphere]
	if charges > 0:
		lines.append("Зарядов: %d" % charges)
	elif player.has_mana:
		lines.append("Мана: %d" % mana)

	# Урон или лечение с учётом силы магии героя
	var base := int(spell.get("damage", 0))
	if base > 0:
		lines.append("Урон: %d" % Game.spell_damage(player, name, SpellDB.sphere_of(name), base))
	elif base < 0:
		lines.append("Лечение: %d" % Game.spell_damage(player, name, SpellDB.sphere_of(name), -base))

	var area := float(spell.get("area", 0))
	if area > 0.0:
		lines.append("Радиус: %.1f м" % (area / 32.0))
	var rng_range := float(spell.get("range", 0))
	if rng_range > 0.0:
		lines.append("Дальность: %.0f м" % (rng_range / 32.0))
	if SpellDB.cooldown_of(name) > 0.0:
		lines.append("Кулдаун: %.1f с" % SpellDB.cooldown_of(name))
	if SpellDB.cast_time_of(name) > 0.0:
		lines.append("Подготовка: %.2f с" % SpellDB.cast_time_of(name))

	var eff := SpellDB.effects_of(name)
	if not eff.is_empty():
		lines.append("Эффекты: " + ", ".join(_effect_labels(eff)))
	return "\n".join(lines)


## Человеческие названия эффектов для тултипа.
func _effect_labels(effects: Array) -> Array:
	var out: Array = []
	for e in effects:
		var m := str((e as Dictionary).get("type", ""))
		var dur := float((e as Dictionary).get("duration", 0.0))
		var suffix := " (%.0f с)" % dur if dur > 0.0 else ""
		match m:
			"shield": out.append("щит %d%s" % [int((e as Dictionary).get("amount", 0)), suffix])
			"resist": out.append("сопротивление %s +%d%s" % [str((e as Dictionary).get("sphere", "")), int((e as Dictionary).get("amount", 0)), suffix])
			"bless": out.append("благословение%s" % suffix)
			"haste": out.append("ускорение x%.2f%s" % [float((e as Dictionary).get("mult", 1.0)), suffix])
			"slow": out.append("замедление x%.2f%s" % [float((e as Dictionary).get("mult", 1.0)), suffix])
			"curse": out.append("проклятие%s" % suffix)
			"invisibility": out.append("невидимость%s" % suffix)
			"vision": out.append("ослепление%s" % suffix)
			"vampirism": out.append("вампиризм %d%%" % int(float((e as Dictionary).get("ratio", 0.0)) * 100.0))
			"dot": out.append("яд %d/с%s" % [int((e as Dictionary).get("dps", 0)), suffix])
			"raise": out.append("поднимает труп")
			_: out.append(m)
	return out

## Клик по заклинанию в книге: как у разработчиков — входим в режим
## прицеливания (анимированный курсор cast/), магия улетает только по клику
## на цель. Мана/заряд при этом НЕ списываются до попадания по цели.
func _cast_spell_button(name: String) -> void:
	if not is_instance_valid(player):
		return
	_begin_spell_targeting(name)

# --- Прицеливание (свиток МАГА или заклинание книги): курсор cast/ ---

var _cast_cursor: Sprite2D = null
var _cast_frames: Array = []
var _cast_frame_t := 0.0
var _cast_frame_i := 0
var _invisible_tex: ImageTexture = null
var _scroll_hint: Label = null
var _error_hint_timer: SceneTreeTimer = null

## Выбрано заклинание из книги: ждём цели. Книга закрывается, курсор-cast следует
## за мышью. Выбор отменяется ПКМ/ESC, назначение на цифру — Ctrl+1..9.
func _begin_spell_targeting(name: String) -> void:
	if not is_instance_valid(player) or not player.can_cast(name):
		return
	_cancel_targeting()
	Game.pending_spell = {"name": name}
	Game._spell_targeting_frame = Engine.get_process_frames()
	spells_visible = false              # книга закрывается, остаётся курсор-прицел
	_update_bottom_panel_visibility()
	_ensure_cast_cursor()
	_hide_os_cursor()
	_update_targeting_hint(name, true)
	SoundDB.play(7)  # ibook

## Заклинание применено по цели (вызывает Game). Сброс режима + обновление книги.
func _finish_spell_targeting() -> void:
	_cancel_targeting()
	refresh_spell_book()
	_update_bottom_panel_visibility()
	if is_instance_valid(_inventory_panel) and _inventory_panel.has_method("_refresh_stats"):
		_inventory_panel._refresh_stats()

## Быстрая клавиша 1..9: вход в прицеливание назначенного заклинания.
func _quick_cast(spell: String) -> void:
	if not is_instance_valid(player) or not player.can_cast(spell):
		print("Быстрый вызов недоступен: " + spell)
		return
	_begin_spell_targeting(spell)

## Ctrl+N: выбранная магия назначена на цифровую клавишу (подпись в книге +
## подсказка). Выбранное заклинание остаётся активным для прицеливания.
func _notify_hotbar_assigned(slot: int, spell: String) -> void:
	refresh_spell_book()
	if _scroll_hint != null and is_instance_valid(_scroll_hint):
		_scroll_hint.text = "«%s» назначена на клавишу %d (жмите %d для прицеливания)" % [
			str(SpellDB.get_spell(spell).get("ru", spell)), slot + 1, slot + 1]
		_scroll_hint.visible = true

## Ошибка выбора цели (заклинание остаётся активным): показываем на
## подсказке, затем возвращаем обычный текст подсказки.
## Ctrl+N: предмет под курсором назначен на цифровую клавишу (зелье/свиток).
func _notify_item_assigned(slot: int, item_key: String) -> void:
	if _scroll_hint == null or not is_instance_valid(_scroll_hint):
		return
	var item := ItemDB.find(item_key)
	var title := str(item.get("name_ru", item_key))
	_scroll_hint.text = "<%s> быстрая клавиша %d (нажмите %d для применения)" % [
		title, slot + 1, slot + 1]
	_scroll_hint.visible = true


func _flash_targeting_error(msg: String) -> void:
	if _scroll_hint != null and is_instance_valid(_scroll_hint):
		_scroll_hint.text = msg
		_scroll_hint.visible = true
	var timer := get_tree().create_timer(1.8)
	_error_hint_timer = timer
	timer.timeout.connect(_on_error_hint_timeout)

func _on_error_hint_timeout() -> void:
	if not Game.pending_spell.is_empty():
		_update_targeting_hint(str(Game.pending_spell.get("name", "")), true)
	elif not Game.pending_scroll.is_empty():
		_update_targeting_hint(str(Game.pending_scroll.get("spell", "")), true)
	elif _scroll_hint != null and is_instance_valid(_scroll_hint):
		_scroll_hint.visible = false

## Маг дважды кликнул свиток в складе: ждём выбора цели (курсор-cast).
func _begin_scroll_targeting(item_key: String) -> void:
	var spell := SpellDB.spell_from_scroll(item_key)
	if spell == "" or not is_instance_valid(player):
		return
	Game.pending_scroll = {"spell": spell, "item_key": item_key}
	_ensure_cast_cursor()
	_hide_os_cursor()
	_update_targeting_hint(spell, true)
	SoundDB.play(7)  # ibook

## Свиток применён по цели (вызывает Game). Сброс режима + обновление книги.
func _finish_scroll_targeting() -> void:
	_cancel_targeting()
	refresh_spell_book()
	_update_bottom_panel_visibility()
	if is_instance_valid(_inventory_panel) and _inventory_panel.has_method("_refresh_stats"):
		_inventory_panel._refresh_stats()

## Отмена любого прицеливания (свиток/магия): цель НЕ тратится, курсор-прицел
## снимается, системный курсор возвращается.
func _cancel_targeting() -> void:
	Game.pending_scroll = {}
	Game.pending_spell = {}
	Game._spell_targeting_frame = -1
	_restore_os_cursor()
	if _cast_cursor != null and is_instance_valid(_cast_cursor):
		_cast_cursor.visible = false
	if _scroll_hint != null and is_instance_valid(_scroll_hint):
		_scroll_hint.visible = false

func _ensure_cast_cursor() -> void:
	if _cast_cursor != null and is_instance_valid(_cast_cursor):
		return
	_cast_cursor = Sprite2D.new()
	_cast_cursor.name = "CastCursor"
	_cast_cursor.visible = false
	add_child(_cast_cursor)
	var dir := DirAccess.open("res://assets/cursors/cast")
	if dir == null:
		return
	dir.list_dir_begin()
	var names: Array = []
	var fn := dir.get_next()
	while fn != "":
		if fn.begins_with("sprites-") and fn.ends_with(".png"):
			names.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	names.sort()
	_cast_frames.clear()
	for nm in names:
		var tex: Variant = load("res://assets/cursors/cast/" + nm)
		if tex != null:
			_cast_frames.append(tex)
	_cast_frame_t = 0.0
	_cast_frame_i = 0

## Скрыть системный курсор: рисуем свой (анимированный) поверх.
func _hide_os_cursor() -> void:
	if _invisible_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, Color(0, 0, 0, 0))
		_invisible_tex = ImageTexture.create_from_image(img)
	Input.set_custom_mouse_cursor(_invisible_tex, Input.CURSOR_ARROW, Vector2.ZERO)

func _restore_os_cursor() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)

## Подсказка над нижними панелями: что применить выбранным свитком/заклинанием
## и как отменить/назначить быструю клавишу (как у разработчиков).
func _update_targeting_hint(spell: String, on: bool) -> void:
	if _scroll_hint == null:
		_scroll_hint = Label.new()
		_scroll_hint.name = "ScrollHint"
		_scroll_hint.theme_type_variation = &"HudHint"
		_scroll_hint.add_theme_font_size_override("font_size", UiTheme.FONT_SUBHEAD)
		_scroll_hint.add_theme_color_override("font_color", UiTheme.ACCENT)
		_scroll_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_scroll_hint.add_theme_constant_override("outline_size", 4)
		_scroll_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_scroll_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_scroll_hint)
		_scroll_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_scroll_hint.offset_top = -66.0
		_scroll_hint.offset_bottom = -42.0
	_scroll_hint.visible = on
	if not on:
		return
	# Подсказка по цели берётся из поля target базы (enemy/ally/point/self),
	# а не из kind — у debuff/raise цель враг, у wall/self — точка/себя.
	var target_kind := SpellDB.target_of(spell)
	var dir_text := ""
	match target_kind:
		"enemy":
			dir_text = "ВРАГА"
		"point":
			dir_text = "ВРАГА ИЛИ ТОЧКУ"
		"self":
			dir_text = "СЕБЯ"
		_:
			dir_text = "СЕБЯ ИЛИ СОЮЗНИКА"
	_scroll_hint.text = ("Примените «%s» на %s (ПКМ/ESC — отмена; Ctrl+1..9 — быстрая клавиша)"
		% [str(SpellDB.get_spell(spell).get("ru", spell)), dir_text])

func _apply_hud_theme() -> void:
	var theme := UiTheme.app_theme()
	theme.set_stylebox("normal", "Button", UiKit.button_style(
		UiTheme.PANEL_INNER, UiTheme.PANEL_EDGE.darkened(0.3),
		UiTheme.BORDER_HAIRLINE, UiTheme.RADIUS_SLOT, UiTheme.SPACE_1))
	theme.set_stylebox("hover", "Button", UiKit.button_style(
		UiTheme.PANEL_INNER.lightened(0.12), UiTheme.ACCENT_DIM,
		UiTheme.BORDER_HAIRLINE, UiTheme.RADIUS_SLOT, UiTheme.SPACE_1))
	theme.set_stylebox("pressed", "Button", UiKit.button_style(
		UiTheme.BG_DEEP, UiTheme.ACCENT_DIM,
		UiTheme.BORDER_HAIRLINE, UiTheme.RADIUS_SLOT, UiTheme.SPACE_1))
	theme.set_stylebox("focus", "Button", UiKit.button_style(
		UiTheme.TRANSPARENT, UiTheme.ACCENT,
		UiTheme.BORDER_FOCUS, UiTheme.RADIUS_SLOT, UiTheme.SPACE_1))
	UiKit.add_button(theme, &"HudCmd",
		UiTheme.PANEL_INNER, UiTheme.PANEL_EDGE.darkened(0.3),
		UiTheme.PANEL_INNER.lightened(0.12), UiTheme.ACCENT_DIM,
		UiTheme.RADIUS_SLOT, UiTheme.SPACE_1)
	UiKit.add_button(theme, &"HudCmdActive",
		UiTheme.PANEL_INNER.lightened(0.16), UiTheme.ACCENT,
		UiTheme.PANEL_INNER.lightened(0.20), UiTheme.ACCENT,
		UiTheme.RADIUS_SLOT, UiTheme.SPACE_1)
	theme.set_color("font_color", &"HudCmd", UiTheme.TEXT)
	theme.set_color("font_hover_color", &"HudCmd", UiTheme.ACCENT)
	theme.set_color("font_pressed_color", &"HudCmd", UiTheme.ACCENT)
	theme.set_color("font_focus_color", &"HudCmd", UiTheme.ACCENT)
	theme.set_color("font_color", &"HudCmdActive", UiTheme.BG_DEEP)
	theme.set_color("font_hover_color", &"HudCmdActive", UiTheme.BG_DEEP)
	theme.set_color("font_pressed_color", &"HudCmdActive", UiTheme.BG_DEEP)
	theme.set_color("font_focus_color", &"HudCmdActive", UiTheme.BG_DEEP)
	theme.set_font_size("font_size", &"HudCmd", UiTheme.FONT_MICRO)
	theme.set_font_size("font_size", &"HudCmdActive", UiTheme.FONT_MICRO)
	UiKit.add_label(theme, &"HudHint", UiTheme.ACCENT, UiTheme.FONT_MICRO)
	if is_instance_valid($HudSide):
		$HudSide.theme = theme
	if is_instance_valid(bottom_panel):
		bottom_panel.theme = theme
	if is_instance_valid(spell_panel):
		spell_panel.theme = theme


func _setup_action_buttons():
	if not is_instance_valid(hud_cmd_row):
		return
	# Компакт-ряд у миникарты. Статы теперь в инвентаре — кнопки «Статы» нет.
	var inv_btn := Button.new()
	inv_btn.name = "InvBtn"
	inv_btn.text = "Инв."
	inv_btn.theme_type_variation = &"HudCmd"
	inv_btn.custom_minimum_size = Vector2(48, 28)
	inv_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_btn.focus_mode = Control.FOCUS_ALL
	inv_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	inv_btn.tooltip_text = "Инвентарь (I)"
	inv_btn.pressed.connect(open_inventory_panel)
	hud_cmd_row.add_child(inv_btn)

	var cmd_labels := ["След.", "Атак.", "Охр.", "Стоп"]
	var cmd_modes := ["follow", "attack", "guard", "stop"]
	for i in range(cmd_labels.size()):
		var b := Button.new()
		b.name = "Cmd%d" % i
		b.text = cmd_labels[i]
		b.custom_minimum_size = Vector2(48, 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.theme_type_variation = &"HudCmd"
		b.focus_mode = Control.FOCUS_ALL
		b.tooltip_text = cmd_labels[i]
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hud_cmd_row.add_child(b)
		cmd_buttons.append(b)
		b.pressed.connect(func(): _set_action_mode(cmd_modes[i]))
	coords_label.visible = false
	_set_action_mode(Game.action_mode if Game.action_mode != "" else "follow")

func _set_action_mode(mode: String):
	for i in range(cmd_buttons.size()):
		cmd_buttons[i].theme_type_variation = &"HudCmd"
		cmd_buttons[i].set_pressed_no_signal(false)

	var active := -1
	match mode:
		"follow":
			active = 0
			Game.action_mode = "follow"
		"attack":
			active = 1
			Game.action_mode = "attack"
		"guard":
			active = 2
			Game.action_mode = "guard"
		"stop":
			Game.action_mode = "none"
	if active >= 0 and active < cmd_buttons.size():
		cmd_buttons[active].theme_type_variation = &"HudCmdActive"
		cmd_buttons[active].set_pressed_no_signal(true)

func _toggle_stats_view():
	# Статы теперь в инвентаре — HUD-toggle не нужен.
	pass

# --- Карточки наведения (стилизованные, через UiKit.make_hover_card) ---------

var _item_card: PanelContainer = null
var _slot_card: PanelContainer = null

func _ensure_card(_kind: String) -> PanelContainer:
	var card := UiKit.make_hover_card(300.0)
	add_child(card)
	var theme := UiKit.base_theme()
	UiKit.add_hover_card_styles(theme)
	card.theme = theme
	return card

## Строки карточки предмета: имя, качество/материал/тип, боевые статы, вес/цена.
func _item_card_lines(item: Dictionary) -> Array:
	var lines: Array = [str(item.get("name_ru", item.get("key", "Предмет")))]
	var sub: Array[String] = []
	for f in ["quality", "material", "type"]:
		var v := str(item.get(f, ""))
		if v != "" and v != "None":
			sub.append(v)
	if not sub.is_empty():
		lines.append(" · ".join(sub))
	var stats: Array[String] = []
	var dmin := int(item.get("damage_min", 0))
	var dmax := int(item.get("damage_max", 0))
	if dmin > 0 or dmax > 0:
		stats.append("Урон %d–%d" % [dmin, dmax])
	var th := int(item.get("to_hit", 0))
	if th != 0:
		stats.append("Атака +%d" % th)
	var df := int(item.get("defence", 0))
	if df > 0:
		stats.append("Защита %d" % df)
	var ab := int(item.get("absorption", 0))
	if ab > 0:
		stats.append("Поглощение %d" % ab)
	var mc := int(item.get("magcap", 0))
	if mc > 0:
		stats.append("Магия %d" % mc)
	if not stats.is_empty():
		lines.append(" · ".join(stats))
	lines.append("Вес %.1f · Цена %d" % [float(item.get("weight", 0.0)), int(item.get("price", 0))])
	return lines

## Карточка предмета на ячейке инвентаря (мышь + фокус).
func _attach_item_card(cell: Control, item: Dictionary) -> void:
	if not is_instance_valid(cell) or item.is_empty():
		return
	var icon_path := str(item.get("icon", ""))
	var qcolor := UiKit.quality_color(str(item.get("quality", "")))
	cell.mouse_entered.connect(func():
		if _item_card == null:
			_item_card = _ensure_card("item")
		UiKit.show_hover_card(_item_card, _item_card_lines(item),
			cell.global_position, _world_bounds(), icon_path, qcolor))
	cell.mouse_exited.connect(func():
		if _item_card != null:
			UiKit.hide_hover_card(_item_card))
	cell.focus_entered.connect(func():
		if _item_card == null:
			_item_card = _ensure_card("item")
		UiKit.show_hover_card(_item_card, _item_card_lines(item),
			cell.global_position, _world_bounds(), icon_path, qcolor))
	cell.focus_exited.connect(func():
		if _item_card != null:
			UiKit.hide_hover_card(_item_card))

## Карточка слота экипировки: читает надетый предмет в момент наведения.
func _attach_slot_card(cell: Control, slot: String) -> void:
	if not is_instance_valid(cell):
		return
	cell.mouse_entered.connect(func(): _show_slot_card(cell, slot))
	cell.mouse_exited.connect(func(): _hide_slot_card())
	cell.focus_entered.connect(func(): _show_slot_card(cell, slot))
	cell.focus_exited.connect(func(): _hide_slot_card())

func _show_slot_card(cell: Control, slot: String) -> void:
	if not is_instance_valid(player):
		return
	var key := str(player.equipped.get(slot, ""))
	if key == "":
		_hide_slot_card()
		return
	var it := ItemDB.find(key)
	if it.is_empty():
		_hide_slot_card()
		return
	if _slot_card == null:
		_slot_card = _ensure_card("slot")
	var lines: Array = _item_card_lines(it)
	lines.append("Слот: %s (клик — снять)" % ItemDB.slot_title(slot))
	var icon_path := str(it.get("icon", ""))
	var qcolor := UiKit.quality_color(str(it.get("quality", "")))
	UiKit.show_hover_card(_slot_card, lines, cell.global_position, _world_bounds(), icon_path, qcolor)

func _hide_slot_card() -> void:
	if _slot_card != null:
		UiKit.hide_hover_card(_slot_card)
# --- Тултипы мира: hover + Alt -----------------------------------------------
## GDD 06.10: hover 0.6 с → база (имя+фракция / здание / лут);
## Alt → полная карточка юнита (HP/бой/резисты). Hold ЛКМ не используется.

const WORLD_HOVER_DELAY := 0.6
var _world_card: PanelContainer = null
var _world_hover_key := ""
var _world_hover_time := 0.0
var _world_card_shown := false
var _world_card_alt := false
var _world_hover_unit: Node2D = null


func _world_bounds() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(1280, 800)
	return vp.get_visible_rect().size


func _update_world_tooltip(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if is_editor_open():
		_reset_world_tooltip()
		return

	var target: Array = _world_hover_target()
	var key := str(target[0])
	var alt := Input.is_key_pressed(KEY_ALT)

	if key == "":
		_reset_world_tooltip()
		return

	if key != _world_hover_key:
		_world_hover_key = key
		_world_hover_time = 0.0
		_world_card_shown = false
		_world_card_alt = alt
		if _world_card != null and _world_card.visible:
			UiKit.hide_hover_card(_world_card)
		return

	_world_hover_time += delta
	if _world_hover_time < WORLD_HOVER_DELAY:
		return

	if _world_card_shown and alt == _world_card_alt:
		return
	# Alt переключил режим — пересобрать карточку
	if _world_card_shown:
		_world_card_shown = false
		if _world_card != null:
			UiKit.hide_hover_card(_world_card)
	if _world_card == null:
		_world_card = _ensure_card("world")

	var lines: Array = target[1]
	var is_unit := key.begins_with("u")
	if is_unit and alt:
		lines = _unit_tooltip_full(target)
	_world_card_alt = alt
	UiKit.show_hover_card(_world_card, lines,
		get_viewport().get_mouse_position(), _world_bounds())
	_world_card_shown = true


func _reset_world_tooltip() -> void:
	_world_hover_time = 0.0
	_world_hover_key = ""
	_world_card_shown = false
	_world_card_alt = false
	if _world_card != null and _world_card.visible:
		UiKit.hide_hover_card(_world_card)


## Полная карточка юнита (Alt): HP, урон, броня, сопротивления.
func _unit_tooltip_full(target: Array) -> Array:
	var lines: Array = target[1].duplicate()
	var e: Node2D = _world_hover_unit
	if e == null or not is_instance_valid(e):
		return lines
	var hp := 0
	if "max_hp" in e:
		hp = int(e.max_hp)
	elif "hp_max" in e:
		hp = int(e.hp_max)
	var cur := int(e.current_hp) if "current_hp" in e else hp
	if hp > 0:
		lines.append(tr("Здоровье: %d/%d") % [cur, hp])
	if e.has_method("get_attack"):
		lines.append(tr("Атака: %d") % int(e.call("get_attack")))
	if e.has_method("get_defense"):
		lines.append(tr("Броня: %d") % int(e.call("get_defense")))
	if e.has_method("get_absorption"):
		lines.append(tr("Поглощение: %d") % int(e.call("get_absorption")))
	var set_name := str(e.anim_set) if "anim_set" in e else ""
	if set_name != "":
		var res: Array[String] = []
		for sphere in ["fire", "water", "air", "earth", "astral"]:
			var r := 0
			if e.has_method("get_protection_" + sphere):
				r = int(e.call("get_protection_" + sphere))
			elif e.has_method("resist_of"):
				r = int(UnitDB.resist_of(set_name, sphere))
			if r != 0:
				res.append("%s %d" % [sphere, r])
		if not res.is_empty():
			lines.append(tr("Сопротивление: ") + ", ".join(res))
	return lines


## Цель под курсором: [ключ, строки]. "" — цели нет.
## Юнит: ключ "u…", база — имя+фракция. Здание/лут — hover без Alt.
func _world_hover_target() -> Array:
	var world := player.get_global_mouse_position()
	_world_hover_unit = null
	for e in Game.enemies + Game.npcs:
		if is_instance_valid(e) and Game.unit_hit_rect(e).grow(8.0).has_point(world):
			_world_hover_unit = e
			return [_unit_hover_key(e), _unit_tooltip_lines(e)]
	if alm_map and alm_map.map_width > 0:
		var ts: int = 32
		if "tile_size" in alm_map:
			ts = maxi(1, int(alm_map.tile_size))
		var cell := Vector2i(int(world.x) / ts, int(world.y) / ts)
		var h := _structure_at_world(cell, world, ts)
		if not h.is_empty():
			return ["b%d" % int(h.get("type_id", -1)), _building_tooltip_lines(h)]
	for lb in get_tree().get_nodes_in_group("loot"):
		if is_instance_valid(lb) and lb is LootDrop \
				and lb.global_position.distance_to(world) < 28.0:
			return ["l%d" % lb.get_instance_id(), _loot_tooltip_lines(lb)]
	return ["", []]


## Здание: structure_at по клетке + соседние (футпринт 3×3 не всегда покрывает
## точку клика, если хитбокс шире одной клетки).
func _structure_at_world(cell: Vector2i, world: Vector2, ts: int) -> Dictionary:
	if alm_map == null or not alm_map.has_method("structure_at"):
		return {}
	var direct: Dictionary = alm_map.structure_at(cell)
	if not direct.is_empty():
		return direct
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var h: Dictionary = alm_map.structure_at(cell + Vector2i(dx, dy))
			if not h.is_empty():
				return h
	return {}


func _unit_hover_key(e: Node2D) -> String:
	return "u%d" % e.get_instance_id()


func _unit_tooltip_lines(e: Node2D) -> Array:
	var lines: Array = []
	var set_name := str(e.anim_set) if "anim_set" in e else ""
	var set_data := UnitDB.get_set(set_name)
	var name := str(set_data.get("desc", ""))
	if name == "":
		name = set_name.get_slice("/", 1) if "/" in set_name else set_name
	lines.append(name if name != "" else "Существо")
	lines.append(tr("Фракция: %s") % _faction_of_set(set_name))
	return lines
func _building_tooltip_lines(h: Dictionary) -> Array:
	var lines: Array = []
	var sid := int(h.get("type_id", -1))
	var name := StructureDB.display_name_by_id(sid) if sid >= 0 else str(h.get("picture", ""))
	lines.append(name if name != "" else "Здание")
	lines.append("Здание")
	return lines

func _loot_tooltip_lines(lb: LootDrop) -> Array:
	var lines: Array = ["Добыча"]
	var gold := 0
	var names: Array[String] = []
	for it in lb.items:
		if it is Dictionary:
			if it.has("gold"):
				gold += int(it.get("gold", 0))
			elif it.has("key"):
				var k := str(it.get("key", ""))
				names.append(str(ItemDB.find(k).get("name_ru", k)))
	if gold > 0:
		lines.append("Золото: %d" % gold)
	if not names.is_empty():
		lines.append("Предметы: %s" % ", ".join(names))
	if gold <= 0 and names.is_empty():
		lines.append("Пусто")
	return lines

## Фракция по набору анимаций юнита (см. §8.2 AGENTS.md).
func _faction_of_set(set_name: String) -> String:
	if set_name.begins_with("ork_mage"):
		return "Орды Огня"
	if set_name.begins_with("humans/"):
		return "Альянс Света"
	if set_name.begins_with("heroes/"):
		return "Герой"
	for k in ["orc", "goblin", "troll", "ogre"]:
		if k in set_name:
			return "Орды Огня"
	for k in ["skeleton", "zombie", "necromant", "ghost"]:
		if k in set_name:
			return "Пожинатели"
	if "druid" in set_name:
		return "Круг Друидов"
	return "Серые"

func _setup_minimap():
	# Защита от повторного вызова: раньше setup_ui вызывал это дважды
	# (напрямую и через _setup_spells) — создавался дубликат узла MinimapTex.
	if minimap_rect.get_node_or_null("MinimapTex") != null:
		return
	minimap_rect.color = Color(0, 0, 0, 0)  # MINIMAP transparent
	# TextureRect для миникарты: размер задаётся под рамку при отрисовке
	# (см. _draw_minimap), чтобы картинка не вылезала за MinimapRect.
	var tex_rect = TextureRect.new()
	tex_rect.name = "MinimapTex"
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	minimap_rect.add_child(tex_rect)
	minimap_image = null
	minimap_texture = null

## Точки юнитов двигаются, поэтому миникарта не полностью статична, но полный
## перебор всей карты каждый кадр (65k клеток на Beach) — лишний. Обновляем
## с фиксированным шагом.
func _update_minimap(delta: float) -> void:
	_minimap_timer -= delta
	if _minimap_timer <= 0.0:
		_minimap_timer = MINIMAP_INTERVAL
		_draw_minimap()

func _draw_minimap():
	if not alm_map or not is_instance_valid(player):
		return

	var mw: int = alm_map.map_width
	var mh: int = alm_map.map_height
	if mw == 0:
		return

	# Размер рисунка = высота MinimapRect (165px), квадрат чтобы не растягивать
	var msize: Vector2 = minimap_rect.size
	var h := int(msize.y)
	var w := h  # квадрат
	if h <= 0:
		return

	# Первый кадр или смена размера рамки — пересоздаём изображение/текстуру.
	var square_size := Vector2(w, h)
	if minimap_image == null or minimap_texture == null or _minimap_size != square_size:
		_minimap_size = square_size
		minimap_image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		minimap_texture = ImageTexture.create_from_image(minimap_image)
		var tex_rect := minimap_rect.get_node_or_null("MinimapTex")
		if tex_rect:
			tex_rect.offset_left = (msize.x - w) / 2.0
			tex_rect.offset_top = 0.0
			tex_rect.offset_right = tex_rect.offset_left + w
			tex_rect.offset_bottom = float(h)

	var ptx: int = int(player.global_position.x) / alm_map.tile_size
	var pty: int = int(player.global_position.y) / alm_map.tile_size
	var scale_x := float(w) / float(mw)
	var scale_y := float(h) / float(mh)

	minimap_image.fill(MINIMAP_BG)

	# Вся карта: цвета по типу клетки (CustomMap) или terrain (.alm)
	for ty in range(mh):
		for tx in range(mw):
			var color := _minimap_color_at(tx, ty)
			if color.a == 0.0:
				continue
			var sx := int(tx * scale_x)
			var sy := int(ty * scale_y)
			var ex := int((tx + 1) * scale_x)
			var ey := int((ty + 1) * scale_y)
			for py in range(sy, mini(ey + 1, h)):
				for px in range(sx, mini(ex + 1, w)):
					minimap_image.set_pixel(px, py, color)

	# Игрок (белая точка)
	var px := int(ptx * scale_x)
	var py := int(pty * scale_y)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var xx := px + dx; var yy := py + dy
			if xx >= 0 and xx < w and yy >= 0 and yy < h:
				minimap_image.set_pixel(xx, yy, MINIMAP_HERO)

	# Враги (красные точки)
	for enemy in Game.enemies:
		if is_instance_valid(enemy):
			var etx: int = int(enemy.global_position.x) / alm_map.tile_size
			var ety: int = int(enemy.global_position.y) / alm_map.tile_size
			var exx := int(etx * scale_x); var eyy := int(ety * scale_y)
			if exx >= 0 and exx < w and eyy >= 0 and eyy < h:
				minimap_image.set_pixel(exx, eyy, MINIMAP_ENEMY)

	# NPC (жёлтые = нейтральные, зелёные = союзники/стражи)
	for npc in Game.npcs:
		if is_instance_valid(npc):
			var ntx: int = int(npc.global_position.x) / alm_map.tile_size
			var nty: int = int(npc.global_position.y) / alm_map.tile_size
			var nxx := int(ntx * scale_x); var nyy := int(nty * scale_y)
			if nxx >= 0 and nxx < w and nyy >= 0 and nyy < h:
				var nc: Color = MINIMAP_NPC_CIV
				if "role" in npc and str(npc.role) == "guard":
					nc = MINIMAP_NPC_GUARD
				minimap_image.set_pixel(nxx, nyy, nc)

	# Здания (серые квадраты 2×2)
	if alm_map.has_method("structure_at") and alm_map.map_width > 0:
		for ty in range(0, mh, 4):
			for tx in range(0, mw, 4):
				var struct: Dictionary = alm_map.structure_at(Vector2i(tx, ty))
				if not struct.is_empty():
					var sx := int(tx * scale_x)
					var sy := int(ty * scale_y)
					for dy in range(0, 2):
						for dx in range(0, 2):
							var xx := sx + dx; var yy := sy + dy
							if xx >= 0 and xx < w and yy >= 0 and yy < h:
								minimap_image.set_pixel(xx, yy, MINIMAP_BUILDING)

	minimap_texture.update(minimap_image)
	var tex_rect2 := minimap_rect.get_node_or_null("MinimapTex")
	if tex_rect2:
		tex_rect2.texture = minimap_texture

# Цвета миникарты: игровые данные (биомы/юниты), не палитра UI-панелей.
const MINIMAP_NPC_GUARD := Color(0.2, 0.8, 0.2, 1.0)
const MINIMAP_NPC_CIV := Color(1.0, 0.85, 0.2, 1.0)
const MINIMAP_ENEMY := Color(1.0, 0.2, 0.2, 1.0)
const MINIMAP_BUILDING := Color(0.5, 0.45, 0.4, 1.0)
const MINIMAP_HERO := Color(1, 1, 1, 1)
const MINIMAP_BG := Color(0.03, 0.03, 0.04, 1.0)
const MINIMAP_CUSTOM := {  # MINIMAP biome colors
	1: Color(0.55, 0.35, 0.15, 1.0),    # MINIMAP soil
	2: Color(0.85, 0.80, 0.50, 1.0),    # MINIMAP sand
	3: Color(0.15, 0.35, 0.75, 1.0),    # MINIMAP water
	4: Color(0.45, 0.42, 0.40, 1.0),    # MINIMAP mountains
	5: Color(0.60, 0.50, 0.35, 1.0),    # MINIMAP road
	6: Color(0.30, 0.22, 0.12, 1.0),    # MINIMAP mud
	7: Color(0.45, 0.3, 0.2, 1.0),      # MINIMAP building
	8: Color(1.0, 0.85, 0.2, 1.0),      # MINIMAP spawn
	0: Color(0.25, 0.55, 0.25, 1.0),    # MINIMAP grass
}
const MINIMAP_ALM := {  # MINIMAP biome colors
	2: Color(0.15, 0.35, 0.75, 1.0),    # MINIMAP water
	1: Color(0.52, 0.48, 0.42, 1.0),    # MINIMAP mountains
	3: Color(0.7, 0.65, 0.55, 1.0),     # MINIMAP road
	4: Color(0.50, 0.35, 0.18, 1.0),    # MINIMAP soil
	5: Color(0.85, 0.70, 0.22, 1.0),    # MINIMAP sand
	6: Color(0.22, 0.15, 0.08, 1.0),    # MINIMAP mud
	0: Color(0.25, 0.55, 0.25, 1.0),    # MINIMAP grass
}

# Цвет клетки для миникарты: CustomMap -> тип (0-8), .alm -> terrain_type
func _minimap_color_at(tx: int, ty: int) -> Color:
	if alm_map is CustomMap:
		var t: int = alm_map.tile_id_at(Vector2i(tx, ty))
		if MINIMAP_CUSTOM.has(t):
			return MINIMAP_CUSTOM[t]
		return Color(0, 0, 0, 0)  # MINIMAP empty
	var t2: int = alm_map.cell_type_at(tx, ty)
	if MINIMAP_ALM.has(t2):
		return MINIMAP_ALM[t2]
	return MINIMAP_ALM[0]

func update_ui(p: Player, delta: float = 0.0):
	if not is_instance_valid(p):
		return
	_update_world_tooltip(delta)

	# Отладочные координаты: позиция героя, курсора, клетки, тайл и проходимость.
	if show_coords:
		var lines := "КООРДИНАТЫ\n"
		lines += "Герой: %d, %d px\n" % [int(p.global_position.x), int(p.global_position.y)]
		var mouse := get_viewport().get_mouse_position()
		var world := p.get_global_mouse_position() if p.has_method("get_global_mouse_position") else Vector2.ZERO
		lines += "Мышь: %d, %d px\n" % [int(mouse.x), int(mouse.y)]
		if alm_map:
			var ts: int = alm_map.tile_size
			var tc := Vector2i(int(p.global_position.x) / ts, int(p.global_position.y) / ts)
			var mc := Vector2i(int(world.x) / ts, int(world.y) / ts)
			lines += "Клетка героя: %d, %d\n" % [tc.x, tc.y]
			lines += "Клетка мыши: %d, %d\n" % [mc.x, mc.y]
			var walk_h: bool = alm_map.is_walkable_world(p.global_position)
			lines += "Проход героя: %s\n" % ("да" if walk_h else "НЕТ")
			var walk_m: bool = alm_map.is_walkable_world(world)
			lines += "Проход мыши: %s\n" % ("да" if walk_m else "НЕТ")
			if mc.x >= 0 and mc.y >= 0 and mc.x < alm_map.map_width and mc.y < alm_map.map_height:
				var t: int = alm_map.cell_type_at(mc.x, mc.y)
				# Горы и вода НЕПРОХОДИМЫ с 05.10 (WalkTable.walkable), раньше
				# здесь стояло «проходимо, медленно» — отладочный тултип врал.
				var names := ["Трава (tile1)", "Горы (tile2 — непроходимо)",
					"Вода (tile3 — непроходимо)", "Дорога (tile4)"]
				lines += "Тайл мыши: %s\n" % (names[t] if t >= 0 and t < names.size() else str(t))
				if not walk_m and alm_map.has_method("blocked_reason"):
					var reason: String = alm_map.call("blocked_reason", mc)
					if reason != "":
						lines += "Занято: %s\n" % reason
				if alm_map.has_method("flag_at_world"):
					var fl: int = alm_map.flag_at_world(world)
					lines += "Флаг: %d (0 зем/1 холм/2 вода/3 выс/4 барьер)\n" % fl
		coords_label.text = lines

	# Подсветка кнопок книги заклинаний: доступно/недостаточно маны или зарядов
	for i in range(_spell_buttons_filled.size()):
		var button = _spell_buttons_filled[i] as Button
		if button == null:
			continue
		if i < _spell_button_names.size():
			var sn: String = str(_spell_button_names[i])
			if player.can_cast(sn):
				button.modulate = Color.WHITE
				button.disabled = false
			else:
				button.modulate = Color(1, 1, 1, 0.45)
				button.disabled = true
		else:
			button.modulate = Color(1, 1, 1, 0.3)

	_update_minimap(delta)

var _spell_button_names: Array = []

func cast_ability(index: int):
	# Больше не используется (кнопки кастуют через _cast_spell_button)
	pass

func _process(_delta):
	if Game.is_paused:
		pause_label.visible = true
		pause_label.text = "ТАКТИЧЕСКАЯ ПАУЗА"
	else:
		pause_label.visible = false

	# Анимированный курсор-прицел (свиток или заклинание книги) следует за мышью
	if (not Game.pending_scroll.is_empty() or not Game.pending_spell.is_empty()) and _cast_cursor != null:
		_cast_cursor.global_position = get_viewport().get_mouse_position()
		if _cast_frames.size() > 0:
			_cast_frame_t += _delta
			if _cast_frame_t >= 0.06:
				_cast_frame_t = 0.0
				_cast_frame_i = (_cast_frame_i + 1) % _cast_frames.size()
				_cast_cursor.texture = _cast_frames[_cast_frame_i]
			if _cast_cursor.texture == null:
				_cast_cursor.texture = _cast_frames[0]
		_cast_cursor.visible = true
	else:
		if _cast_cursor != null and is_instance_valid(_cast_cursor):
			_cast_cursor.visible = false
	# Обратный отсчёт кулдаунов в книге магии. Раньше кулдаун был только в
	# тултипе, и игрок спамил клавиши, не понимая, почему заклинание не
	# срабатывает. Обновляем каждый кадр, но только когда что-то изменилось:
	# 24 клетки, лупать их без надобности — лишняя работа в каждом кадре.
	_update_cooldowns()


func _update_cooldowns() -> void:
	if not is_instance_valid(player):
		return
	for i in range(_spell_buttons_filled.size()):
		var b := _spell_buttons_filled[i] as Button
		if not is_instance_valid(b):
			continue
		var name := str(_spell_button_names[i])
		var left := float(player.cast_cooldowns.get(name, 0.0))
		# Считать округлённые секунды: показывать «0.3 с» бессмысленно.
		var shown := int(ceil(left))
		if shown == _cd_shown.get(name, -1):
			continue
		_cd_shown[name] = shown
		_set_cooldown_visual(b, left, SpellDB.cooldown_of(name))

func toggle_spells():
	spells_visible = !spells_visible
	_update_bottom_panel_visibility()

## Магия (B) — нижняя панель. Инвентарь теперь в модальном окне.
func _update_bottom_panel_visibility():
	spell_panel.visible = spells_visible
	bottom_panel.visible = spells_visible
	if not spells_visible:
		return

	# BottomPanel центрирован якорями (anchor_left=0.5, anchor_right=0.5),
	# ширина 720px задаётся offset_left=-360, offset_right=360 в tscn.
	# Здесь только вертикальная позиция (bottom-up от нижнего края).
	var vh := get_viewport().get_visible_rect().size.y

	var n := spell_buttons.size()
	if n <= 0:
		n = 12
	var rows := maxi(1, ceili(float(n) / float(SPELL_COLS)))
	var spell_h := clampf(10.0 + rows * (SPELL_CELL + 2.0), 90.0, 230.0)

	var book_w := 480.0
	spell_panel.offset_left = (720.0 - book_w) / 2.0
	spell_panel.offset_right = spell_panel.offset_left + book_w
	spell_panel.offset_top = 0.0
	spell_panel.offset_bottom = spell_h
	bottom_panel.offset_top = vh - spell_h
	bottom_panel.offset_bottom = vh

# --- Экономика (P0): панели магазина / школы / таверны ---

var _shop: ShopPanel = null
var _alchemy: AlchemyPanel = null
var _school: SchoolPanel = null
var _inn: InnPanel = null
var _archmage: ArchmagePanel = null
var _blacksmith: BlacksmithPanel = null
var _inventory_panel: InventoryPanel = null
var _interior_pos := Vector2.ZERO   # позиция героя перед входом в здание
var _in_interior := false
## Узлы HUD, которые прячем на время интерьера. Раньше они оставались видимыми:
## вокруг модального окна было видно «воду» и объекты мира, а кнопка «Закрыть»
## интерьера попадала в полосу склада.
const _HUD_NODES := ["BottomPanel", "MinimapPanel", "HudSide", "CoordsLabel", "PauseLabel"]

## Вход в здание: герой «уходит внутрь» (скрыт на карте), выходит при закрытии.
func _enter_interior() -> void:
	if not is_instance_valid(player):
		return
	if not Game.pending_scroll.is_empty() or not Game.pending_spell.is_empty():
		_cancel_targeting()   # прицеливание внутри здания не нужно
	_interior_pos = player.global_position
	player.stop_movement()          # не «ускакивает» по старой цели, пока в меню
	player.visible = false
	_in_interior = true
	for path in _HUD_NODES:
		var node: Control = get_node_or_null(path) as Control
		if node != null:
			node.visible = false

func _exit_interior() -> void:
	if not _in_interior:
		return
	_in_interior = false
	for path in _HUD_NODES:
		var node2: Control = get_node_or_null(path) as Control
		if node2 != null:
			node2.visible = true
	if is_instance_valid(player):
		player.visible = true
		# Точка выхода: исходная позиция, но на ПРОХОДИМОЙ клетке (не «в здании»)
		player.global_position = _clamp_to_walkable(_interior_pos)
		player.reset_physics_interpolation()

## Ближайшая проходимая точка рядом с запрошенной (спираль по клеткам).
func _clamp_to_walkable(from: Vector2) -> Vector2:
	var map_node = get_tree().get_first_node_in_group("alm_map")
	if map_node == null or not map_node.has_method("is_walkable_world"):
		return from
	if map_node.is_walkable_world(from):
		return from
	var cell := Vector2i(int(from.x) / 32, int(from.y) / 32)
	for r in range(1, 5):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var p := Vector2((cell.x + dx) * 32 + 16, (cell.y + dy) * 32 + 16)
				if map_node.is_walkable_world(p):
					return p
	return from

## Общий обработчик закрытия любой панели: показать героя у здания.
func _on_panel_closed() -> void:
	_shop = null
	_alchemy = null
	_school = null
	_inn = null
	_blacksmith = null
	_inventory_panel = null
	_archmage = null
	_exit_interior()

## Открыта ли какая-то панель-интерьер (клики не должны двигать героя по карте).
func is_editor_open() -> bool:
	return is_instance_valid(_shop) or is_instance_valid(_alchemy) or is_instance_valid(_school) or is_instance_valid(_inn) or is_instance_valid(_blacksmith) or is_instance_valid(_inventory_panel) or is_instance_valid(_archmage)

## Курсор над каким-либо элементом интерфейса (панель/кнопка/книга/инвентарь)?
## Клик по UI не должен читаться как движение/атака по карте.
func is_pointer_over_ui(screen_pos: Vector2) -> bool:
	for child in get_children():
		if child is Control and _control_contains(child, screen_pos):
			return true
	return false

func _control_contains(c: Control, p: Vector2) -> bool:
	# Вся цепочка родителей должна быть видимой (скрытые панели не блокируют)
	var cur: Control = c
	while cur is Control:
		if not cur.visible:
			return false
		cur = cur.get_parent() as Control
	# Узлы с MOUSE_FILTER_IGNORE не перехватывают клики (фон панелей),
	# но их дети-виджеты (кнопки и т.п.) по-прежнему блокируются отдельно.
	var hit := c.mouse_filter != Control.MOUSE_FILTER_IGNORE \
		and Rect2(c.global_position, c.size).has_point(p)
	for ch in c.get_children():
		if ch is Control and _control_contains(ch, p):
			return true
	return hit

## Магазин: купля/продажа (клик по зданию Shop).
func open_shop() -> void:
	if _shop != null and is_instance_valid(_shop):
		return
	_enter_interior()
	_shop = ShopPanel.new()
	_shop.setup(player)
	_shop.closed.connect(_on_panel_closed)
	add_child(_shop)

func open_alchemy() -> void:
	if _alchemy != null and is_instance_valid(_alchemy):
		return
	_enter_interior()
	_alchemy = AlchemyPanel.new()
	_alchemy.setup(player)
	_alchemy.closed.connect(_on_panel_closed)
	add_child(_alchemy)

## Школа тренировок: навыки за золото (клик по Training School).
func open_school() -> void:
	if _school != null and is_instance_valid(_school):
		return
	_enter_interior()
	_school = SchoolPanel.new()
	_school.setup(player)
	_school.closed.connect(_on_panel_closed)
	add_child(_school)

## Таверна: наём наёмников и разговоры (клик по Inn).
func open_inn() -> void:
	if _inn != null and is_instance_valid(_inn):
		return
	_enter_interior()
	_inn = InnPanel.new()
	_inn.setup(player)
	_inn.closed.connect(_on_panel_closed)
	add_child(_inn)

## Великий маг (капитан): военная плата (клик по магу в центре города).
func open_archmage() -> void:
	if _archmage != null and is_instance_valid(_archmage):
		return
	_enter_interior()
	_archmage = ArchmagePanel.new()
	_archmage.setup(player)
	_archmage.closed.connect(_on_panel_closed)
	_archmage.inventory_changed.connect(_on_inventory_changed)
	add_child(_archmage)

## Кузница: переплавка оружия/брони в слитки (клик по Blacksmith).
func open_blacksmith() -> void:
	if _blacksmith != null and is_instance_valid(_blacksmith):
		return
	_enter_interior()
	_blacksmith = BlacksmithPanel.new()
	_blacksmith.setup(player)
	_blacksmith.closed.connect(_on_panel_closed)
	add_child(_blacksmith)

## Инвентарь и экипировка: модальное окно. Повторное нажатие I — закрыть.
func open_inventory_panel() -> void:
	if _inventory_panel != null and is_instance_valid(_inventory_panel):
		_inventory_panel.close()
		return
	_enter_interior()
	_inventory_panel = InventoryPanel.new()
	_inventory_panel.setup(player)
	_inventory_panel.closed.connect(_on_panel_closed)
	_inventory_panel.inventory_changed.connect(_on_inventory_changed)
	add_child(_inventory_panel)

func _update_gold(amount: int) -> void:
	if is_instance_valid(hud_gold_label):
		hud_gold_label.text = str(amount)


func _on_inventory_changed() -> void:
	if is_instance_valid(_inventory_panel) and _inventory_panel.has_method("_refresh_stats"):
		_inventory_panel._refresh_stats()
	_update_gold(int(player.gold) if player != null else 0)

func refresh_inventory() -> void:
	if is_instance_valid(_inventory_panel):
		if _inventory_panel.has_method("_refresh_inventory_grid"):
			_inventory_panel._refresh_inventory_grid()
		if _inventory_panel.has_method("_refresh_stats"):
			_inventory_panel._refresh_stats()
	if is_instance_valid(player):
		_update_gold(int(player.get("gold") if "gold" in player else 0))
