extends CanvasLayer
class_name GameUI

@onready var spell_grid: GridContainer = $BottomPanel/SpellPanel/SpellGrid
@onready var bottom_panel: Control = $BottomPanel
@onready var spell_panel: Control = $BottomPanel/SpellPanel
@onready var inventory_panel: Control = $BottomPanel/InventoryPanel
@onready var inventory_scroll: ScrollContainer = $BottomPanel/InventoryPanel/InventoryMargin/InventoryScroll
@onready var inventory_margin: MarginContainer = $BottomPanel/InventoryPanel/InventoryMargin
@onready var inventory_grid: GridContainer = $BottomPanel/InventoryPanel/InventoryMargin/InventoryScroll/InventoryGrid
@onready var pause_label: Label = $PauseLabel
@onready var mini_portrait: TextureRect = $RightPanel/RightMargin/RightCol/Header/MiniPortraitBorder/MiniPortrait
@onready var hero_name_label: Label = $RightPanel/RightMargin/RightCol/Header/HeaderText/HeroName
@onready var hero_class_label: Label = $RightPanel/RightMargin/RightCol/Header/HeaderText/HeroClass
@onready var preview_info: Label = $RightPanel/RightMargin/RightCol/PreviewInfo
@onready var equip_area: Control = $RightPanel/RightMargin/RightCol/EquipArea
@onready var stats_area: VBoxContainer = $RightPanel/RightMargin/RightCol/StatsArea
@onready var minimap_rect: ColorRect = $RightPanel/RightMargin/RightCol/MinimapBorder/MinimapMargin/MinimapRect
@onready var coords_label: Label = $CoordsLabel

var show_coords := false
var hero_portrait: Texture2D = null   # дефолтный портрет героя (сброс ховера)
var _hover_name := ""
var cmd_buttons: Array = []          # кнопки команд поверх commandbarr.bmp (0-3 команды, 4 координаты)
var coords_btn: Button = null

var minimap_camera: Camera2D
var alm_map = null   # CustomMap или AlmMap (группа "alm_map")
var player: Player

# Для рисования миникарты
var minimap_image: Image
var minimap_texture: ImageTexture
var _minimap_size := Vector2.ZERO
var _minimap_timer := 0.0
const MINIMAP_INTERVAL := 0.25

func setup_ui(p: Player):
	player = p

	_setup_spells()

	# Шапка панели персонажа: имя, класс и компактный портрет (из экрана старта)
	hero_name_label.text = Game.hero_name
	var cls := "Маг" if Game.hero_class == "mage" else "Воин"
	var gnd := "Женщина" if Game.hero_gender == "female" else "Мужчина"
	hero_class_label.text = "%s · %s" % [cls, gnd]
	var hero_tex = load("res://assets/equipment/%s/1.png" % Game.hero_character_id)
	if hero_tex:
		mini_portrait.texture = hero_tex
		hero_portrait = hero_tex
	else:
		var tex = load("res://assets/portraits/goodorc.png")
		if tex:
			mini_portrait.texture = tex
			hero_portrait = tex

	_setup_inventory()
	refresh_spell_book()
	_setup_equipment_area()
	_setup_stats_area()
	_update_preview_hero()

	# Карта для миникарты: CustomMap или AlmMap (группа "alm_map", без каста — они не родственники)
	alm_map = get_tree().get_first_node_in_group("alm_map")

	_setup_minimap()
	_setup_action_buttons()
	_layout_panels()
	# При изменении размера окна — перераскладка панелей
	get_tree().root.size_changed.connect(_layout_panels)
	_update_stats()
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
var inventory_visible: bool = true
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

	if not known:
		# Пустой слот книги: приглушённый border цвета стихии
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(SPELL_CELL, SPELL_CELL)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.07, 0.06, 0.7)
		style.border_color = sphere_color.darkened(0.5)
		style.set_border_width_all(1)
		style.set_corner_radius_all(3)
		cell.add_theme_stylebox_override("panel", style)
		cell.tooltip_text = "%s\nСфера: %s\n(не выучено — выучите Книгой Магии)" % [title, sphere]
		spell_grid.add_child(cell)
		spell_buttons.append(cell)
		return

	var b := Button.new()
	b.custom_minimum_size = Vector2(SPELL_CELL, SPELL_CELL)
	b.flat = true

	# Стиль ячейки: тёмный фон + цветной border стихии снизу (2px)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.09, 0.08, 0.92)
	style.border_color = Color(0.2, 0.18, 0.15)
	style.set_border_width_all(1)
	style.set_border_width_bottom(2)
	style.border_color = sphere_color.lerp(Color(0.2, 0.18, 0.15), 0.4)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(2)
	b.add_theme_stylebox_override("normal", style)

	var hover_style := style.duplicate()
	hover_style.border_color = sphere_color
	hover_style.bg_color = Color(0.15, 0.13, 0.11, 0.95)
	b.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := style.duplicate()
	pressed_style.bg_color = Color(0.06, 0.05, 0.04, 1.0)
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
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(1, 0.95, 0.5))
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
	cd.add_theme_font_size_override("font_size", 15)
	cd.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
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

var _spellback: Texture2D = null
func _spellback_tex() -> Texture2D:
	if _spellback == null:
		_spellback = load("res://assets/interface/spellback.bmp")
	return _spellback


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
	_update_stats()

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

## Свиток применён по цели (вызывает Game). Сброс режима + обновление склад/книги.
func _finish_scroll_targeting() -> void:
	_cancel_targeting()
	refresh_inventory()
	refresh_spell_book()
	_update_bottom_panel_visibility()
	_update_stats()

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
		_scroll_hint.add_theme_font_size_override("font_size", 16)
		_scroll_hint.add_theme_color_override("font_color", Color(1, 0.9, 0.35))
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

# Инвентарь
var inventory_slots: Array = []
var inventory_items: Array = []
var inventory_items_meta: Array = []  # исходные Dictionary предметов (для key/quality)

