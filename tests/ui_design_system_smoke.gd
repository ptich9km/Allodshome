extends SceneTree
## Сторож единой дизайн-системы интерфейса (scripts/ui_theme.gd, assets/ui/frames/).
##
## Существует потому, что до этого файла оформление расползлось по девяти панелям,
## и это ничем не ловилось. Конкретные классовые дефекты, которые он закрывает:
##
##  1. **Шрифтов не было вообще** (0 .ttf/.otf в проекте). Если файл удалён или
##     не импортирован — падает проверка font_files_exist, а не рантайм-падение
##     в меню. Плюс проверяется НАЛИЧИЕ ГЛИФОВ: шрифт без кириллицы молча
##     превращает весь русский текст в квадраты, и ни один тест это не увидит.
##  2. **`theme = theme` в main_menu.gd** — локальная переменная затеняла
##     свойство `Control.theme`, тема строилась и выбрасывалась, а меню рисовалось
##     на дефолтной теме движка. Проверка theme_reaches_control ловит это по
##     ФАКТУ (variation резолвится в непустой StyleBox), а не по чтению исходника.
##  3. **Палитра расползалась инлайном.** Сторож require_token_usage ловит
##     появление `Color(` в файлах панелей там, где роль должна браться из
##     UiTheme.
##  4. **Поля 9-slice схлопывались бы в ноль.** Такое уже было: у divider высота
##     16 при полях 8+8, центр по Y схлопывался. Генератор это уже проверяет,
##     здесь — независимая проверка по данным на диске.
##
## Запуск: godot --headless --path . --script res://tests/ui_design_system_smoke.gd

const FRAMES_DIR := "res://assets/ui/frames"
const DB_PATH := "res://assets/ui/frames/frames_db.json"

## Панели, уже переведённые на токены. Список растёт по мере миграции:
## главное меню, Esc, HUD-кнопки; интерьеры — следующий заход.
##
## Guard намеренно НЕ включает все девять панелей сразу. Красный с первого дня
## сторож бесполезен: он перестаёт замечать новое, к нему привыкают. Пока
## панель не переведена — она вне зоны контроля, и её цвета ещё разбросаны.
const PANEL_FILES := [
	"res://scripts/main_menu.gd",
	"res://scripts/save_menu.gd",
	"res://scripts/ui.gd",
	"res://scripts/settings_panel.gd",
	"res://scripts/school_panel.gd",
	"res://scripts/alchemy_panel.gd",
	"res://scripts/inventory_panel.gd",
	"res://scripts/shop_panel.gd",
	"res://scripts/inn_panel.gd",
	"res://scripts/workshop_panel.gd",
   "res://scripts/craft_tab.gd",
   "res://scripts/craft_smith_tab.gd",
   "res://scripts/craft_tailor_tab.gd",
]

## Панели, где палитра ещё инлайновая. Пусто — все интерьеры на токенах.
const PANEL_PENDING := []

## Строки, где `Color(` легален даже в панели: собственные оттенки качества,
## сферы, миникарта и смысловые цвета HUD (HP/MP/сопротивления). Это не
## «расползание палитры», а игровые данные/семантика.
const COLOR_EXEMPT := [
	"quality_color", "SPHERE_COLORS", "RESIST_COLORS",
	"MINIMAP", "sphere_color", "set_pixel", "modulate",
	"outline_color", "HUD_HD", "HUD_MP", "RESIST_",
	"_HP_COLOR", "_MP_COLOR", "InvStat",
]

var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(what)


func _run() -> void:
	_check_fonts()
	_check_tokens()
	_check_frames()
	# await обязателен: функция содержит await, и без него корутина возвращается
	# на первой паузе — все её проверки уедут за пределы отчёта и тест будет
	# зелёным на сломанном коде. Этот класс граблей уже стоил проекту двух
	# ложно-зелёных тестов (см. AGENTS.md §12).
	await _check_theme_reaches_control()
	await _check_dividers_are_nine_patch()
	await _check_hud_buttons()
	require_token_usage()
	_report()
	quit(0 if _fails.is_empty() else 1)


