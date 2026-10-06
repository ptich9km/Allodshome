class_name AlchemyPanel
extends CanvasLayer

signal closed
signal inventory_changed

const RECIPES_PATH := "res://assets/professions/alchemy/recipes.json"

var player: Player
var _recipes: Array[Dictionary] = []
var _selected_index := 0
var _previous_focus: Control
var _recipe_list: VBoxContainer
var _detail: VBoxContainer
var _status_label: Label
var _create_button: Button
var _close_button: Button
var _recipe_buttons: Array[Button] = []

func setup(p: Player) -> void:
	player = p
	layer = 10
	_build_ui()

func _ready() -> void:
	_previous_focus = UiKit.save_focus(self)
	_load_recipes()
	_refresh()

func _build_ui() -> void:
	var dim := UiKit.make_dim(0.66)
	add_child(dim)

	var root := MarginContainer.new()
	root.name = "AlchemyRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_margins(root, 24, 24, 24, 24)
	root.theme = _make_theme()
	add_child(root)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme_type_variation = &"AlchemyPanel"
	root.add_child(panel)

	var margin := MarginContainer.new()
	_set_margins(margin, 20, 18, 20, 18)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"AlchemyTitle"
	title.text = tr("АЛХИМИЯ")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var hint := Label.new()
	hint.theme_type_variation = &"AlchemyHint"
	hint.text = tr("Соберите травы и создайте зелье")
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(hint)

	var body := HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)

	var recipe_panel := PanelContainer.new()
	recipe_panel.theme_type_variation = &"AlchemySection"
	recipe_panel.custom_minimum_size = Vector2(380, 0)
	body.add_child(recipe_panel)
	var recipe_margin := MarginContainer.new()
	_set_margins(recipe_margin, 14, 14, 14, 14)
	recipe_panel.add_child(recipe_margin)
	var recipe_column := VBoxContainer.new()
	recipe_column.add_theme_constant_override("separation", 10)
	recipe_margin.add_child(recipe_column)
	var recipe_title := Label.new()
	recipe_title.theme_type_variation = &"AlchemySectionTitle"
	recipe_title.text = tr("РЕЦЕПТЫ")
	recipe_column.add_child(recipe_title)
	var recipe_scroll := ScrollContainer.new()
	recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	recipe_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	recipe_scroll.follow_focus = true
	recipe_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_column.add_child(recipe_scroll)
	_recipe_list = VBoxContainer.new()
	_recipe_list.name = "RecipeList"
	_recipe_list.add_theme_constant_override("separation", 8)
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_scroll.add_child(_recipe_list)

	var detail_panel := PanelContainer.new()
	detail_panel.theme_type_variation = &"AlchemySection"
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(detail_panel)
	var detail_margin := MarginContainer.new()
	_set_margins(detail_margin, 18, 14, 18, 14)
	detail_panel.add_child(detail_margin)
	_detail = VBoxContainer.new()
	_detail.name = "RecipeDetail"
	_detail.add_theme_constant_override("separation", 10)
	detail_margin.add_child(_detail)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	content.add_child(footer)
	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.theme_type_variation = &"AlchemyHint"
	_status_label.text = tr("Выберите рецепт")
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_status_label)
	_create_button = Button.new()
	_create_button.name = "Create"
	_create_button.text = tr("Создать")
	_create_button.custom_minimum_size = Vector2(180, 46)
	_create_button.pressed.connect(_create_selected)
	footer.add_child(_create_button)
	_close_button = Button.new()
	_close_button.name = "Close"
	_close_button.text = tr("Закрыть")
	_close_button.custom_minimum_size = Vector2(140, 46)
	_close_button.pressed.connect(close)
	footer.add_child(_close_button)