# Двойной клик по магическому предмету (книга/свиток) — учим/читаем.
var _magic_click_key := ""
var _magic_click_time := 0.0

## true, если это повторный клик по тому же предмету в течение 0.45 с.
func _magic_double_click(item_key: String) -> bool:
	var now := Time.get_ticks_msec()
	var hit := _magic_click_key == item_key and now - _magic_click_time < 450
	_magic_click_key = item_key
	_magic_click_time = now
	return hit

## Размер ячейки склада и число колонок считаются от ширины панели, поэтому инвентарь
## не «едет» при изменении размера окна.
const INV_SLOT := 62
const INV_GAP := 4
const INV_MARGIN := 6

func _setup_inventory():
	_apply_inventory_theme()
	build_inventory_grid()

## Оформление склада: единая тема UiKit вместо фоновых картинок (myitem.png/invframe.bmp).
func _apply_inventory_theme() -> void:
	var theme := UiKit.base_theme()
	inventory_panel.theme_type_variation = &"InvPanel"
	UiKit.add_panel(theme, &"InvPanel", UiKit.SLOT_BG, UiKit.SLOT_BORDER, 4)
	UiKit.add_slot(theme, &"SlotCell")
	UiKit.apply_scrollbar(theme)
	inventory_panel.theme = theme
	UiKit.set_margins(inventory_margin, INV_MARGIN, INV_MARGIN, INV_MARGIN, INV_MARGIN)
	inventory_grid.add_theme_constant_override("h_separation", INV_GAP)
	inventory_grid.add_theme_constant_override("v_separation", INV_GAP)

## Сколько ячеек влезает в панель по ширине.
func _inventory_columns() -> int:
	var w: float = inventory_panel.size.x
	if w <= 0.0:
		w = 720.0
	var usable: float = w - INV_MARGIN * 2.0
	return maxi(1, int((usable + INV_GAP) / float(INV_SLOT + INV_GAP)))

## Пересобрать сетку инвентаря после покупки/продажи/лута/зелья.
func refresh_inventory() -> void:
	for s in inventory_slots:
		if is_instance_valid(s):
			s.queue_free()
	inventory_slots.clear()
	inventory_items.clear()
	inventory_items_meta.clear()
	build_inventory_grid()

func build_inventory_grid() -> void:
	if not is_instance_valid(player):
		return
	inventory_grid.columns = _inventory_columns()
	# Склад: подсчёт одинаковых предметов (стак) для счётчика в углу
	var counts := {}
	for key in player.inventory:
		var k := str(key)
		counts[k] = int(counts.get(k, 0)) + 1
	# Книги и свитки лежат в складе как обычные предметы (купить в лавке) и
	# учатся/читаются двойным кликом по ячейке; книга одного заклинания
	# синтезируется (в item_db её нет — там только 5 книг стихий).
	for key in player.inventory:
		var item := ItemDB.find(str(key))
		if item.is_empty():
			item = SpellDB.book_item(str(key))
			if item.is_empty():
				continue
		_add_inventory_slot(item, int(counts[str(key)]))
	if inventory_slots.is_empty():
		var lab := Label.new()
		lab.text = "Склад пуст"
		lab.add_theme_font_size_override("font_size", 16)
		lab.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
		inventory_grid.add_child(lab)

## Создать ячейку склада (PanelContainer + иконка), count>1 — счётчик стека.
func _add_inventory_slot(item: Dictionary, count: int = 0) -> void:
	var slot := PanelContainer.new()
	slot.theme_type_variation = &"SlotCell"
	slot.custom_minimum_size = Vector2(INV_SLOT, INV_SLOT)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	# Карточка предмета у курсора (стилизованная, вместо стандартного tooltip_text).
	_attach_item_card(slot, item)
	# Выбран слот экипировки — затемняем неподходящие предметы (см. _set_slot_highlight).
	if _highlight_slot != "" and not _item_matches_slot(item):
		slot.modulate = Color(1, 1, 1, 0.30)
	inventory_grid.add_child(slot)
	inventory_slots.append(slot)
	inventory_items.append(item)
	inventory_items_meta.append(item)

	var gear := {
		"slot": ItemDB.slot_of(item),
		"weapon": ItemDB.weapon_kind(item),
		"two_handed": ItemDB.is_two_handed(item),
		"armor": ItemDB.armor_kind(item),
	}
	_add_item(inventory_slots.size() - 1, str(item.get("icon", "")), str(item.get("name_ru", "")), gear)

	# Счётчик количества (стак/деньги) в правом верхнем углу ячейки
	if count > 1:
		var cnt := Label.new()
		cnt.text = str(count)
		cnt.add_theme_font_size_override("font_size", 12)
		cnt.add_theme_color_override("font_color", Color(1, 0.9, 0.45))
		cnt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		cnt.add_theme_constant_override("outline_size", 4)
		cnt.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		cnt.offset_left = -24.0
		cnt.offset_top = 0.0
		cnt.offset_right = -2.0
		cnt.offset_bottom = 18.0
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(cnt)