## HUD-кнопки не должны быть системными flat-кнопками движка.
func _check_hud_buttons() -> void:
	# Без hero_stats main.tscn уводит в character_select и setup_ui не зовётся.
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.hero_class = "warrior"
	Game.hero_name = "Тест"
	Game.hero_character_id = "mfighter"
	var scene = load("res://scenes/main.tscn")
	if scene == null:
		_check(false, "main.tscn грузится")
		return
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	await create_timer(0.8).timeout
	var ui = game.get("ui") if "ui" in game else null
	_check(ui != null, "GameUI в дереве")
	if ui == null:
		game.queue_free()
		await process_frame
		return
	# setup_ui уже вызван game.gd при загрузке сцены — не дублируем.
	var cmd_buttons: Array = ui.get("cmd_buttons") if "cmd_buttons" in ui else []
	_check(cmd_buttons.size() >= 4, "командные кнопки созданы (%d)" % cmd_buttons.size())
	_check(ui.get_node_or_null("HudSide") != null, "HudSide у миникарты есть")
	_check(ui.get_node_or_null("StatsPanel") == null, "StatsPanel удалён (статы в инвентаре)")
	var themed := 0
	for b in cmd_buttons:
		if b is Button:
			_check(not (b as Button).flat, "командная кнопка не flat")
			var sb = (b as Button).get_theme_stylebox("normal")
			_check(sb is StyleBoxFlat, "командная кнопка: стиль из темы (StyleBoxFlat)")
			if sb is StyleBoxFlat:
				var got: Color = (sb as StyleBoxFlat).bg_color
				_check(not (got.r == got.g and got.g == got.b),
					"фон командной кнопки не серый (%s)" % str(got))
				_check(got.a >= 0.5, "фон командной кнопки не прозрачный (a=%.2f)" % got.a)
				themed += 1
	_check(themed >= 4, "командные кнопки стилизованы (%d из %d)" % [themed, cmd_buttons.size()])
	var stats_btn = ui.get("_stats_toggle_btn") if "_stats_toggle_btn" in ui else null
	if stats_btn is Button:
		_check(not (stats_btn as Button).flat, "кнопка «Статы» не flat")
		_check((stats_btn as Button).theme_type_variation == &"HudCmd",
			"кнопка «Статы»: variation HudCmd")
	game.queue_free()
	await process_frame


# --- 1. Шрифты ---

func _check_fonts() -> void:
	_check(UiTheme.font_files_exist(),
		"все четыре файла шрифтов на месте (PT Sans 2 веса + Philosopher 2 веса)")
	var probe := UiTheme.CYRILLIC_PROBE
	for path in [UiTheme.FONT_BODY_FILE, UiTheme.FONT_BODY_BOLD_FILE,
			UiTheme.FONT_DISPLAY_FILE, UiTheme.FONT_DISPLAY_BOLD_FILE]:
		var font = load(path)
		_check(font is FontFile, "%s загружается как FontFile" % path)
		if not (font is FontFile):
			continue
		var missing := ""
		for i in probe.length():
			var c := probe.unicode_at(i)
			if not (font as FontFile).has_char(c):
				missing += probe[i]
		_check(missing.is_empty(),
			"%s содержит весь русский алфавит (нет: %s)" % [path, missing])

	# Кегли по умолчанию обязаны быть из шкалы, иначе «единый стандарт» — фикция.
	var t := UiTheme.app_theme()
	_check(t.default_font_size == UiTheme.FONT_BODY,
		"кегль по умолчанию = FONT_BODY (%d)" % UiTheme.FONT_BODY)
	_check(t.default_font != null, "проектная тема несёт шрифт")


# --- 2. Токены ---

func _check_tokens() -> void:
	# Шкала кеглей строго возрастающая, иначе «лестница» не лестница.
	var scale := [UiTheme.FONT_MICRO, UiTheme.FONT_BODY, UiTheme.FONT_SUBHEAD,
		UiTheme.FONT_SECTION, UiTheme.FONT_TITLE, UiTheme.FONT_SCREEN]
	for i in range(1, scale.size()):
		_check(int(scale[i]) > int(scale[i - 1]),
			"кегль %d (%d) больше предыдущего (%d)" % [i, scale[i], scale[i - 1]])

	# Шкала отступов — та же история.
	var spaces := [UiTheme.SPACE_1, UiTheme.SPACE_2, UiTheme.SPACE_3,
		UiTheme.SPACE_4, UiTheme.SPACE_5, UiTheme.SPACE_6]
	for i in range(1, spaces.size()):
		_check(int(spaces[i]) > int(spaces[i - 1]),
			"отступ %d (%d) больше предыдущего (%d)" % [i, spaces[i], spaces[i - 1]])

	# Отступ панели от края: за ним обязан быть виден живой мир. Это требование
	# игрока, поэтому оно проверяется числом, а не на глаз.
	_check(UiTheme.SCREEN_INSET > 0 and UiTheme.SCREEN_INSET <= 64,
		"SCREEN_INSET в разумных пределах (=%d, мир виден по краям)" % UiTheme.SCREEN_INSET)

	# Основной текст обязан быть светлее фона, иначе меню нечитаемо.
	_check(UiTheme.TEXT.get_luminance() > UiTheme.PANEL_BG.get_luminance() * 2.0,
		"текст светлее фона панели (%.3f > %.3f)"
			% [UiTheme.TEXT.get_luminance(), UiTheme.PANEL_BG.get_luminance()])
	_check(UiTheme.ACCENT.get_luminance() > UiTheme.PANEL_EDGE.get_luminance(),
		"акцент светлее рамки — заголовок читается на панели")

	# Затемнение не должно съедать контраст текста под панелью.
	_check(UiTheme.SCRIM.a <= 0.6,
		"SCRIM не слишком плотный (alpha=%.2f)" % UiTheme.SCRIM.a)


