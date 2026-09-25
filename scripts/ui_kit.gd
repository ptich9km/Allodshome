class_name UiKit
extends RefCounted
## Общий UI-слой проекта: палитры, фабрики StyleBox и хелперы вёрстки.
##
## До UiKit в каждой панели лежала своя копия `_make_theme()`, `_set_margins`,
## `_clear_grid`, обработки Esc и восстановления фокуса — четыре побайтово
## одинаковых `_set_margins` и три точных дубликата variation-имён
## (InnTitle ≡ ShopTitle, InnGoldLabel ≡ ShopGoldLabel,
##  InnRecruitSlot ≡ ShopItemSlot). Здесь всё это живёт в одном месте.
##
## Панели передают свою палитру в `base_theme(spec)` и добавляют сверху
## только свои variation-имена, поэтому вид не меняется.

# --- Общие константы палитры (были продублированы в inn и shop) ---
const TITLE_COLOR := Color(1.0, 0.78, 0.36)
const TITLE_SIZE := 28
const GOLD_COLOR := Color(1.0, 0.88, 0.42)
const GOLD_SIZE := 19
const SECTION_COLOR := Color(1.0, 0.76, 0.36)
const SECTION_SIZE := 18
const HINT_COLOR := Color(0.90, 0.84, 0.68)
const HINT_SIZE := 14
## Слот предмета: одинаков в таверне (InnRecruitSlot) и магазине (ShopItemSlot).
const SLOT_BG := Color(0.08, 0.07, 0.08, 0.80)
const SLOT_BORDER := Color(0.58, 0.36, 0.16, 0.96)
## Диалог-панель: inn 0.86 против shop 0.88 — оставляем разные, чтобы не менять вид.
const DIALOG_BORDER := Color(0.72, 0.46, 0.18, 0.96)

const SPHERE_COLORS := {
	"Fire": Color(1.0, 0.4, 0.1),
	"Water": Color(0.2, 0.6, 1.0),
	"Air": Color(0.8, 0.9, 1.0),
	"Earth": Color(0.6, 0.4, 0.2),
	"Astral": Color(0.7, 0.3, 0.9),
}


# === Фабрики стилей ===

