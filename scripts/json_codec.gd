class_name JsonSafe
extends RefCounted
## Рекурсивное преобразование значений Godot в JSON-безопасную форму и обратно.
##
## Зачем: в данных мира (WorldState) и в состоянии героя лежат Vector2 и
## Color. JSON.stringify на них не возвращает исходный тип — координаты
## либо теряются, либо превращаются в строку.
##
## Проверить это сравнением словарей в памяти невозможно: to_dict() →
## from_dict() без участия JSON проходит, а записанный на диск файл уже битый.
## Поэтому проверка обязана идти через реальный stringify → parse_string
## (см. tests/save_smoke.gd).
##
## Формат тега — самодостаточный словарь с ключом "__t", поэтому не зависит
## от порядка ключей и не путается с обычными данными пользователя.

const TAG := "__t"

## Значение → JSON-безопасная форма. Контейнеры обходятся рекурсивно.
static func encode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return v
		TYPE_FLOAT:
			return v
		TYPE_VECTOR2:
			return {TAG: "v2", "x": v.x, "y": v.y}
		TYPE_VECTOR2I:
			return {TAG: "v2i", "x": v.x, "y": v.y}
		TYPE_VECTOR3:
			return {TAG: "v3", "x": v.x, "y": v.y, "z": v.z}
		TYPE_COLOR:
			return {TAG: "c", "r": v.r, "g": v.g, "b": v.b, "a": v.a}
		TYPE_DICTIONARY:
			var out := {}
			for key in v:
				out[_encode_key(key)] = encode(v[key])
			return out
		TYPE_ARRAY:
			var arr := []
			for item in v:
				arr.append(encode(item))
			return arr
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var arr2 := []
			for item in v:
				arr2.append(encode(item))
			return arr2
		_:
			# Неизвестный тип (Node, Object, Callable...) в JSON попадать не
			# должен. Сохраняем как строку с типом, чтобы не потерять молча.
			push_warning("JsonSafe.encode: тип %d не поддерживается, записан как строка" % typeof(v))
			return {TAG: "raw", "t": type_string(typeof(v)), "v": str(v)}


static func _encode_key(key: Variant) -> Variant:
	# Ключи словарей в Godot бывают String/и т.п. JSON требует строки,
	# поэтому не-строковый ключ кодируем тем же тегом, что и значения.
	if typeof(key) == TYPE_STRING:
		return key
	return encode(key)


## JSON-безопасная форма → исходное значение.
static func decode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			if v.has(TAG):
				return _decode_tagged(v)
			var out := {}
			for key in v:
				out[_decode_key(key)] = decode(v[key])
			return out
		TYPE_ARRAY:
			var arr := []
			for item in v:
				arr.append(decode(item))
			return arr
		_:
			return v


static func _decode_key(key: Variant) -> Variant:
	if typeof(key) == TYPE_STRING:
		return key
	return decode(key)


static func _decode_tagged(d: Dictionary) -> Variant:
	match str(d.get(TAG, "")):
		"i":
			return int(d.get("v", 0))
		"v2":
			return Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
		"v2i":
			return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
		"v3":
			return Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))
		"c":
			return Color(float(d.get("r", 0.0)), float(d.get("g", 0.0)),
				float(d.get("b", 0.0)), float(d.get("a", 1.0)))
		"raw":
			return str(d.get("v", ""))
		_:
			return d


## Словарь → текст JSON. Все значения кодируются.
static func dump(v: Variant) -> String:
	return JSON.stringify(encode(v))


## Текст JSON → словарь со восстановленными типами. null, если текст битый.
##
## Используем JSON.new().parse(), а не JSON.parse_string(): тот при неудаче
## печатает в консоль красный "Parse JSON failed", из-за чего битый файл
## сохранения выглядит как авария движка. Здесь нужен тихий null.
static func load_string(s: String) -> Variant:
	var j := JSON.new()
	if j.parse(s) != OK:
		return null
	return decode(j.data)
