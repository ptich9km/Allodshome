extends SceneTree
##
## Генератор эталона конфига: res://assets/config/game.cfg из DEFAULTS.
##
## Зачем он, если DEFAULTS и так лежат в коде: чтобы файл в репозитории был
## ЧИТАЕМЫМ и не расходился с кодом. Файл собирается из одного источника
## правды, значит синхронизация не может «разъехаться» — при добавлении ключа
## достаточно дописать его в DEFAULTS и прогнать этот скрипт.
##
## Комментарии в .cfg пишутся через `;` — ConfigFile их понимает, а `#`
## не понимает (проверено по документации Godot 4.7). Сам ConfigFile комментарии
## при сохранении теряет, поэтому шапка и пояснения дописываются текстом.
##
## Запуск:
##   godot --headless --path . --script res://tests/gen_game_config_defaults.gd
##   godot --headless --path . --script res://tests/gen_game_config_defaults.gd -- --check
##

const OUT := "res://assets/config/game.cfg"

## Пояснения к ключам: секция -> ключ -> строка комментария.
## Пустое значение означает «комментарий не нужен».
const NOTES := {
	"combat.hit_base": "база попадания, %",
	"combat.hit_soften": "смягчение: шанс = base*(att+soft)/(def+soft)",
	"combat.damage_multiplier": "ГЛОБАЛЬНЫЙ множитель урона (идея из AION)",
	"combat.attack_cooldown": "ранее продублировано 1.0 в enemy/mercenary/npc",
	"combat.enemy_defense_div": "защита врага = max_hp / это",
	"combat.enemy_attack_dmg_div": "атака врага = damage / это + max_hp / enemy_attack_hp_div",
	"combat.enemy_attack_hp_div": "атака врага = damage / enemy_attack_dmg_div + max_hp / это",
	"combat.enemy_absorption_div": "поглощение врага = max_hp / это",
	"combat.protection_max": "потолок сопротивления стихии, %",
	"magic.sp_offset": "SP = навык + разум - это",
	"economy.start_gold": "СТАРТОВОЕ ЗОЛОТО. Сейчас 20, а оружие стоит 150-600.",
	"economy.sell_price_div": "продажа в магазине = цена / это",
	"metal.price_per_defence": "золота за единицу защиты. Проверено: Crossbow = слиток x 1600",
	"metal.price_per_damage": "золота за единицу среднего урона",
	"spawn.tree_density": "плотность деревьев на карте",
	"mob_tier.hp_multiplier": "множитель HP по тиру моба (идея из AION). Тиров пока нет.",
}

const HEADERS := {
	"combat": "БОЙ",
	"magic": "МАГИЯ",
	"economy": "ЭКОНОМИКА",
	"loot": "ЛУТ",
	"progression": "ПРОГРЕСС",
	"movement": "ДВИЖЕНИЕ",
	"autosave": "АВТОСЕЙВ",
	"metal": "МЕТАЛЛ -> СТАТЫ  (двигатель этапа баланса)",
	"spawn": "ГЕНЕРАЦИЯ КАРТЫ",
	"mob_tier": "ТИРЫ МОБОВ  (место заведено заранее, тиров в игре нет)",
	"zone": "ЗОНЫ  (Серые, страж��, точки интереса)",
}


func _note(section: String, key: String) -> String:
	var n: String = str(NOTES.get("%s.%s" % [section, key], ""))
	return ("    ; " + n) if n != "" else ""


func _fmt(value: Variant) -> String:
	if value is float:
		return str(value)
	return str(value)


func build_text() -> String:
	var lines: Array[String] = []
	lines.append("; ============================================================")
	lines.append("; Allods Home - игровой конфиг")
	lines.append(";")
	lines.append("; Эталоны по умолчанию. Сгенерировано из DEFAULTS в")
	lines.append("; scripts/game_config.gd - правь значения здесь, потом перезапусти игру.")
	lines.append(";")
	lines.append("; Свои правки держи в user://config/game.cfg - он перекрывает этот")
	lines.append("; файл и не попадает в git. Экспорт: готовится скриптом seed_user_file().")
	lines.append(";")
	lines.append("; ВАЖНО: имена секций и ключей не могут содержать пробелов -")
	lines.append("; ConfigFile молча отрезает всё после первого пробела.")
	lines.append("; ============================================================")

	for section in GameConfig.DEFAULTS:
		lines.append("")
		lines.append("; ============================================================")
		lines.append("; " + str(HEADERS.get(section, section)))
		lines.append("; ============================================================")
		lines.append("[%s]" % section)
		var keys: Array = (GameConfig.DEFAULTS[section] as Dictionary).keys()
		keys.sort()
		for key in keys:
			var note := _note(section, str(key))
			lines.append("%s = %s%s" % [key, _fmt((GameConfig.DEFAULTS[section] as Dictionary)[key]), note])
	lines.append("")
	return "\n".join(lines)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var code := main()
	print("EXIT %d" % code)
	quit(code)


func main() -> int:
	var check_only := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--check":
			check_only = true
	var text := build_text()

	if check_only:
		if not FileAccess.file_exists(OUT):
			print("FAIL: %s не существует" % OUT)
			return 2
		var cur := FileAccess.get_file_as_string(OUT)
		if cur != text:
			print("FAIL: файл разошёлся с DEFAULTS - перегенерируй без --check")
			return 2
		print("RESULT: OK файл совпадает с DEFAULTS (%d строк)" % text.split("\n").size())
		return 0

	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		print("FAIL: не записался %s (ошибка %d)" % [OUT, FileAccess.get_open_error()])
		return 2
	f.store_string(text)
	f.close()
	print("записан %s (%d строк, %d секций)" % [OUT, text.split("\n").size(), GameConfig.DEFAULTS.size()])
	print("RESULT: OK gen_game_config_defaults")
	return 0