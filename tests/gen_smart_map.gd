extends SceneTree
## CLI-обёртка над MapGenerator (scripts/world/map_generator.gd).
##
## Вся логика генерации живёт в MapGenerator, этот файл только разбирает аргументы
## и запускает. Раньше генератор был SceneTree-скриптом целиком; теперь ядро
## вызывается из игры по сиду, а этот скрипт остался для пакетной генерации.
##
## Без аргументов — прежнее поведение: seed=4242, zone=mid, gen_smart_01.alm
## в assets/maps/gen/. Существующие скрипты (import_smoke, spawn_smoke) продолжают
## находить карту на прежнем месте.
##
##   godot --headless --path . --script res://tests/gen_smart_map.gd
##   godot --headless --path . --script res://tests/gen_smart_map.gd -- --seed 777 --zone hard
##   godot --headless --path . --script res://tests/gen_smart_map.gd -- --seed 1 --out user://maps/
##
## Аргументы:
##   --seed N     сид генерации (по умолчанию MapGenerator.BASE_SEED = 4242)
##   --zone Z     start | mid | hard | faction (по умолчанию mid)
##   --out DIR    каталог с завершающим слэшем (по умолчанию res://assets/maps/gen/)
##   --name NAME  базовое имя файлов без расширения (по умолчанию gen_smart_01)

const OUT_DIR_DEFAULT := "res://assets/maps/gen/"
const ZONE_DEFAULT := "mid"
const NAME_DEFAULT := "gen_smart_01"

func _init() -> void:
	var args: PackedStringArray = _user_args()
	var seed_value: int = MapGenerator.BASE_SEED
	var zone: String = ZONE_DEFAULT
	var out_dir: String = OUT_DIR_DEFAULT
	var basename: String = NAME_DEFAULT

	var i: int = 0
	while i < args.size() - 1:
		match args[i]:
			"--seed":
				seed_value = int(args[i + 1])
			"--zone":
				zone = str(args[i + 1])
			"--out":
				out_dir = str(args[i + 1])
				if not out_dir.ends_with("/"):
					out_dir += "/"
			"--name":
				basename = str(args[i + 1])
		i += 2

	if not ["start", "mid", "hard", "faction"].has(zone):
		printerr("Неизвестная зона '%s' — допустимо: start, mid, hard, faction" % zone)
		quit(1)
		return

	# Имя карты внутри .alm совпадает с базовым именем файла.
	var path: String = MapGenerator.new().generate(seed_value, zone, out_dir, basename, basename)
	if path == "":
		printerr("Генерация не удалась")
		quit(1)
		return
	print("MAP: %s" % path)
	quit(0)

## Аргументы после "--" (Godot отбрасывает их из OS.get_cmdline_args()).
func _user_args() -> PackedStringArray:
	var all: PackedStringArray = OS.get_cmdline_user_args()
	if all.size() > 0:
		return all
	return OS.get_cmdline_args()