# --- 3. Рамки 9-slice ---

func _check_frames() -> void:
	var db := {}
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			db = parsed
	_check(not db.is_empty(), "frames_db.json читается и не пуст")
	if db.is_empty():
		return

	var frames: Dictionary = db.get("frames", {})
	_check(frames.size() == 4,
		"в frames_db.json четыре рамки (=%d)" % frames.size())

	for name in frames.keys():
		var spec: Dictionary = frames[name]
		var size: Array = spec.get("size", [])
		var m: Dictionary = spec.get("texture_margin", {})
		var path := "%s/%s.png" % [FRAMES_DIR, name]
		_check(ResourceLoader.exists(path), "рамка %s.png на диске" % name)
		if not ResourceLoader.exists(path):
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		_check(img != null and not img.is_empty(), "рамка %s.png декодируется" % name)
		if img == null or img.is_empty():
			continue
		_check(img.get_size() == Vector2i(int(size[0]), int(size[1])),
			"рамка %s: размер %s совпадает с базой %s"
				% [name, str(img.get_size()), str(size)])

		# Главный инвариант 9-slice: центр плитки не должен схлопнуться в ноль
		# ни по одной оси. Именно так сломался divider (высота 16, поля 8+8).
		var w := int(size[0])
		var h := int(size[1])
		var cx := w - int(m.get("left", 0)) - int(m.get("right", 0))
		var cy := h - int(m.get("top", 0)) - int(m.get("bottom", 0))
		_check(cx >= 1 and cy >= 1,
			"рамка %s: центр плитки не схлопывается (%dx%d из %dx%d)"
				% [name, cx, cy, w, h])

		# Тело рамки непрозрачное: требование «без прозрачности в меню».
		# Исключение — divider: это тонкая орнаментальная линейка, прозрачность
		# в середине у неё по определению, иначе она стала бы полосой во всю
		# ширину панели.
		if name == "divider":
			continue
		var opaque := true
		for px in [Vector2i(1, 1), Vector2i(w / 2, h / 2),
				Vector2i(w - 2, 1), Vector2i(1, h - 2)]:
			if img.get_pixelv(px).a < 0.99:
				opaque = false
		_check(opaque, "рамка %s: тело непрозрачное (alpha=1)" % name)


# --- 4. Тема действительно доходит до контрола ---
## Главный регресс-тест на баг `theme = theme`. Читать исходник бесполезно —
## нужно проверять поведение: variation-стиль, который никто не зарегистрировал,
## Godot отдаёт null, и узел падает на дефолт.