static func button_style(background: Color, border: Color, width: int = 2,
		radius: int = 6, content_margin: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(content_margin)
	return style


static func panel_style(background: Color, border: Color, radius: int = 5,
		width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


## Кнопка-«чип» без заливки: нормальное состояние полностью прозрачное.
static func ghost_button_style(border: Color, width: int = 2, radius: int = 6,
		content_margin: int = 6) -> StyleBoxFlat:
	return button_style(Color(0, 0, 0, 0), border, width, radius, content_margin)


# === Базовая тема ===

## Спецификация панели. Обязательны только radius/margin — остальное берётся
## из «тёплой» палитры таверны/магазина/кузницы, чтобы кнопки во всём
## интерьере выглядели одинаково.
##   font_size, font_color, radius, margin, disabled, scrollbar,
##   normal_bg, normal_border, hover_bg, hover_border, focus_border
static func base_theme(spec: Dictionary = {}) -> Theme:
	var radius := int(spec.get("radius", 6))
	var margin := int(spec.get("margin", 6))
	var font_size := int(spec.get("font_size", 14))
	var font_color: Color = spec.get("font_color", Color(0.96, 0.88, 0.70))
	var theme := Theme.new()
	theme.default_font_size = font_size
	theme.set_color("font_color", "Label", font_color)
	theme.set_color("font_hover_color", "Button",
		spec.get("font_hover_color", Color(1.0, 0.92, 0.62)))
	theme.set_color("font_pressed_color", "Button",
		spec.get("font_pressed_color", Color(1.0, 1.0, 0.90)))
	theme.set_color("font_focus_color", "Button",
		spec.get("font_focus_color", Color(1.0, 0.90, 0.48)))
	theme.set_color("font_disabled_color", "Button",
		spec.get("font_disabled_color", Color(0.60, 0.55, 0.48)))

	var normal_bg: Color = spec.get("normal_bg", Color(0.24, 0.13, 0.07, 0.96))
	var normal_border: Color = spec.get("normal_border", Color(0.70, 0.40, 0.14))
	var hover_bg: Color = spec.get("hover_bg", Color(0.36, 0.19, 0.08, 0.98))
	var hover_border: Color = spec.get("hover_border", Color(1.0, 0.74, 0.26))
	var pressed_bg: Color = spec.get("pressed_bg", Color(0.15, 0.08, 0.04, 1.0))
	var pressed_border: Color = spec.get("pressed_border", Color(0.66, 0.36, 0.12))
	var disabled_bg: Color = spec.get("disabled_bg", Color(0.16, 0.14, 0.13, 0.88))
	var disabled_border: Color = spec.get("disabled_border", Color(0.35, 0.30, 0.26))
	var focus_border: Color = spec.get("focus_border", Color(1.0, 0.78, 0.20))

	theme.set_stylebox("normal", "Button",
		button_style(normal_bg, normal_border, 2, radius, margin))
	theme.set_stylebox("hover", "Button",
		button_style(hover_bg, hover_border, 2, radius, margin))
	theme.set_stylebox("pressed", "Button",
		button_style(pressed_bg, pressed_border, 2, radius, margin))
	theme.set_stylebox("disabled", "Button",
		button_style(disabled_bg, disabled_border, 2, radius, margin))
	theme.set_stylebox("focus", "Button",
		button_style(Color(normal_bg.r, normal_bg.g, normal_bg.b, 0.0), focus_border, 3,
			radius, margin))
	if bool(spec.get("scrollbar", false)):
		apply_scrollbar(theme, radius, margin)
	return theme


## Золотой стиль полосы прокрутки. Раньше он жил только в shop_panel, поэтому
## скролл рецептов в алхимии оставался системным серым.
static func apply_scrollbar(theme: Theme, radius: int = 5, margin: int = 4) -> void:
	theme.set_stylebox("scroll", "VScrollBar",
		panel_style(Color(0.04, 0.03, 0.02, 0.38), Color(0, 0, 0, 0), radius))
	theme.set_stylebox("scroll_focus", "VScrollBar",
		panel_style(Color(0.04, 0.03, 0.02, 0.38), Color(0, 0, 0, 0), radius))
	theme.set_stylebox("grabber", "VScrollBar",
		panel_style(Color(0.62, 0.38, 0.16, 0.72), Color(0.94, 0.66, 0.24, 0.90), radius))
	theme.set_stylebox("grabber_highlight", "VScrollBar",
		panel_style(Color(0.82, 0.52, 0.20, 0.88), Color(1.0, 0.80, 0.34, 1.0), radius))
	theme.set_stylebox("grabber_pressed", "VScrollBar",
		panel_style(Color(0.96, 0.64, 0.22, 0.96), Color(1.0, 0.88, 0.48, 1.0), radius))
	theme.set_constant("grabber_minimum_height", "VScrollBar", 24)
	theme.set_constant("grabber_offset", "VScrollBar", 2)
	theme.set_stylebox("grabber_area", "VScrollBar",
		panel_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))


# === Хелперы variation-имён ===

static func add_label(theme: Theme, name: StringName, color: Color, size: int = 0) -> void:
	theme.set_type_variation(name, &"Label")
	theme.set_color("font_color", name, color)
	if size > 0:
		theme.set_font_size("font_size", name, size)


static func add_panel(theme: Theme, name: StringName, bg: Color, border: Color,
		radius: int = 5) -> void:
	# variation-имя не может совпадать с именем встроенного класса:
	# Theme.set_type_variation() падает с C++-ошибкой на PanelContainer.
	var variation: StringName = name
	if variation == &"PanelContainer":
		push_warning("UiKit.add_panel: variation-имя не должно быть 'PanelContainer', подменено")
		variation = &"PanelContainerVar"
	theme.set_type_variation(variation, &"PanelContainer")
	theme.set_stylebox("panel", variation, panel_style(bg, border, radius))


## Заголовок и сумма золота — общие для таверны, магазина и школы.
static func add_title(theme: Theme, name: StringName, color: Color = TITLE_COLOR,
		size: int = TITLE_SIZE) -> void:
	add_label(theme, name, color, size)


static func add_gold_label(theme: Theme, name: StringName) -> void:
	add_label(theme, name, GOLD_COLOR, GOLD_SIZE)


static func add_slot(theme: Theme, name: StringName) -> void:
	add_panel(theme, name, SLOT_BG, SLOT_BORDER, 5)


## Кнопка-вариация из пяти состояний по двум цветам.
static func add_button(theme: Theme, name: StringName, normal: Color, border: Color,
		hover: Color, hover_border: Color, radius: int = 6, margin: int = 6) -> void:
	theme.set_type_variation(name, &"Button")
	theme.set_stylebox("normal", name, button_style(normal, border, 2, radius, margin))
	theme.set_stylebox("hover", name, button_style(hover, hover_border, 2, radius, margin))
	theme.set_stylebox("pressed", name,
		button_style(hover.darkened(0.35), border, 2, radius, margin))
	theme.set_stylebox("disabled", name,
		button_style(Color(0.12, 0.11, 0.10, 0.85), border.darkened(0.4), 2, radius, margin))
	theme.set_stylebox("focus", name,
		button_style(Color(0, 0, 0, 0), Color(1.0, 0.94, 0.42), 3, radius, margin))


# === Хелперы вёрстки ===

static func set_margins(container: MarginContainer, left: int, top: int,
		right: int, bottom: int) -> void:
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_bottom", bottom)


## Затемнение фона под модальным окном. alpha разный у разных панелей,
## поэтому параметр обязательный.
static func make_dim(alpha: float) -> ColorRect:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, alpha)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	return dim