## Обработчик клика по предмету — экипировать героя / изучить магию.
func _on_item_clicked(item: Dictionary):
	if not is_instance_valid(player):
		return
	var quality := str(item.get("quality", ""))
	var item_key := str(item.get("key", ""))
	if quality == "Herb":
		print("Трава: %s — ингредиент для будущих рецептов." % str(item.get("name_ru", item_key)))
		return

	# Магические предметы: книга (маг) или свиток (любой). Учатся/читаются
	# ДВОЙНЫМ кликом по ячейке склада; предмет при этом расходуется.
	# Имена: ключ "Book Fire Arrow"/"Scroll Fire Ball" — SpellDB их распознаёт.
	if quality == "Book":
		if not _magic_double_click(item_key):
			return
		if player.learn_book(item_key):
			SoundDB.play(7)  # ibook
			refresh_inventory()
			refresh_spell_book()
			_update_bottom_panel_visibility()
			_update_stats()
		else:
			print("Книги магии читает только маг (и заклинание должно быть новым).")
		return
	if quality in ["Scroll", "SuperScroll"]:
		if not _magic_double_click(item_key):
			return
		# Маг читает свиток ПРИЦЕЛЬНО (курсор-прицел, применяет 1 раз по цели);
		# не-маг копит заряд в панели магии.
		if player.has_mana:
			_begin_scroll_targeting(item_key)
			return
		if player.read_scroll(item_key):
			SoundDB.play(7)  # ibook
			refresh_inventory()
			refresh_spell_book()
			_update_bottom_panel_visibility()
			_update_stats()
		return

	# Зелья: лечение/мана из склада
	if quality == "Potion":
		_use_potion(item_key, item)
		return

	# Экипировка идёт через player.equip_item(): он запоминает КЛЮЧ предмета
	# в слоте. Раньше здесь выставлялись только armor_kind/weapon/has_shield —
	# то есть менялся набор анимации, а сам предмет нигде не сохранялся и в бой
	# не попадал (статы считались по атрибутам).
	var slot := str(item.get("slot", ""))
	if slot == "shield" and player.two_handed:
		print("Щит нельзя с двуручным оружием!")
		return
	if player.equip_item(item):
		_update_stats()
		print("Экипировано: " + str(item.get("name_ru", item_key)))
		if _highlight_slot != "":
			_set_slot_highlight("")   # сброс подсветки + перестройка инвентаря
		else:
			refresh_inventory()
	else:
		refresh_inventory()

## Зелья из склада: лечение/мана (объём по названию), предмет расходуется.
func _use_potion(item_key: String, item: Dictionary) -> void:
	if not is_instance_valid(player):
		return
	var key := item_key.to_lower()
	var heal := 0
	var mana := 0
	if "healing" in key:
		heal = 60 if "big" in key else (30 if "medium" in key else 20)
	elif "mana" in key:
		mana = 50 if "big" in key else (25 if "medium" in key else 15)
	elif "regen" in key:
		heal = 15
		mana = 10
	if heal <= 0 and mana <= 0:
		return
	if not player.remove_item(item_key):
		return
	player.current_hp = mini(player.max_hp, player.current_hp + heal)
	if player.max_mana > 0:
		player.current_mana = mini(player.max_mana, player.current_mana + mana)
	SoundDB.play(11)
	refresh_inventory()
	_update_stats()
	print("Использовано: " + str(item.get("name_ru", item_key)))

func _add_item(slot_idx: int, icon_path: String, item_name: String, gear: Dictionary = {}):
	if slot_idx >= 0 and slot_idx < inventory_slots.size():
		var tex = load(icon_path)
		var slot: Control = inventory_slots[slot_idx]
		if tex:
			# Иконка предмета внутри ячейки (PanelContainer), не перехватывает клики
			var icon_rect = TextureRect.new()
			icon_rect.texture = tex
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon_rect.offset_left = 4.0
			icon_rect.offset_top = 4.0
			icon_rect.offset_right = -4.0
			icon_rect.offset_bottom = -4.0
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(icon_rect)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP

		var item_data: Dictionary = gear.duplicate(true)
		item_data["name"] = item_name
		item_data["icon"] = icon_path
		# Магический предмет (книга/свиток): ключ и качество для обработки
		var src: Dictionary = inventory_items_meta[slot_idx] if slot_idx < inventory_items_meta.size() else {}
		if not src.is_empty():
			item_data["key"] = str(src.get("key", ""))
			item_data["quality"] = str(src.get("quality", ""))
		inventory_items[slot_idx] = item_data

		# Кликабельный слот: наводим и нажимаем для экипировки
		slot.gui_input.connect(func(event: InputEvent, data := item_data):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_on_item_clicked(data))

func _setup_action_buttons():
	# Командные кнопки (следовать/атаковать/охранять/стоп + переключатели) —
	# одним рядом под миникартой в правой панели. Фоновая картинка Allods 2
	# (commandbarr.bmp) убрана вместе с декорацией; кнопки плоские с тултипами.
	var labels := [
		"Следовать", "Атаковать", "Охранять", "Стоп",
		"Координаты", "Патруль", "Разговор", "Отдых",
	]
	var right_col := equip_area.get_parent() as VBoxContainer

	# Кнопка «Инвентарь» — под миникартой, перед командными кнопками
	var inv_btn := Button.new()
	inv_btn.text = "Инвентарь (I)"
	inv_btn.custom_minimum_size = Vector2(0, 32)
	inv_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	inv_btn.pressed.connect(open_inventory_panel)
	if right_col != null:
		right_col.add_child(inv_btn)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	if right_col != null:
		right_col.add_child(row)
	for i in range(labels.size()):
		var b := Button.new()
		b.custom_minimum_size = Vector2(38, 38)
		b.flat = true
		b.tooltip_text = labels[i]
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.add_child(b)
		cmd_buttons.append(b)
		match i:
			0: b.pressed.connect(func(): _set_action_mode("follow"))
			1: b.pressed.connect(func(): _set_action_mode("attack"))
			2: b.pressed.connect(func(): _set_action_mode("guard"))
			3: b.pressed.connect(func(): _set_action_mode("stop"))
			4:
				b.toggle_mode = true
				coords_btn = b
				b.pressed.connect(func(): _toggle_coords())
			_:
				b.disabled = true  # остальные — заглушки (в разработке)
	coords_label.visible = false

func _set_action_mode(mode: String):
	# Сбрасываем подсветку всех командных кнопок
	for i in range(4):
		cmd_buttons[i].modulate = Color.WHITE

	match mode:
		"follow":
			cmd_buttons[0].modulate = Color.YELLOW
			Game.action_mode = "follow"
		"attack":
			cmd_buttons[1].modulate = Color.RED
			Game.action_mode = "attack"
		"guard":
			cmd_buttons[2].modulate = Color.GREEN
			Game.action_mode = "guard"
		"stop":
			Game.action_mode = "none"

