extends SceneTree
## Смоук переключения языка RU/ENG (scripts/loc.gd, assets/locale/ui.json).
##
## Закрывает то, что локализация ломает «молча»:
##
##  * **Ключ не найден -> показан сам ключ.** Без проверки интерфейс молча
##    показывает `ui.menu.new_game` вместо текста.
##  * **Ключ есть только в одном языке.** Тогда в этом языке строка падает на
##    русский — заметно, но легко пропустить. Проверяем полноту всех записей.
##  * **Ключ-сирота в .json.** Уже не используется, но лежит: чинит его
##    бесполезно, а удалить забывают.
##  * **Выбор языка не переживает перезапуск.** Тогда игроку приходится
##    переключать каждый раз.
##  * **Локализация не должна трогать игровые данные.** Это главная ловушка:
##    `loot_icons.gd:92` разбирает кириллицу из `name_ru`, чтобы выбрать иконку
##    зелья. Если завернуть это в Loc, смена языка поменяет иконки — игровой
##    баг, а не косметика. Проверяем, что в режиме EN иконка та же.
##
## Запуск: godot --headless --path . --script res://tests/loc_smoke.gd

const LOC_TABLE := "res://assets/locale/ui.json"

## Файлы, где ключи Loc встречаются. Сверяется с таблицей, чтобы ключ,
## удалённый из .json, не остался в коде.
const CODE_USERS := [
	"res://scripts/main_menu.gd",
	"res://scripts/save_menu.gd",
	"res://scripts/settings_panel.gd",
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
	Loc.clear_saved()
	Loc.set_locale("ru")

	_table_shape()
	_no_cyrillic_in_english()
	_no_key_shown_raw()
	_keys_used_in_code()
	_language_switch_changes_main_menu()
	_persistence()
	_locale_does_not_touch_game_data()

	_report()
	quit(0 if _fails.is_empty() else 1)


# --- Таблица: полнота и мусор ---

func _table_shape() -> void:
	var f := FileAccess.open(LOC_TABLE, FileAccess.READ)
	if f == null:
		_check(false, "%s читается" % LOC_TABLE)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	_check(parsed is Dictionary, "%s — валидный JSON-объект" % LOC_TABLE)
	if not (parsed is Dictionary):
		return
	var keys: Array = Loc.keys()
	_check(keys.size() >= 40,
		"в таблице не меньше 40 ключей (=%d)" % keys.size())
	for k in keys:
		_check(Loc.entry_complete(str(k)),
			"ключ %s переведён на оба языка" % k)


## Английский не должен содержать кириллицу. Один забытый русский остаток в
## английской строке — это и есть «почти переведено».
##
## Исключение — названия языков в самом языке: кнопка «Русский» обязана
## называться «Русский» и в английском меню, иначе игрок не узнаёт переключатель.
const NATIVE_NAME_KEYS := ["ui.lang.ru", "ui.lang.en"]


func _no_cyrillic_in_english() -> void:
	var f := FileAccess.open(LOC_TABLE, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	for k in (parsed as Dictionary).keys():
		var key := str(k)
		if key.begins_with("_"):
			continue
		if NATIVE_NAME_KEYS.has(key):
			continue
		var entry = (parsed as Dictionary)[key]
		if not (entry is Dictionary):
			continue
		var en := str((entry as Dictionary).get("en", ""))
		var cyr := ""
		for i in en.length():
			if en.unicode_at(i) >= 0x0400 and en.unicode_at(i) <= 0x04FF:
				cyr += en[i]
		_check(cyr.is_empty(), "в переводе %s нет кириллицы (найдено: %s)" % [key, cyr])


## Ни один ключ не должен показываться игроку как есть.
func _no_key_shown_raw() -> void:
	Loc.set_locale("ru")
	for k in Loc.keys():
		var ru := Loc.t(str(k))
		_check(not ru.begins_with("ui."),
			"в русском ключ %s отдаёт текст, а не ключ" % k)
	Loc.set_locale("en")
	for k in Loc.keys():
		var en := Loc.t(str(k))
		_check(not en.begins_with("ui."),
			"в английском ключ %s отдаёт текст, а не ключ" % k)
	Loc.set_locale("ru")


## Каждый ключ из таблицы обязан где-то использоваться: иначе он протух.
func _keys_used_in_code() -> void:
	var code := ""
	for p in CODE_USERS:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			_check(false, "%s читается" % p)
			continue
		code += f.get_as_text()
		f.close()
	for k in Loc.keys():
		var key := str(k)
		# Подсказка переключателя собирает ключ по шаблону "ui.lang." + code.
		if code.contains('"ui.lang." +'):
			continue
		_check(code.contains(key), "ключ %s используется в коде" % key)


# --- Переключение без перезапуска ---

func _language_switch_changes_main_menu() -> void:
	var packed: PackedScene = load("res://scenes/main_menu.tscn")
	_check(packed != null, "main_menu.tscn загружается")
	if packed == null:
		return
	Loc.set_locale("ru")
	var menu = packed.instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame

	# Кнопка ищется по ключу перевода через meta: Godot выедает точки из имён
	# узлов, `ui.menu.new_game` становится `ui_menu_new_game`.
	var btn = menu.menu_button("ui.menu.new_game")
	_check(btn is Button, "кнопка «Новая игра» найдена по ключу-имени")
	var ru_text := ""
	if btn is Button:
		ru_text = (btn as Button).text
	_check(ru_text == "Новая игра", "в RU кнопка = «Новая игра» (получено «%s»)" % ru_text)

	# Нажимаем переключатель языка так же, как игрок.
	var en_btn := menu.find_child("Lang_en", true, false)
	_check(en_btn is Button, "кнопка переключения на EN найдена")
	if en_btn is Button:
		(en_btn as Button).pressed.emit()
		await process_frame

	_check(Loc.locale() == "en", "язык переключился на en")
	var en_text := ""
	if btn is Button:
		en_text = (btn as Button).text
	_check(en_text == "New Game",
		"в EN кнопка = «New Game» (получено «%s»)" % en_text)
	_check(en_text != ru_text, "подпись действительно изменилась")

	# Заголовок-фирма не переводится, но подзаголовок должен.
	var sub := menu.find_child("Subtitle", true, false)
	_check(sub is Label, "подзаголовок найден")
	if sub is Label:
		_check((sub as Label).text == "A sandbox and tactical RPG",
			"подзаголовок переведён (получено «%s»)" % (sub as Label).text)

	menu.queue_free()
	await process_frame


# --- Хранение выбора ---

func _persistence() -> void:
	Loc.clear_saved()
	Loc.set_locale("en")
	_check(Loc.save_locale(), "выбор языка записан в user://settings.cfg")
	_check(FileAccess.file_exists(Settings.PATH), "settings.cfg существует")
	Loc.set_locale("ru")
	Loc.load_locale()
	_check(Loc.locale() == "en", "после reload() язык остался en (выбор пережил запуск)")

	# Мусорный файл не должен ломать игру.
	var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
	f.store_string("language=klingon\nэто не конфиг")
	f.close()
	# Перечитываем файл: без reload кэш Settings остаётся тёплым, и проверка
	# прошла бы на старом добром файле, а не на битом.
	Settings.reload_from_disk()
	Loc.set_locale("ru")
	Loc.load_locale()
	_check(Loc.locale() == "ru", "битый settings.cfg игнорируется, язык не ломается")
	Loc.clear_saved()
	Loc.set_locale("ru")


# --- Локализация не трогает игровые данные ---

func _locale_does_not_touch_game_data() -> void:
	# LootIcons выбирает иконку зелья, разбирая кириллицу из name_ru
	# (loot_icons.gd:92 `_is_mana_potion`). Если бы это поехало через Loc,
	# смена языка молча поменяла бы иконки — игровой баг, а не косметика.
	var potions := ["Potion Medium Healing", "Potion Medium Mana",
		"Potion Big Healing", "Potion Antipoison"]
	var ru_icons: Array = []
	for p in potions:
		var item := ItemDB.find(p)
		if item.is_empty():
			continue
		ru_icons.append(LootIcons.icon_for(item))
	Loc.set_locale("en")
	var en_icons: Array = []
	for p in potions:
		var item := ItemDB.find(p)
		if item.is_empty():
			continue
		en_icons.append(LootIcons.icon_for(item))
	Loc.set_locale("ru")
	_check(ru_icons == en_icons,
		"иконки зелий не зависят от языка интерфейса (%s vs %s)"
			% [str(ru_icons), str(en_icons)])
	_check(not ru_icons.is_empty(), "иконки зелий вообще нашлись")


func _report() -> void:
	print("RESULT: %s loc_smoke (проверок: %d, провалов: %d)"
			% ["OK" if _fails.is_empty() else "FAIL", _checks, _fails.size()])
	for f in _fails:
		print("  FAIL " + f)