static func clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


## Esc — закрыть панель. Раньше в 4 файлах копия условия, причём в
## school_panel.gd ещё и без `not event.echo` (авто-повтор дёргал панель).
static func esc_pressed(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE


## Запомнить элемент, который был в фокусе до открытия панели.
## Панели — это CanvasLayer, поэтому параметр Node, а не CanvasItem.
static func save_focus(node: Node) -> Control:
	if node == null or not is_instance_valid(node):
		return null
	var viewport := node.get_viewport()
	return null if viewport == null else viewport.gui_get_focus_owner()


static func restore_focus(previous: Control) -> void:
	if previous != null and is_instance_valid(previous):
		previous.call_deferred("grab_focus")


## Навигация по сетке кнопок: соседи влево/вправо/вверх/вниз + Tab.
## Логика перенесена из shop_panel.gd:_wire_grid_focus без изменений.
static func wire_grid_focus(buttons: Array[Button], columns: int) -> void:
	if columns <= 0 or buttons.is_empty():
		return
	for index in range(buttons.size()):
		var row := index / columns
		var column := index % columns
		var left: Button = buttons[row * columns + maxi(column - 1, 0)]
		var right: Button = buttons[mini(row * columns + mini(column + 1, columns - 1),
			buttons.size() - 1)]
		buttons[index].focus_neighbor_left = left.get_path()
		buttons[index].focus_neighbor_right = right.get_path()
		buttons[index].focus_neighbor_top = buttons[maxi(index - columns, 0)].get_path()
		buttons[index].focus_neighbor_bottom = buttons[mini(index + columns,
			buttons.size() - 1)].get_path()
		buttons[index].focus_previous = buttons[maxi(index - 1, 0)].get_path()
		buttons[index].focus_next = buttons[mini(index + 1, buttons.size() - 1)].get_path()


## Равномерно масштабирует корень панели под окно от дизайнерского размера.
## Логика перенесена из inn/shop/blacksmith (_DESIGN_SIZE = 1024×1024).
static func fit_design_root(root: Control, design_size: Vector2) -> void:
	if not is_instance_valid(root):
		return
	var viewport := root.get_viewport()
	if viewport == null:
		return
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	var factor := minf(viewport_size.x / design_size.x, viewport_size.y / design_size.y)
	root.scale = Vector2.ONE * factor
	root.position = (viewport_size - design_size * factor) * 0.5


## Подключить пересчёт масштаба к изменению размера окна.
## Передаётся именно handler панели, а не лямбда, — чтобы `_exit_tree` панели
## мог отключить ту же связь (`_update_layout`) по имени метода.
## Источник сигнала: Window (`size_changed`) либо Control (`resized`) — панели
## передают разное, поэтому поддерживаем оба.
static func bind_resize(source: Node, handler: Callable) -> void:
	if source == null or not is_instance_valid(source):
		return
	var signal_name := "resized" if source is Control else "size_changed"
	if not source.has_signal(signal_name):
		return
	if not source.is_connected(signal_name, handler):
		source.connect(signal_name, handler)
	if handler.is_valid():
		handler.call()
