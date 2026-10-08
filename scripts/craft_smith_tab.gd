class_name CraftSmithTab
extends CraftTab

## Вкладка кузнеца: переплавка сломанной брони/оружия в слитки + ткань,
## и крафт брони/оружия по рецептам (много слитков + немного ткани).
##
## ПОРЯДОК СПИСКА. Сначала ПЕРЕРАБОТКА, потом РЕЦЕПТЫ, и это не украшение:
## переработка - единственный источник металла в игре, и прятать её под
## рецептами значит заставлять игрока гадать, откуда брать слитки.

func _decor_path() -> String:
	return "res://assets/professions/workshop/anvil.png"


func _items() -> Array:
	var out: Array = []
	for raw in _inventory_items():
		var item: Dictionary = raw["item"]
		if not CraftDB.can_recycle(CraftDB.SMITH, item):
			continue
		out.append({
			"mode": RECYCLE_ID,
			"key": str(raw["key"]),
			"item": item,
			"count": int(raw["count"]),
		})
	out.append({"mode": RECIPE_ID, "id": "", "recipe": {}})
	# Только рецепты со свитком в инвентаре — петля лавки.
	for r in CraftDB.known_recipes(CraftDB.SMITH, player):
		out.append({"mode": RECIPE_ID, "id": str(r.get("id", "")), "recipe": r})
	return out


func _item_label(entry: Dictionary) -> String:
	if str(entry.get("mode", "")) == RECYCLE_ID:
		var item: Dictionary = entry["item"]
		var mark := "" if ItemDB.is_broken(item) else "  [целое]"
		return "  %s  ×%d%s" % [str(item.get("name_ru", entry["key"])), int(entry["count"]), mark]
	var recipe: Dictionary = entry.get("recipe", {})
	if recipe.is_empty():
		return tr("— Рецепты (нужен свиток) —")
	return "    %s" % str(recipe.get("name_ru", entry.get("id", "")))


func _build_detail(entry: Dictionary) -> void:
	if str(entry.get("mode", "")) == RECYCLE_ID:
		_build_recycle_detail(entry)
	else:
		_build_recipe_detail(entry)


func _build_recycle_detail(entry: Dictionary) -> void:
	var item: Dictionary = entry["item"]
	var y := CraftDB.recycle_yield(item)
	_detail.add_child(_heading(str(item.get("name_ru", entry["key"]))))
	if ItemDB.is_broken(item):
		_detail.add_child(_note(tr("Сломанная вещь: выход по качеству.")))
	else:
		_detail.add_child(_note(tr("Целая вещь: выход = 80%% ресурсов крафта.")))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_3)
	_detail.add_child(row)
	row.add_child(_make_icon(item, Vector2(72, 72)))

	var got := VBoxContainer.new()
	got.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	got.add_theme_constant_override("separation", 2)
	row.add_child(got)
	got.add_child(_line(tr("Качество: %s") % str(item.get("quality", ""))))
	got.add_child(_line(tr("В наличии: %d шт") % int(entry["count"])))
	got.add_child(HSeparator.new())
	if int(y.get("ingot", 0)) > 0:
		var ingot_key := ItemDB.ingot_key(str(item.get("material", "")))
		var ingot := ItemDB.find(ingot_key)
		got.add_child(_line("%s ×%d" % [
			str(ingot.get("name_ru", ingot_key)), int(y["ingot"])]))
	if int(y.get("fabric", 0)) > 0:
		got.add_child(_line("%s ×%d" % [str(ItemDB.find(CraftDB.FABRIC_KEY)
			.get("name_ru", CraftDB.FABRIC_KEY)), int(y["fabric"])]))
	if int(y.get("essence", 0)) > 0:
		got.add_child(_line("%s ×%d" % [str(ItemDB.find(CraftDB.ESSENCE_KEY)
			.get("name_ru", CraftDB.ESSENCE_KEY)), int(y["essence"])]))
	if int(y.get("ingot", 0)) == 0 and int(y.get("fabric", 0)) == 0 \
			and int(y.get("essence", 0)) == 0:
		got.add_child(_line(tr("Нет ресурсов для переплавки")))


func _build_recipe_detail(entry: Dictionary) -> void:
	var recipe: Dictionary = entry.get("recipe", {})
	if recipe.is_empty():
		_detail.add_child(_make_hint(tr(
			"Сломанные вещи дают слитки и ткань. Из них варится новая вещь.")))
		return
	_detail.add_child(_heading(str(recipe.get("name_ru", entry.get("id", "")))))
	_detail.add_child(_tier_cards(recipe))
	_detail.add_child(HSeparator.new())
	_detail.add_child(_section(tr("Ингредиенты")))
	for ing in recipe.get("inputs", []):
		_detail.add_child(_make_ingredient_row(ing))


# --- Общие для всех вкладок куски -----------------------------------------

## Три уровня выхода одной вещи. Текстура у них общая, различаются числа и
## свечение, поэтому показываем карточку на каждый уровень.
func _tier_cards(recipe: Dictionary) -> Control:
	var outs := HBoxContainer.new()
	outs.add_theme_constant_override("separation", UiTheme.SPACE_2)
	var weights := CraftDB.tier_weights(_skill())
	var count := (recipe.get("outputs", []) as Array).size()
	for tier in count:
		var oitem := ItemDB.find(CraftDB.output_key(recipe, tier))
		outs.add_child(_make_tier_card(oitem, weights[tier]))
	return outs


func _make_tier_card(item: Dictionary, weight: float) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CraftTierCard"
	var m := MarginContainer.new()
	_set_margins(m, UiTheme.SPACE_1, UiTheme.SPACE_1, UiTheme.SPACE_1, UiTheme.SPACE_1)
	panel.add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	m.add_child(box)
	box.add_child(_make_icon(item, Vector2(56, 56)))
	var name_label := Label.new()
	name_label.theme_type_variation = &"CraftHint"
	name_label.text = "%s\n%.0f%%" % [
		CraftDB.TIER_QUALITY_LONG[CraftVFX.tier_of_item(item)], weight]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	return panel


func _make_ingredient_row(raw: Dictionary) -> Control:
	var item_key := str(raw.get("item", ""))
	var required := int(raw.get("count", 0))
	var current := _item_count(item_key)
	var item := ItemDB.find(item_key)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CraftIngredient"
	var m := MarginContainer.new()
	_set_margins(m, UiTheme.SPACE_2, UiTheme.SPACE_1, UiTheme.SPACE_2, UiTheme.SPACE_1)
	panel.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_2)
	m.add_child(row)
	row.add_child(_make_icon(item, Vector2(40, 40)))
	var name_label := Label.new()
	name_label.text = str(item.get("name_ru", item_key))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	var count_label := Label.new()
	count_label.theme_type_variation = &"CraftIngredientOk" \
		if current >= required else &"CraftIngredientMissing"
	count_label.text = tr("Есть %d / нужно %d") % [current, required]
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(count_label)
	return panel


func _heading(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"CraftTitle"
	l.text = text
	return l


func _section(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"CraftSection"
	l.text = text
	return l


func _line(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _note(text: String) -> Label:
	var l := _make_hint(text)
	return l