func _check_theme_reaches_control() -> void:
	var packed: PackedScene = load("res://scenes/main_menu.tscn")
	_check(packed != null, "main_menu.tscn загружается")
	if packed == null:
		return
	var menu = packed.instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame

	# Находим кнопку меню и проверяем, что её variation зарегистрирована:
	# без темы стиль пришёл бы из движка, а variation молча игнорировался бы.
	var btn := _first_button(menu)
	_check(btn != null, "в главном меню есть кнопка")
	if btn != null:
		var variation: StringName = btn.theme_type_variation
		_check(variation != &"", "у кнопки задана variation (%s)" % variation)
		var sb: StyleBox = null
		# Ищем владельца темы ВВЕРХ ОТ КНОПКИ, а не от корня сцены: тема лежит
		# на Control внутри CanvasLayer, то есть это потомок корня, а не предок.
		var owner: Node = _theme_owner(btn)
		_check(owner != null,
			"у кнопки есть предок с темой (в CanvasLayer)")
		if owner != null and owner is Control:
			sb = (owner as Control).theme.get_stylebox("normal", variation)
		elif owner != null and owner is Window:
			sb = (owner as Window).theme.get_stylebox("normal", variation)
		_check(sb != null,
			"variation %s резолвится в StyleBox, а не в null" % variation)
		if sb != null:
			_check(sb is StyleBoxFlat,
				"variation %s — StyleBoxFlat (собственный стиль, не движковый)" % variation)

		# ГЛАВНАЯ ПРОВЕРКА: стиль, который РЕАЛЬНО применился к контролу.
		# Проверки темы выше недостаточно: Godot распространяет тему только по
		# Control-дереву и Window, а CanvasLayer НЕ прозрачен для этого обхода.
		# Тема на корне сцены доходила до мира, но не до кнопок внутри
		# CanvasLayer — и все проверки выше были зелёными на сломанном экране:
		# кнопки рисовались дефолтным стилем движка.
		var applied: StyleBox = btn.get_theme_stylebox("normal")
		_check(applied != null, "кнопка получила какой-то стиль")
		if applied is StyleBoxFlat and sb is StyleBoxFlat:
			var got: Color = (applied as StyleBoxFlat).bg_color
			var want: Color = (sb as StyleBoxFlat).bg_color
			_check(got == want,
				"кнопка использует стиль темы, а не движка (bg %s против %s)"
					% [str(got), str(want)])
			# Дефолт движка серый — ровно то, что видел игрок.
			_check(not (got.r == got.g and got.g == got.b),
				"фон кнопки не серый (получено %s)" % str(got))
			_check(got.a >= 0.99,
				"фон кнопки непрозрачный (alpha=%.2f)" % got.a)
		_check(btn.get_theme_font_size("font_size") == UiTheme.FONT_BODY,
			"кегль кнопки из шкалы (%d)" % btn.get_theme_font_size("font_size"))

		# Заголовок обязан быть антиквой крупным кеглем, а не дефолтом 16.
		var title := menu.find_child("Title", true, false)
		if title is Label:
			_check((title as Label).get_theme_font_size("font_size")
				== UiTheme.FONT_SCREEN,
				"заголовок экрана = FONT_SCREEN (%d)"
					% (title as Label).get_theme_font_size("font_size"))

	menu.queue_free()
	await process_frame


## Разделитель-лин��йка нельзя растягивать как картинку: текстура 64 px,
## растянутая до 420, превращала орнамент в толстые жёлтые полосы. Проверяем,
## что на месте именно NinePatchRect с полями из frames_db.
func _check_dividers_are_nine_patch() -> void:
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var div: Node = menu.find_child("Divider", true, false)
	_check(div != null, "разделитель в главном меню есть")
	if div != null:
		_check(div is NinePatchRect,
			"разделитель — NinePatchRect, а не растянутый TextureRect")
		if div is NinePatchRect:
			var n := div as NinePatchRect
			_check(n.patch_margin_left > 0 and n.patch_margin_top > 0,
				"поля 9-slice разделителя заданы (%d, %d)"
					% [n.patch_margin_left, n.patch_margin_top])
			_check(n.texture != null, "текстура разделителя загружена")
	menu.queue_free()
	await process_frame


func _first_button(node: Node) -> Button:
	if node is Button:
		return node
	for c in node.get_children():
		var b := _first_button(c)
		if b != null:
			return b
	return null


## Ближайший Control или Window с темой вверх по дереву. Именно так ищется
## владелец: у главного меню тема лежит на Control ВНУТРИ CanvasLayer, потому
## что Godot не распространяет тему через сам слой.
func _theme_owner(node: Node) -> Node:
	var p: Node = node
	while p != null:
		if (p is Control and (p as Control).theme != null) \
				or (p is Window and (p as Window).theme != null):
			return p
		p = p.get_parent()
	return null


# --- 5. Палитра не расползается инлайном ---

func require_token_usage() -> void:
	for path in PANEL_FILES:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			_check(false, "%s читается" % path)
			continue
		var lines := f.get_as_text().split("\n")
		f.close()
		var offenders: Array[String] = []
		for i in range(lines.size()):
			var line: String = lines[i]
			if not line.contains("Color("):
				continue
			# Комментарии и осмысленные цвета — легальны.
			var stripped: String = line.strip_edges()
			if stripped.begins_with("#") or stripped.begins_with("##"):
				continue
			var exempt := false
			for e in COLOR_EXEMPT:
				if line.contains(e):
					exempt = true
			if exempt:
				continue
			# `var x := Color(` внутри вызова UiKit.add_* — это подстановка
			# роли в тему, а не палитра панели. Помечаем спец-конструкцией,
			# чтобы её можно было отличить от будущего разброса.
			if line.contains("UiTheme."):
				continue
			offenders.append("%s:%d" % [path.get_file(), i + 1])
		_check(offenders.is_empty(),
			"%s: палитра идёт через UiTheme, а не инлайн (%s)"
				% [path.get_file(), str(offenders)])


func _report() -> void:
	print("RESULT: %s ui_design_system_smoke (проверок: %d, провалов: %d)"
			% ["OK" if _fails.is_empty() else "FAIL", _checks, _fails.size()])
	for f in _fails:
		print("  FAIL " + f)