func _toggle_coords():
	show_coords = not show_coords
	coords_btn.button_pressed = show_coords
	coords_label.visible = show_coords

## Esc снимает подсветку подходящих предметов у выбранного пустого слота.
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE and _highlight_slot != "":
		_set_slot_highlight("")
		get_viewport().set_input_as_handled()

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
	cell.mouse_entered.connect(func():
		if _item_card == null:
			_item_card = _ensure_card("item")
		UiKit.show_hover_card(_item_card, _item_card_lines(item),
			cell.global_position, DESIGN_SIZE))
	cell.mouse_exited.connect(func():
		if _item_card != null:
			UiKit.hide_hover_card(_item_card))
	cell.focus_entered.connect(func():
		if _item_card == null:
			_item_card = _ensure_card("item")
		UiKit.show_hover_card(_item_card, _item_card_lines(item),
			cell.global_position, DESIGN_SIZE))
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
	UiKit.show_hover_card(_slot_card, lines, cell.global_position, DESIGN_SIZE)

func _hide_slot_card() -> void:
	if _slot_card != null:
		UiKit.hide_hover_card(_slot_card)

# --- Задержанные тултипы мира (юнит/здание/лут) ------------------------------

const WORLD_HOVER_DELAY := 0.5
const DESIGN_SIZE := Vector2(1280, 800)
var _world_card: PanelContainer = null
var _world_hover_key := ""
var _world_hover_time := 0.0
var _world_card_shown := false