func _load_recipes() -> void:
	_recipes.clear()
	var file := FileAccess.open(RECIPES_PATH, FileAccess.READ)
	if file == null:
		push_error("AlchemyPanel: не открыть " + RECIPES_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	var raw_recipes: Array = parsed.get("recipes", [])
	for raw in raw_recipes:
		if not (raw is Dictionary):
			continue
		var recipe: Dictionary = (raw as Dictionary).duplicate(true)
		if not _recipe_valid(recipe):
			continue
		_recipes.append(recipe)

func _recipe_valid(recipe: Dictionary) -> bool:
	var output := str(recipe.get("output", ""))
	if ItemDB.find(output).is_empty():
		push_error("AlchemyPanel: неизвестный результат " + output)
		return false
	var ingredients: Array = recipe.get("ingredients", [])
	if ingredients.is_empty():
		return false
	for raw in ingredients:
		if not (raw is Dictionary):
			return false
		var key := str(raw.get("item", ""))
		if ItemDB.find(key).is_empty() or int(raw.get("count", 0)) <= 0:
			push_error("AlchemyPanel: неизвестный ингредиент " + key)
			return false
	return true

func _refresh() -> void:
	_clear_container(_recipe_list)
	_clear_container(_detail)
	_recipe_buttons.clear()
	if _selected_index >= _recipes.size():
		_selected_index = 0
	for index in range(_recipes.size()):
		var recipe: Dictionary = _recipes[index]
		var button := Button.new()
		button.name = "Recipe%d" % index
		button.text = "%s %s" % [tr("Рецепт:"), str(recipe.get("name_ru", recipe.get("id", "—")))]
		button.tooltip_text = _recipe_status_text(recipe)
		button.custom_minimum_size = Vector2(0, 54)
		button.theme_type_variation = &"AlchemySelectedRecipeButton" if index == _selected_index else &"AlchemyRecipeButton"
		button.pressed.connect(_select_recipe.bind(index))
		_recipe_list.add_child(button)
		_recipe_buttons.append(button)
	if not _recipes.is_empty():
		_build_detail(_recipes[_selected_index])
		_create_button.disabled = not _has_ingredients(_recipes[_selected_index])
	else:
		_create_button.disabled = true
		_status_label.text = tr("Нет доступных рецептов")
	_configure_focus()
	if not _recipe_buttons.is_empty():
		_recipe_buttons[_selected_index].call_deferred("grab_focus")
	else:
		_close_button.call_deferred("grab_focus")

func _select_recipe(index: int) -> void:
	_selected_index = clampi(index, 0, _recipes.size() - 1)
	_status_label.text = tr("Выбран рецепт")
	_refresh()

func _build_detail(recipe: Dictionary) -> void:
	var output_key := str(recipe.get("output", ""))
	var output := ItemDB.find(output_key)
	var heading := Label.new()
	heading.theme_type_variation = &"AlchemyRecipeTitle"
	heading.text = str(recipe.get("name_ru", output_key))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_child(heading)
	var icon := TextureRect.new()
	var icon_path := str(output.get("icon", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(0, 110)
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(icon)
	var result := Label.new()
	result.theme_type_variation = &"AlchemyResultLabel"
	result.text = tr("Результат: %s ×%d") % [str(output.get("name_ru", output_key)), int(recipe.get("output_count", 1))]
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_child(result)
	var divider := HSeparator.new()
	_detail.add_child(divider)
	var ingredients_title := Label.new()
	ingredients_title.theme_type_variation = &"AlchemySectionTitle"
	ingredients_title.text = tr("Ингредиенты")
	_detail.add_child(ingredients_title)
	for raw in recipe.get("ingredients", []):
		_detail.add_child(_make_ingredient_row(raw))

func _make_ingredient_row(raw: Dictionary) -> PanelContainer:
	var item_key := str(raw.get("item", ""))
	var required := int(raw.get("count", 0))
	var current := _item_count(item_key)
	var item := ItemDB.find(item_key)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"AlchemyIngredientSlot"
	var margin := MarginContainer.new()
	_set_margins(margin, 8, 6, 8, 6)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var icon := TextureRect.new()
	var icon_path := str(item.get("icon", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(46, 46)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var name_label := Label.new()
	name_label.text = str(item.get("name_ru", item_key))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	var count_label := Label.new()
	count_label.theme_type_variation = &"AlchemyIngredientOk" if current >= required else &"AlchemyIngredientMissing"
	count_label.text = tr("Есть %d / нужно %d") % [current, required]
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(count_label)
	return panel

func _item_count(key: String) -> int:
	var count := 0
	if is_instance_valid(player):
		for item_key in player.inventory:
			if str(item_key) == key:
				count += 1
	return count

func _has_ingredients(recipe: Dictionary) -> bool:
	for raw in recipe.get("ingredients", []):
		if _item_count(str(raw.get("item", ""))) < int(raw.get("count", 0)):
			return false
	return true

func _recipe_status_text(recipe: Dictionary) -> String:
	if _has_ingredients(recipe):
		return tr("Все ингредиенты доступны")
	return tr("Не хватает ингредиентов")

func _create_selected() -> void:
	if not is_instance_valid(player) or _recipes.is_empty():
		return
	var recipe: Dictionary = _recipes[_selected_index]
	if not _has_ingredients(recipe):
		_status_label.text = tr("Не хватает ингредиентов")
		return
	for raw in recipe.get("ingredients", []):
		var item_key := str(raw.get("item", ""))
		for _count in range(int(raw.get("count", 0))):
			if not player.remove_item(item_key):
				return
	var output_key := str(recipe.get("output", ""))
	for _count in range(int(recipe.get("output_count", 1))):
		player.add_item(output_key)
	SoundDB.play(9)
	inventory_changed.emit()
	_status_label.text = tr("Создано: %s") % str(recipe.get("name_ru", output_key))
	_refresh()

func _configure_focus() -> void:
	for index in range(_recipe_buttons.size()):
		var button := _recipe_buttons[index]
		button.focus_previous = _recipe_buttons[maxi(index - 1, 0)].get_path()
		button.focus_next = _recipe_buttons[mini(index + 1, _recipe_buttons.size() - 1)].get_path()
	if not _recipe_buttons.is_empty():
		_recipe_buttons[-1].focus_next = _create_button.get_path()
		_create_button.focus_previous = _recipe_buttons[-1].get_path()
	_create_button.focus_next = _close_button.get_path()
	_close_button.focus_previous = _create_button.get_path()

func _clear_container(container: Container) -> void:
	UiKit.clear(container)

func _set_margins(container: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
	UiKit.set_margins(container, left, top, right, bottom)

func _make_theme() -> Theme:
	# Единый тёплый стиль интерьера (UiTheme). Зелёный оттенок убран: «по стилю»
	# означает один источник правды, а не отдельную палитру алхимии.
	var theme := UiTheme.app_theme()
	theme.set_stylebox("normal", "Button", UiKit.button_style(
		UiTheme.PANEL_INNER, UiTheme.PANEL_EDGE,
		UiTheme.BORDER_NORMAL, UiTheme.RADIUS_PANEL, UiTheme.SPACE_2))
	theme.set_stylebox("hover", "Button", UiKit.button_style(
		UiTheme.PANEL_INNER.lightened(0.12), UiTheme.ACCENT_DIM,
		UiTheme.BORDER_NORMAL, UiTheme.RADIUS_PANEL, UiTheme.SPACE_2))
	theme.set_stylebox("pressed", "Button", UiKit.button_style(
		UiTheme.BG_DEEP, UiTheme.PANEL_EDGE,
		UiTheme.BORDER_NORMAL, UiTheme.RADIUS_PANEL, UiTheme.SPACE_2))
	theme.set_stylebox("focus", "Button", UiKit.button_style(
		UiTheme.TRANSPARENT, UiTheme.ACCENT,
		UiTheme.BORDER_FOCUS, UiTheme.RADIUS_PANEL, UiTheme.SPACE_2))
	UiKit.apply_scrollbar(theme, UiTheme.RADIUS_SLOT, UiTheme.SPACE_1)
	UiKit.add_panel(theme, &"AlchemyPanel",
		UiTheme.PANEL_BG, UiTheme.PANEL_EDGE, UiTheme.RADIUS_FRAME)
	UiKit.add_panel(theme, &"AlchemySection",
		UiTheme.PANEL_INNER, UiTheme.PANEL_EDGE.darkened(0.2), UiTheme.RADIUS_PANEL)
	UiKit.add_panel(theme, &"AlchemyIngredientSlot",
		UiTheme.SLOT_BG, UiTheme.SLOT_EDGE, UiTheme.RADIUS_SLOT)
	UiTheme.add_display_label(theme, &"AlchemyTitle", UiTheme.FONT_TITLE, UiTheme.ACCENT)
	UiKit.add_label(theme, &"AlchemySectionTitle", UiTheme.TEXT_MUTED, UiTheme.FONT_SECTION)
	UiKit.add_label(theme, &"AlchemyRecipeTitle", UiTheme.TEXT, UiTheme.FONT_SUBHEAD)
	UiKit.add_label(theme, &"AlchemyResultLabel", UiTheme.TEXT, UiTheme.FONT_BODY)
	UiKit.add_label(theme, &"AlchemyHint", UiTheme.TEXT_MUTED, UiTheme.FONT_BODY)
	UiKit.add_label(theme, &"AlchemyIngredientOk", UiTheme.SUCCESS, UiTheme.FONT_BODY)
	UiKit.add_label(theme, &"AlchemyIngredientMissing", UiTheme.DANGER, UiTheme.FONT_BODY)
	UiKit.add_button(theme, &"AlchemyRecipeButton",
		UiTheme.PANEL_INNER, UiTheme.PANEL_EDGE.darkened(0.25),
		UiTheme.PANEL_INNER.lightened(0.12), UiTheme.ACCENT_DIM,
		UiTheme.RADIUS_SLOT, UiTheme.SPACE_2)
	UiKit.add_button(theme, &"AlchemySelectedRecipeButton",
		UiTheme.PANEL_INNER.lightened(0.16), UiTheme.ACCENT,
		UiTheme.PANEL_INNER.lightened(0.20), UiTheme.ACCENT,
		UiTheme.RADIUS_SLOT, UiTheme.SPACE_2)
	return theme


func _input(event: InputEvent) -> void:
	if UiKit.esc_pressed(event):
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	UiKit.restore_focus(_previous_focus)
	closed.emit()
	queue_free()
