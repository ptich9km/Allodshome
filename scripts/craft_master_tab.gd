class_name CraftMasterTab
extends CraftSmithTab

## Вкладка мастера: улучшение крафтовой вещи на следующий уровень.
##
## Берёт Crafted / Crafted Fine из инвентаря и поднимает вверх по
## TIER_QUALITY_LONG. Стоимость — доля ресурсов рецепта (50% до улучшенной,
## 100% + эссенция до мастерской). Навык mastering растёт от улучшений.

func _decor_path() -> String:
	return "res://assets/professions/workshop/furnace.png"


func _items() -> Array:
	var out: Array = []
	for raw in _inventory_items():
		var item: Dictionary = raw["item"]
		if not ItemDB.is_equippable(item):
			continue
		var t := CraftDB.next_tier(item)
		if t < 0:
			continue
		var out_key := CraftDB.upgrade_key(item)
		if out_key == "" or ItemDB.find(out_key).is_empty():
			continue
		out.append({
			"mode": RECYCLE_ID,
			"key": str(raw["key"]),
			"item": item,
			"count": int(raw["count"]),
			"upgrade": out_key,
			"next_tier": t,
		})
	return out


func _item_label(entry: Dictionary) -> String:
	if str(entry.get("mode", "")) != RECYCLE_ID:
		return super._item_label(entry)
	var item: Dictionary = entry["item"]
	var t := int(entry.get("next_tier", 0))
	var tag := "→ Fine" if t == CraftDB.TIER_IMPROVED else "→ Master"
	return "  %s  [%s]" % [str(item.get("name_ru", entry["key"])), tag]


func _action_label(entry: Dictionary) -> String:
	if str(entry.get("mode", "")) == RECYCLE_ID and not entry.get("upgrade", "").is_empty():
		return tr("Улучшить")
	return super._action_label(entry)


func _action_block_reason(entry: Dictionary) -> String:
	if str(entry.get("mode", "")) == RECYCLE_ID and not entry.get("upgrade", "").is_empty():
		if not is_instance_valid(player):
			return tr("Нет героя")
		var item: Dictionary = entry["item"]
		var cost := CraftDB.upgrade_cost(item)
		var ingot_key := ItemDB.ingot_key(str(item.get("material", "")))
		var checks := [
			[ingot_key, int(cost.get("ingot", 0))],
			[CraftDB.FABRIC_KEY, int(cost.get("fabric", 0))],
			[CraftDB.ESSENCE_KEY, int(cost.get("essence", 0))],
		]
		for c in checks:
			var k := str(c[0])
			var n := int(c[1])
			if n <= 0:
				continue
			if _item_count(k) < n:
				return tr("Не хватает: %s") % str(ItemDB.find(k).get("name_ru", k))
		return ""
	return super._action_block_reason(entry)


func _perform(entry: Dictionary) -> String:
	if str(entry.get("mode", "")) == RECYCLE_ID and not entry.get("upgrade", "").is_empty():
		return CraftDB.upgrade_item(player, str(entry.get("key", "")))
	return super._perform(entry)


func _build_detail(entry: Dictionary) -> void:
	if str(entry.get("mode", "")) != RECYCLE_ID or entry.get("upgrade", "").is_empty():
		super._build_detail(entry)
		return
	var item: Dictionary = entry["item"]
	var out_key := str(entry.get("upgrade", ""))
	var out := ItemDB.find(out_key)
	var cost := CraftDB.upgrade_cost(item)
	_detail.add_child(_heading(str(item.get("name_ru", entry["key"]))))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_3)
	_detail.add_child(row)
	row.add_child(_make_icon(item, Vector2(72, 72)))
	var arrow := Label.new()
	arrow.text = "→"
	arrow.theme_type_variation = &"CraftTitle"
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(arrow)
	row.add_child(_make_icon(out, Vector2(72, 72)))

	_detail.add_child(_section(tr("Стоимость улучшения")))
	var ingot_key := ItemDB.ingot_key(str(item.get("material", "")))
	if int(cost.get("ingot", 0)) > 0:
		_detail.add_child(_make_cost_row(ingot_key, int(cost["ingot"])))
	if int(cost.get("fabric", 0)) > 0:
		_detail.add_child(_make_cost_row(CraftDB.FABRIC_KEY, int(cost["fabric"])))
	if int(cost.get("essence", 0)) > 0:
		_detail.add_child(_make_cost_row(CraftDB.ESSENCE_KEY, int(cost["essence"])))
	_detail.add_child(_note(tr("Мастер улучшает крафтовые вещи. Навык растёт от улучшений.")))


func _make_cost_row(item_key: String, required: int) -> Control:
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


func _variation_prefix() -> String:
	return "CraftMaster"


func _build_recipe_detail(entry: Dictionary) -> void:
	_detail.add_child(_make_hint(tr(
		"Выберите крафтовую вещь в списке — мастер улучшит её уровень.")))