## Каждый кадр: цель под курсором; после WORLD_HOVER_DELAY неподвижного курсора
## показываем карточку у мыши (имя/HP/фракция для юнитов, имя для зданий, лут).
func _update_world_tooltip(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var target: Array = _world_hover_target()
	var key := str(target[0])
	if key == "":
		_world_hover_time = 0.0
		_world_hover_key = ""
		_world_card_shown = false
		if _world_card != null and _world_card.visible:
			UiKit.hide_hover_card(_world_card)
		return
	if key != _world_hover_key:
		_world_hover_key = key
		_world_hover_time = 0.0
		_world_card_shown = false
		if _world_card != null and _world_card.visible:
			UiKit.hide_hover_card(_world_card)
		return
	_world_hover_time += delta
	if _world_hover_time < WORLD_HOVER_DELAY:
		return
	if _world_card_shown:
		return
	if _world_card == null:
		_world_card = _ensure_card("world")
	UiKit.show_hover_card(_world_card, target[1],
		get_viewport().get_mouse_position(), DESIGN_SIZE)
	_world_card_shown = true

## Цель под курсором: [ключ, строки]. "" — цели нет.
func _world_hover_target() -> Array:
	var world := player.get_global_mouse_position()
	# 1) Юнит (монстр/житель) — хитбокс спрайта, как в _hover_portrait.
	for e in Game.enemies + Game.npcs:
		if is_instance_valid(e) and Game.unit_hit_rect(e).grow(6.0).has_point(world):
			return [_unit_hover_key(e), _unit_tooltip_lines(e)]
	# 2) Здание под курсором.
	if alm_map and alm_map.map_width > 0:
		var ts: int = alm_map.tile_size
		var cell := Vector2i(int(world.x) / ts, int(world.y) / ts)
		if alm_map.has_method("structure_at"):
			var h: Dictionary = alm_map.structure_at(cell)
			if not h.is_empty():
				return ["b%d" % int(h.get("type_id", -1)), _building_tooltip_lines(h)]
	# 3) Лут на земле.
	for lb in get_tree().get_nodes_in_group("loot"):
		if is_instance_valid(lb) and lb is LootBag \
				and lb.global_position.distance_to(world) < 22.0:
			return ["l%d" % lb.get_instance_id(), _loot_tooltip_lines(lb)]
	return ["", []]

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
	var hp := 0
	if "max_hp" in e:
		hp = int(e.max_hp)
	elif "hp_max" in e:
		hp = int(e.hp_max)
	var cur := int(e.current_hp) if "current_hp" in e else hp
	lines.append("Здоровье: %d/%d" % [cur, hp])
	if "current_mana" in e:
		lines.append("Мана: %d/%d" % [int(e.current_mana), int(e.max_mana)])
	lines.append("Фракция: %s" % _faction_of_set(set_name))
	return lines

func _building_tooltip_lines(h: Dictionary) -> Array:
	var lines: Array = []
	var sid := int(h.get("type_id", -1))
	var name := StructureDB.display_name_by_id(sid) if sid >= 0 else str(h.get("picture", ""))
	lines.append(name if name != "" else "Здание")
	lines.append("Здание")
	return lines

func _loot_tooltip_lines(lb: LootBag) -> Array:
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

## Портрет под курсором: враг-юнит (UnitDB picture) или здание (structures Picture).
## Если нет — портрет героя. Под портретем — текстовая информация о цели.
var _portrait_cache := {}
var _hovered_unit: Node2D = null  # юнит под курсором (для обновления HP)
func _hover_portrait() -> void:
	if not is_instance_valid(player):
		return
	var world := player.get_global_mouse_position()
	var pic := ""
	var hover_set := ""
	_hovered_unit = null

	# 1) Юнит под курсором (монстр или житель): хит-бокс спрайта
	for e in Game.enemies + Game.npcs:
		if is_instance_valid(e) and Game.unit_hit_rect(e).grow(6.0).has_point(world):
			if e is Enemy or e is Npc:
				hover_set = str(e.anim_set)
			if hover_set != "":
				pic = str(UnitDB.get_set(hover_set).get("picture", ""))
			_hovered_unit = e
			break

	# 2) Иначе здание под курсором
	if pic == "" and alm_map and alm_map.map_width > 0:
		var ts: int = alm_map.tile_size
		var cell := Vector2i(int(world.x) / ts, int(world.y) / ts)
		if alm_map.has_method("structure_at"):
			var h: Dictionary = alm_map.structure_at(cell)
			if not h.is_empty():
				pic = str(h.get("picture", ""))

	if pic == "":
		if _hover_name != "":
			_hover_name = ""
			mini_portrait.texture = hero_portrait
			_update_preview_hero()
		return

	var lower := pic.to_lower()
	if lower == _hover_name:
		# Обновляем HP если юнит жив (HP меняется)
		if _hovered_unit != null and is_instance_valid(_hovered_unit):
			_update_preview_unit(_hovered_unit)
		return
	_hover_name = lower
	var tex: Texture2D = _portrait_cache.get(lower)
	if tex == null:
		var path := "res://assets/portraits/%s.png" % lower
		if not ResourceLoader.exists(path):
			if hover_set != "":
				tex = UnitDB.preview_frame(hover_set)
				if tex != null:
					_portrait_cache[lower] = tex
			if tex == null:
				_hover_name = ""
				mini_portrait.texture = hero_portrait
				_update_preview_hero()
				return
			mini_portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		else:
			tex = load(path)
			if tex != null:
				_portrait_cache[lower] = tex
			mini_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if tex != null:
		mini_portrait.texture = tex
	else:
		mini_portrait.texture = hero_portrait

	# Обновить текстовую информацию
	if _hovered_unit != null and is_instance_valid(_hovered_unit):
		_update_preview_unit(_hovered_unit)
	else:
		_update_preview_building(lower)


func _update_preview_unit(e: Node2D) -> void:
	if preview_info == null:
		return
	var set_name := str(e.anim_set) if "anim_set" in e else ""
	var set_data := UnitDB.get_set(set_name)
	var name := str(set_data.get("desc", ""))
	if name == "":
		name = set_name.get_slice("/", 1) if "/" in set_name else set_name
	var lines: Array = [name if name != "" else "Существо"]
	var hp := 0
	if "max_hp" in e:
		hp = int(e.max_hp)
	elif "hp_max" in e:
		hp = int(e.hp_max)
	var cur := int(e.current_hp) if "current_hp" in e else hp
	lines.append("HP: %d/%d" % [cur, hp])
	lines.append("Фракция: %s" % _faction_of_set(set_name))
	preview_info.text = "\n".join(lines)


func _update_preview_building(pic_name: String) -> void:
	if preview_info == null:
		return
	# Ищем здание под курсором для получения имени
	var world := player.get_global_mouse_position()
	if alm_map and alm_map.map_width > 0:
		var ts: int = alm_map.tile_size
		var cell := Vector2i(int(world.x) / ts, int(world.y) / ts)
		if alm_map.has_method("structure_at"):
			var h: Dictionary = alm_map.structure_at(cell)
			if not h.is_empty():
				var sid := int(h.get("type_id", -1))
				var display := StructureDB.display_name_by_id(sid) if sid >= 0 else ""
				preview_info.text = display if display != "" else "Здание"
				return
	preview_info.text = "Здание"


func _update_preview_hero() -> void:
	if preview_info == null or not is_instance_valid(player):
		return
	var weapon := str(player.equipped.get("weapon", ""))
	var shield := str(player.equipped.get("shield", ""))
	var body := str(player.equipped.get("body", ""))
	var lines: Array = []
	if weapon != "":
		lines.append("Оружие: %s" % str(ItemDB.find(weapon).get("name_ru", weapon)) if not ItemDB.find(weapon).is_empty() else weapon)
	if shield != "":
		lines.append("Щит: %s" % str(ItemDB.find(shield).get("name_ru", shield)) if not ItemDB.find(shield).is_empty() else shield)
	if body != "":
		lines.append("Броня: %s" % str(ItemDB.find(body).get("name_ru", body)) if not ItemDB.find(body).is_empty() else body)
	if lines.is_empty():
		preview_info.text = "Нет экипировки"
	else:
		preview_info.text = "\n".join(lines)

func _setup_minimap():
	# Защита от повторного вызова: раньше setup_ui вызывал это дважды
	# (напрямую и через _setup_spells) — создавался дубликат узла MinimapTex.
	if minimap_rect.get_node_or_null("MinimapTex") != null:
		return
	minimap_rect.color = Color(0, 0, 0, 0)
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

	# Размер рисунка = рамка MinimapRect (160x160 в tscn), а не жёсткие 190,
	# из-за которых карта вылезала на панель команд и за экран.
	var msize: Vector2 = minimap_rect.size
	var w := int(msize.x)
	var h := int(msize.y)
	if w <= 0 or h <= 0:
		return

	# Первый кадр или смена размера рамки — пересоздаём изображение/текстуру.
	if minimap_image == null or minimap_texture == null or _minimap_size != msize:
		_minimap_size = msize
		minimap_image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		minimap_texture = ImageTexture.create_from_image(minimap_image)
		var tex_rect := minimap_rect.get_node_or_null("MinimapTex")
		if tex_rect:
			tex_rect.offset_right = float(w)
			tex_rect.offset_bottom = float(h)

	var ptx: int = int(player.global_position.x) / alm_map.tile_size
	var pty: int = int(player.global_position.y) / alm_map.tile_size
	var scale_x := float(w) / float(mw)
	var scale_y := float(h) / float(mh)

	minimap_image.fill(Color(0.03, 0.03, 0.04, 1.0))

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
				minimap_image.set_pixel(xx, yy, Color(1, 1, 1, 1))

	# Враги (красные точки)
	for enemy in Game.enemies:
		if is_instance_valid(enemy):
			var etx: int = int(enemy.global_position.x) / alm_map.tile_size
			var ety: int = int(enemy.global_position.y) / alm_map.tile_size
			var exx := int(etx * scale_x); var eyy := int(ety * scale_y)
			if exx >= 0 and exx < w and eyy >= 0 and eyy < h:
				minimap_image.set_pixel(exx, eyy, Color(1.0, 0.2, 0.2, 1.0))

	# NPC (жёлтые = нейтральные, зелёные = союзники/стражи)
	for npc in Game.npcs:
		if is_instance_valid(npc):
			var ntx: int = int(npc.global_position.x) / alm_map.tile_size
			var nty: int = int(npc.global_position.y) / alm_map.tile_size
			var nxx := int(ntx * scale_x); var nyy := int(nty * scale_y)
			if nxx >= 0 and nxx < w and nyy >= 0 and nyy < h:
				var nc: Color
				if "guard" in str(npc.get("role", "")):
					nc = Color(0.2, 0.8, 0.2, 1.0)  # страж = зелёный
				else:
					nc = Color(1.0, 0.85, 0.2, 1.0)  # житель = жёлтый
				minimap_image.set_pixel(nxx, nyy, nc)

	# Здания (серые квадраты 2×2)
	if alm_map.has_method("structure_at") and alm_map.map_width > 0:
		var ts: int = alm_map.tile_size
		for ty in range(0, mh, 4):
			for tx in range(0, mw, 4):
				var h: Dictionary = alm_map.structure_at(Vector2i(tx, ty))
				if not h.is_empty():
					var sx := int(tx * scale_x)
					var sy := int(ty * scale_y)
					for dy in range(0, 2):
						for dx in range(0, 2):
							var xx := sx + dx; var yy := sy + dy
							if xx >= 0 and xx < w and yy >= 0 and yy < h:
								minimap_image.set_pixel(xx, yy, Color(0.5, 0.45, 0.4, 1.0))

	minimap_texture.update(minimap_image)
	var tex_rect2 := minimap_rect.get_node_or_null("MinimapTex")
	if tex_rect2:
		tex_rect2.texture = minimap_texture

# Цвет клетки для миникарты: CustomMap -> тип (0-8), .alm -> terrain_type
func _minimap_color_at(tx: int, ty: int) -> Color:
	if alm_map is CustomMap:
		var t: int = alm_map.tile_id_at(Vector2i(tx, ty))
		match t:
			1: return Color(0.55, 0.35, 0.15, 1.0)    # почва
			2: return Color(0.85, 0.80, 0.50, 1.0)    # песок
			3: return Color(0.15, 0.35, 0.75, 1.0)    # вода
			4: return Color(0.45, 0.42, 0.40, 1.0)    # горы
			5: return Color(0.60, 0.50, 0.35, 1.0)    # дорога
			6: return Color(0.30, 0.22, 0.12, 1.0)    # грязь
			7: return Color(0.45, 0.3, 0.2, 1.0)      # строение
			8: return Color(1.0, 0.85, 0.2, 1.0)      # спавн
			0: return Color(0.25, 0.55, 0.25, 1.0)    # трава
			_: return Color(0, 0, 0, 0)                # пусто
	var t2: int = alm_map.cell_type_at(tx, ty)
	match t2:
		2:
			return Color(0.15, 0.35, 0.75, 1.0)  # вода (tile3)
		1:
			return Color(0.52, 0.48, 0.42, 1.0)   # горы/холмы — серые скалы
		3:
			return Color(0.7, 0.65, 0.55, 1.0)   # дорога (tile4)
		4:
			return Color(0.50, 0.35, 0.18, 1.0)  # почва (tile5) — тёмно-коричневая
		5:
			return Color(0.85, 0.70, 0.22, 1.0)  # песок — яркий жёлтый
		6:
			return Color(0.22, 0.15, 0.08, 1.0)  # грязь — тёмно-коричневая
		_:
			return Color(0.25, 0.55, 0.25, 1.0)  # трава (tile1)

# --- Панель экипировки: кукла + 10 слотов (см. ItemDB.EQUIP_SLOTS) ----------

const EQUIP_SLOT_SIZE := Vector2(54, 54)
var _equip_slots := {}          # слот -> {panel: Control, icon: TextureRect}
var _doll: TextureRect = null
var _highlight_slot := ""       # пустой слот, для которого подсвечиваем инвентарь

func _setup_equipment_area() -> void:
	if not is_instance_valid(equip_area):
		return
	var theme := UiKit.base_theme()
	UiKit.add_panel(theme, &"EquipSlot", UiKit.SLOT_BG, UiKit.SLOT_BORDER, 4)
	# Подсветка выбранного слота — золотая рамка поверх базового стиля.
	theme.set_stylebox("panel", &"EquipSlotActive", UiKit.panel_style(
		Color(0.18, 0.14, 0.10, 0.95), UiKit.DIALOG_BORDER, 4, 3))
	equip_area.theme = theme

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	equip_area.add_child(center)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	center.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 8)
	row.add_child(mid)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)

	# Кукла: полноростовый спрайт героя по центру (шлем над головой, броня под ним).
	_doll = TextureRect.new()
	_doll.texture = hero_portrait
	_doll.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_doll.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_doll.custom_minimum_size = Vector2(130, 200)
	_doll.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for slot in ["weapon", "shield", "hands", "cloak"]:
		left.add_child(_make_equip_slot(slot))
	mid.add_child(_make_equip_slot("head"))
	mid.add_child(_doll)
	mid.add_child(_make_equip_slot("body"))
	for slot in ["amulet", "ring1", "ring2", "feet"]:
		right.add_child(_make_equip_slot(slot))

