class_name LootBag
extends Node2D
## Мешок с добычей (лут) на месте смерти врага. Подбирается, когда герой
## подходит вплотную: золото в казну, предметы — в склад героя.
##
## Иконки предметов рисуются узлами Sprite2D поверх нарисованного мешочка
## (см. LootIcons): кодовая отрисовка рисует только форму мешка, а что внутри —
## показывают настоящие спрайты из assets/loot_icons/. Показывается не больше
## трёх иконок сеткой сверху, остальное видно в тултипе.

var items: Array = []   # [{"gold": N}] / [{"key": "item_db key"}, ...]
var _player: Node2D = null
var _pick_radius := 26.0

## Размер баночки зелья: задаёт создатель мешка (см. enemy.gd/_make_loot).
## Логика: сильный врач роняет большую баночку, слабый - маленькую.
var potion_size := "small"

const ICON_PX := 16.0        # сторона иконки на земле
const ICON_GAP := 4.0
const ICON_TOP := -14.0      # над мешком

func _ready() -> void:
	z_index = 10
	_player = get_tree().get_first_node_in_group("player")
	add_to_group("loot")
	_build_icons()


## Создаёт спрайты-иконки содержимого. Три слота сеткой над мешком: первая
## строка - оружие, вторая - броня/зелья, третья - золото. Порядок не важен,
## но слева направо читается естественно.
func _build_icons() -> void:
	for c in get_children():
		if c is Sprite2D:
			c.queue_free()
	var show: int = LootIcons.stack_preview(items)
	var slots: Array[Dictionary] = []
	for it in items:
		if not (it is Dictionary):
			continue
		if slots.size() >= show:
			break
		var path := ""
		if it.has("gold"):
			path = LootIcons.gold_icon()
		elif it.has("key"):
			var d := ItemDB.find(str(it.get("key", "")))
			if str(d.get("quality", "")) == "Potion":
				path = LootIcons.icon_for_potion(d, potion_size)
			if path == "":
				path = LootIcons.icon_for(d)
		if path != "":
			slots.append({"path": path, "scale": 1.0})
	if slots.is_empty():
		return
	# сетка 3 в ряд; если больше трёх, LootIcons уже обрезал
	var cols: int = slots.size()
	var start_x := -float(cols - 1) * (ICON_PX + ICON_GAP) * 0.5
	for i in slots.size():
		var s := Sprite2D.new()
		s.texture = load(str(slots[i]["path"]))
		var tex: Texture2D = s.texture
		# ��онки �� loot_icons ��� 32 px, а баночки меньше - масштабируем от
		# размера текстуры, иначе баночка была бы вдвое крупнее меча
		var k := ICON_PX / float(maxi(1, maxi(tex.get_width(), tex.get_height())))
		s.scale = Vector2(k, k)
		s.position = Vector2(start_x + float(i) * (ICON_PX + ICON_GAP), ICON_TOP)
		s.z_index = 1
		add_child(s)

func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	if global_position.distance_to(_player.global_position) < _pick_radius:
		_collect()

func _collect() -> void:
	## Подбор: золото в казну, предметы в склад. После - обязательно
	## refresh_inventory(), иначе склад на экране остаётся старым, пока игрок
	## не откроет его заново (раньше здесь не вызывалось ничего).
	var got_gold := 0
	var got_items: Array[String] = []
	for it in items:
		if it is Dictionary:
			if it.has("gold"):
				var g := int(it.get("gold", 0))
				if g > 0:
					if _player.has_method("add_gold"):
						_player.call("add_gold", g)
					got_gold += g
			elif it.has("key"):
				var key := str(it.get("key", ""))
				if key != "" and _player.has_method("add_item"):
					_player.call("add_item", key)
					got_items.append(key)
	if got_gold > 0:
		print("+%d золота" % got_gold)
	for k in got_items:
		print("+%s" % k)
	if got_gold > 0 or not got_items.is_empty():
		SoundDB.play(1)  # click00
		_notify_ui()
	queue_free()


## Попросить HUD обновить склад. Узел UI НЕ состоит в группе "ui" (в main.tscn
## нет строки groups), поэтому сначала пробуем группу, потом ищем CanvasLayer с
## методом refresh_inventory - тот же приём, что в game.gd:425.
func _notify_ui() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var target: Node = tree.get_first_node_in_group("ui")
	if target == null or not target.has_method("refresh_inventory"):
		target = _find_ui(tree.root)
	if target != null and target.has_method("refresh_inventory"):
		target.call("refresh_inventory")


func _find_ui(from: Node) -> Node:
	if from == null:
		return null
	if from is CanvasLayer and from.has_method("refresh_inventory"):
		return from
	for c in from.get_children():
		var got := _find_ui(c)
		if got != null:
			return got
	return null

func _draw() -> void:
	# Мешочек с добычей (как в оригинале): тёмный корпус со стянутым верхом и узелком
	draw_circle(Vector2(0, 4), 8.0, Color(0.1, 0.07, 0.05, 0.7))                       # тень
	draw_polygon(
		PackedVector2Array([
			Vector2(-6, 0), Vector2(-7, 4), Vector2(-4, 8), Vector2(4, 8),
			Vector2(7, 4), Vector2(6, 0), Vector2(3, -3), Vector2(-3, -3),
		]),
		PackedColorArray([Color(0.45, 0.34, 0.2, 1.0)]))                               # корпус
	draw_polyline(
		PackedVector2Array([
			Vector2(-6, 0), Vector2(-7, 4), Vector2(-4, 8), Vector2(4, 8),
			Vector2(7, 4), Vector2(6, 0), Vector2(3, -3), Vector2(-3, -3), Vector2(-6, 0),
		]),
		Color(0.28, 0.2, 0.12, 1.0), 1.2)
	draw_circle(Vector2(-2, 2), 2.0, Color(0.6, 0.48, 0.3, 1.0))                       # блик
	draw_line(Vector2(-5, -3), Vector2(5, -3), Color(0.33, 0.24, 0.14, 1.0), 2.0)      # завязка
	draw_line(Vector2(0, -4), Vector2(0, -8), Color(0.33, 0.24, 0.14, 1.0), 2.0)       # узелок
	draw_circle(Vector2(0, -8), 1.8, Color(0.85, 0.7, 0.35, 1.0))                      # золотой узел