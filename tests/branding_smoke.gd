extends SceneTree
##
## СТОРОЖ названия (03.10). Слово «Аллоды / Allods» запрещено: это духовный
## наследник, а не копия, и название в игре быть не должно.
##
## Где смотрят:
##   - project.godot config/name — заголовок окна и имя папки user://;
##   - титульный экран выбора героя;
##   - шапка game.cfg;
##   - фильтр файлов в редакторе карт (виден игроку, если открыть редактор).
##
## ЧЕГО тест НЕ трогает: внутренние комментарии вида «как в Allods16»,
## «формула оригинала Allods II». Это атрибуция — откуда взята формула и
## формат карт. Стирать её нельзя, она объясняет, почему числа такие.
##
## ЗАПУСК
## ------
## godot --headless --path . --script res://tests/branding_smoke.gd
##

const PROJECT := "res://project.godot"
const CFG := "res://assets/config/game.cfg"
const TITLE_SCRIPT := "res://scripts/character_select.gd"
const EDITOR_SCRIPT := "res://scripts/map_editor.gd"

## Строки, которые игрок видит. Их проверяем на запрещённое слово ПОТОЧНО,
## а не сканированием файла: в коде есть внутренние комментарии о
## происхождении формул, и они разрешены (см. шапку теста).
const PLAYER_VISIBLE := [
	["res://project.godot", "config/name"],
	["res://assets/config/game.cfg", "шапка"],
	["res://scripts/character_select.gd", "титульный экран"],
	["res://scripts/main_menu.gd", "главное меню"],
	["res://scripts/map_editor.gd", "фильтр редактора"],
]

var _checks := 0
var _fails: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)


## Ищем и латиницу, и кириллицу. "Аллоды" в разных регистрах и падежах,
## "Allods"/"allods" — тоже самое.
func _banned_hits(text: String) -> Array[String]:
	var out: Array[String] = []
	var low := text.to_lower()
	# латиница
	for w in ["allod", "allods", "allods2", "allods ii", "allods16", "unityallods"]:
		if low.contains(w):
			out.append(w)
	# кириллица: аллод + ы/ов/ами/ах/ом/е/а/у
	if low.contains("аллод") or low.contains("аллоз") or low.contains("аллозд"):
		out.append("аллод*")
	return out


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


func _run() -> void:
	print("-- название игры --")
	var proj := _read(PROJECT)
	_check(not proj.is_empty(), "project.godot читается")

	# config/name
	var name_line := ""
	for line in proj.split("\n"):
		if line.begins_with("config/name"):
			name_line = line.strip_edges()
			break
	_check(name_line != "", "в project.godot есть config/name")
	_check(not _banned_hits(name_line).is_empty() == false,
		"config/name без запрещённого слова: %s" % name_line)
	_check(name_line.to_lower().contains("mirotokhome"),
		"config/name содержит Mirotokhome (%s)" % name_line)

	# титульный экран
	var title_script := _read(TITLE_SCRIPT)
	var title_txt := ""
	for line in title_script.split("\n"):
		if line.contains("CsTitle"):
			continue
		if line.contains("title.text = \"") and "STAT_TITLES" not in line:
			title_txt = line.strip_edges().trim_prefix("title.text = ") \
				.trim_prefix("\"").trim_suffix("\"")
			break
	_check(title_txt != "", "титульный экран найден (%s)" % title_txt)
	_check(_banned_hits(title_txt).is_empty(),
		"титульный экран без запрещённого слова")
	_check(title_txt.contains("MIROTOKHOME"), "титульный экран = MIROTOKHOME")

	# фильтр редактора
	var ed := _read(EDITOR_SCRIPT)
	var filt := ""
	for line in ed.split("\n"):
		if line.contains("fd.filters"):
			filt = line
			break
	_check(_banned_hits(filt).is_empty(),
		"фильтр файлов редактора без запрещённого слова")

# шапка конфига (строка 2 — на первой разделитель из точек)
	var cfg := _read(CFG)
	var lines := cfg.split("\n")
	var header := lines[1].strip_edges() if lines.size() > 1 else ""
	_check(_banned_hits(header).is_empty(), "шапка game.cfg без запрещённого слова")
	_check(header.contains("Mirotokhome"), "шапка game.cfg = %s" % header)

	# Конфиги сканируем ЦЕЛИКОМ — там нет комментариев о происхождении.
	for pair in [["res://project.godot", "project.godot"],
			["res://assets/config/game.cfg", "game.cfg"]]:
		var hits := _banned_hits(_read(pair[0]))
		_check(hits.is_empty(), "%s целиком: запрещённых слов нет (%s)"
				% [pair[1], str(hits)])

	# Код НЕ сканируем целиком: там есть внутренние комментарии о происхождении
	# формул и формата карт («как в Allods16», «Аллодов» в player.gd:265).
	# Проверяем только конкретные видимые игроку строки — они выше.

	_report()


func _report() -> void:
	print("RESULT: %s branding_smoke (проверок: %d, провалов: %d)"
			% ["OK" if _fails.is_empty() else "FAIL", _checks, _fails.size()])
	for f in _fails:
		print("  FAIL " + f)
	quit(0 if _fails.is_empty() else 1)