func _make_equip_slot(slot: String) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"EquipSlot"
	panel.custom_minimum_size = EQUIP_SLOT_SIZE
	panel.focus_mode = Control.FOCUS_ALL
	panel.tooltip_text = ItemDB.slot_title(slot)
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)
	panel.gui_input.connect(_on_slot_input.bind(slot))
	panel.focus_entered.connect(func(): _on_slot_focus(slot, true))
	panel.focus_exited.connect(func(): _on_slot_focus(slot, false))
	_attach_slot_card(panel, slot)
	_equip_slots[slot] = {"panel": panel, "icon": icon}
	return panel

## Обновить иконки слотов по текущей экипировке героя.
func refresh_equipment() -> void:
	if not is_instance_valid(player) or _equip_slots.is_empty():
		return
	for slot in ItemDB.EQUIP_SLOTS:
		var cell: Dictionary = _equip_slots[slot]
		var icon_rect: TextureRect = cell.icon
		var key := str(player.equipped.get(slot, ""))
		if key == "":
			icon_rect.texture = null
		else:
			var it := ItemDB.find(key)
			icon_rect.texture = load(str(it.get("icon", ""))) if not it.is_empty() else null

func _on_slot_input(event: InputEvent, slot: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_slot_clicked(slot)

## Фокус слота (клавиатура/геймпад): ведём себя как клик по пустому слоту —
## подсвечиваем подходящие предметы, повторный фокус/выход — сброс.
func _on_slot_focus(slot: String, entered: bool) -> void:
	if not entered and _highlight_slot == slot:
		_set_slot_highlight("")
	elif entered and str(player.equipped.get(slot, "")) == "":
		_set_slot_highlight(slot)

func _on_slot_clicked(slot: String) -> void:
	if not is_instance_valid(player):
		return
	var key := str(player.equipped.get(slot, ""))
	if key != "":
		# Заполненный слот: снять предмет в инвентарь (если его там ещё нет).
		if player.unequip_slot(slot):
			if not player.has_item(key):
				player.add_item(key)
			SoundDB.play(6)  # idrop
			_set_slot_highlight("")
			refresh_inventory()
			_update_stats()
		return
	# Пустой слот: включить/выключить подсветку подходящих предметов.
	if _highlight_slot == slot:
		_set_slot_highlight("")
	else:
		_set_slot_highlight(slot)

func _set_slot_highlight(slot: String) -> void:
	_highlight_slot = slot
	for s in ItemDB.EQUIP_SLOTS:
		var cell: Dictionary = _equip_slots.get(s, {})
		if cell.is_empty():
			continue
		var panel: PanelContainer = cell.panel
		if s == slot:
			panel.theme_type_variation = &"EquipSlotActive"
		else:
			panel.theme_type_variation = &"EquipSlot"
	refresh_inventory()

## Предмет совпадает со слотом подсветки (или подсветки нет — любой).
func _item_matches_slot(item: Dictionary) -> bool:
	if _highlight_slot == "":
		return true
	return ItemDB.fits_slot(item, _highlight_slot)

# --- Блок статов: текстовые строки с HSeparator между секциями --------

var _hp_label: Label = null
var _mp_label: Label = null
var _stat_labels := {}   # key -> Label ("attrs"/"derived"/"skills"/"resists"/"extra")

func _setup_stats_area() -> void:
	if not is_instance_valid(stats_area):
		return
	stats_area.add_theme_constant_override("separation", 2)

	# HP/MP — текстом (бары дублируют то, что над головой героя)
	_hp_label = _add_stat_text("ЖИЗНЬ", Color(0.55, 0.85, 0.55))
	_mp_label = _add_stat_text("МАНА", Color(0.55, 0.7, 1.0))

	# Секция: Атрибуты
	_add_separator("АТРИБУТЫ")
	_stat_labels["attrs"] = _add_stat_line()

	# Секция: Бой
	_add_separator("БОЙ")
	_stat_labels["derived"] = _add_stat_line()

	# Секция: Навыки / Сферы
	if Game.hero_class == "mage":
		_add_separator("СФЕРЫ")
	else:
		_add_separator("НАВЫКИ")
	_stat_labels["skills"] = _add_stat_line()

	# Секция: Сопротивление
	_add_separator("СОПРОТИВЛЕНИЕ")
	_stat_labels["resists"] = _add_stat_line()

	# Секция: Параметры
	_add_separator("ПАРАМЕТРЫ")
	_stat_labels["extra"] = _add_stat_line()


func _add_stat_text(title: String, color: Color) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var lab_title := Label.new()
	lab_title.text = title
	lab_title.custom_minimum_size = Vector2(55, 0)
	lab_title.add_theme_font_size_override("font_size", 12)
	lab_title.add_theme_color_override("font_color", Color(0.75, 0.70, 0.60))
	row.add_child(lab_title)
	var lab_val := Label.new()
	lab_val.add_theme_font_size_override("font_size", 13)
	lab_val.add_theme_color_override("font_color", color)
	row.add_child(lab_val)
	stats_area.add_child(row)
	return lab_val


func _add_separator(title: String) -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	stats_area.add_child(sep)
	var lab := Label.new()
	lab.text = title
	lab.add_theme_font_size_override("font_size", 11)
	lab.add_theme_color_override("font_color", Color(0.6, 0.55, 0.48))
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_area.add_child(lab)


func _add_stat_line() -> Label:
	var lab := Label.new()
	lab.add_theme_font_size_override("font_size", 13)
	lab.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80))
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_area.add_child(lab)
	return lab


func _update_stats():
	if not is_instance_valid(player):
		return
	var p = player
	refresh_equipment()

	if _hp_label != null:
		_hp_label.text = "%d / %d" % [p.current_hp, p.max_hp]
	if _mp_label != null:
		_mp_label.text = "%d / %d" % [p.current_mana, p.max_mana]
	if _stat_labels.is_empty():
		return

	_stat_labels["attrs"].text = "Тело %d  Ловк %d  Разум %d  Дух %d" % [
		p.body, p.agility, p.mind, p.spirit]
	_stat_labels["derived"].text = "Урон %d–%d  Атака %d\nЗащита %d  Поглощ. %d" % [
		p.get_damage_min(), p.get_damage_max(), p.get_attack(),
		p.get_defense(), p.get_absorption()]
	if Game.hero_class == "mage":
		_stat_labels["skills"].text = "Огонь %d  Вода %d  Воздух %d\nЗемля %d  Астрал %d" % [
			p.fire_skill, p.water_skill, p.air_skill, p.earth_skill, p.astral_skill]
	else:
		_stat_labels["skills"].text = "Меч %d  Топор %d  Дубина %d\nКопьё %d  Стрельба %d" % [
			p.blade_skill, p.axe_skill, p.bludgeon_skill, p.pike_skill, p.shooting_skill]
	_stat_labels["resists"].text = "Огн. %d%%  Вод. %d%%  Возд. %d%%\nЗем. %d%%  Аст. %d%%" % [
		p.get_protection_fire(), p.get_protection_water(), p.get_protection_air(),
		p.get_protection_earth(), p.get_protection_astral()]
	_stat_labels["extra"].text = "Обзор %d  Скор. %d  Нагр. %.1f/%.0f  Опыт %d" % [
		p.get_sight(), int(p.move_speed), p.get_load(), p.load_capacity(),
		p.total_experience()]

func update_ui(p: Player, delta: float = 0.0):
	if not is_instance_valid(p):
		return
	_hover_portrait()
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
				var names := ["Трава (tile1)", "Горы (tile2 — проходимо, медленно)", "Вода (tile3)", "Дорога (tile4)"]
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

func toggle_inventory():
	inventory_visible = !inventory_visible
	_update_bottom_panel_visibility()

func toggle_spells():
	spells_visible = !spells_visible
	_update_bottom_panel_visibility()

# Магия (B) и инвентарь (I) — независимые панели.
# Обе видны: магия сверху, инвентарь снизу. Контейнер подгоняется под контент.
func _update_bottom_panel_visibility():
	spell_panel.visible = spells_visible
	inventory_panel.visible = inventory_visible

	var any_visible = spells_visible or inventory_visible
	bottom_panel.visible = any_visible
	if not any_visible:
		return

	# BottomPanel центрирован якорями (anchor_left=0.5, anchor_right=0.5),
	# ширина 720px задаётся offset_left=-360, offset_right=360 в tscn.
	# Здесь только вертикальная позиция (bottom-up от нижнего края).
	var vh := get_viewport().get_visible_rect().size.y

	# Высота книги заклинаний: по числу строк сетки ячеек 36px (минимум 12),
	# но не ниже фона 90px. Маг после выучивания многих книг — книга растёт вверх.
	var n := spell_buttons.size()
	if n <= 0:
		n = 12
	var rows := maxi(1, ceili(float(n) / float(SPELL_COLS)))
	var spell_h := clampf(10.0 + rows * (SPELL_CELL + 2.0), 90.0, 230.0)
	var inv_h = 95.0
	var gap = 5.0

	var book_w := 480.0
	spell_panel.offset_left = (720.0 - book_w) / 2.0
	spell_panel.offset_right = spell_panel.offset_left + book_w

	if spells_visible and inventory_visible:
		spell_panel.offset_top = 0.0
		spell_panel.offset_bottom = spell_h
		inventory_panel.offset_top = spell_h + gap
		inventory_panel.offset_bottom = spell_h + gap + inv_h
		bottom_panel.offset_top = vh - (spell_h + gap + inv_h)
	elif spells_visible:
		spell_panel.offset_top = 0.0
		spell_panel.offset_bottom = spell_h
		bottom_panel.offset_top = vh - spell_h
	else:
		inventory_panel.offset_top = 0.0
		inventory_panel.offset_bottom = inv_h
		bottom_panel.offset_top = vh - inv_h
	bottom_panel.offset_bottom = vh

# --- Экономика (P0): панели магазина / школы / таверны ---

var _shop: ShopPanel = null
var _alchemy: AlchemyPanel = null
var _school: SchoolPanel = null
var _inn: InnPanel = null
var _blacksmith: BlacksmithPanel = null
var _inventory_panel: InventoryPanel = null
var _interior_pos := Vector2.ZERO   # позиция героя перед входом в здание
var _in_interior := false
## Узлы HUD, которые прячем на время интерьера. Раньше они оставались видимыми:
## вокруг модального окна было видно «воду» и объекты мира, а кнопка «Закрыть»
## интерьера попадала в полосу склада.
const _HUD_NODES := ["BottomPanel", "RightPanel", "CoordsLabel", "PauseLabel"]

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
	_exit_interior()

## Открыта ли какая-то панель-интерьер (клики не должны двигать героя по карте).
func is_editor_open() -> bool:
	return is_instance_valid(_shop) or is_instance_valid(_alchemy) or is_instance_valid(_school) or is_instance_valid(_inn) or is_instance_valid(_blacksmith) or is_instance_valid(_inventory_panel)

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
	_shop.inventory_changed.connect(refresh_inventory)
	add_child(_shop)
	refresh_inventory()

func open_alchemy() -> void:
	if _alchemy != null and is_instance_valid(_alchemy):
		return
	_enter_interior()
	_alchemy = AlchemyPanel.new()
	_alchemy.setup(player)
	_alchemy.closed.connect(_on_panel_closed)
	_alchemy.inventory_changed.connect(refresh_inventory)
	add_child(_alchemy)
	refresh_inventory()

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

## Кузница: переплавка оружия/брони в слитки (клик по Blacksmith).
func open_blacksmith() -> void:
	if _blacksmith != null and is_instance_valid(_blacksmith):
		return
	_enter_interior()
	_blacksmith = BlacksmithPanel.new()
	_blacksmith.setup(player)
	_blacksmith.closed.connect(_on_panel_closed)
	_blacksmith.inventory_changed.connect(refresh_inventory)
	add_child(_blacksmith)

## Инвентарь и экипировка: модальное окно с куклой, слотами и складом.
func open_inventory_panel() -> void:
	if _inventory_panel != null and is_instance_valid(_inventory_panel):
		return
	_enter_interior()
	_inventory_panel = InventoryPanel.new()
	_inventory_panel.setup(player)
	_inventory_panel.closed.connect(_on_panel_closed)
	_inventory_panel.inventory_changed.connect(_on_inventory_changed)
	add_child(_inventory_panel)

func _on_inventory_changed() -> void:
	refresh_inventory()
	refresh_equipment()
	_update_stats()
