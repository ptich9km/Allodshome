extends RefCounted
class_name GameConfig
##
## Игровой конфиг: все числа, которые можно крутить без правки кода.
##
## Замысел — от файла `import/rates.properties` (настройки сервера AION).
## Оттуда взяты удачные решения: множитель урона и множители HP/PW по тирам
## мобов. Отброшено лишнее: в AION ~80% файла — это `regular/premium/vip`,
## три копии одного множителя ради монетизации; у нас повторять нечего.
##
## Где лежит:
##   res://assets/config/game.cfg  — эталоны, в репозитории
##   user://config/game.cfg        — твои правки, вне git, перекрывают res
##
## Правила, заложенные специально:
##   1. Любой ключ имеет значение по умолчанию. Опечатка в конфиге не должна
##      ронять игру — берём дефолт и пишем предупреждение в лог.
##   2. Дефолты равны тем числам, что были зашиты в код. Появление конфига
##      ничего не меняет в поведении игры, только делает числа видимыми.
##   3. Конфиг читается при старте. Горячей перезагрузки нет.
##

## Пути. USER_PATH — то, что ты крутишь руками.
const RES_PATH := "res://assets/config/game.cfg"
const USER_PATH := "user://config/game.cfg"

## Значения по умолчанию = текущие числа из кода (правило 2).
## Порядок ключей здесь = порядок секций в .cfg.
const DEFAULTS := {
	"combat": {
		"hit_base": 70,             # база попадания, %
		"hit_soften": 5,            # смягчение: шанс = base*(att+soft)/(def+soft)
		"hit_min": 5,
		"hit_max": 95,
		"damage_multiplier": 1.0,   # глобальный множитель урона (взят из AION)
		"attack_cooldown": 1.0,     # раньше продублировано 1.0 в трёх файлах
		"enemy_defense_div": 25,    # было max_hp/25
		"enemy_attack_dmg_div": 2,  # было damage/2
		"enemy_attack_hp_div": 30,  # было max_hp/30
		"enemy_absorption_div": 40, # было max_hp/40
		"protection_max": 95,       # потолок сопротивления стихии, %
	},
	"magic": {
		"sp_offset": 15.0,          # SP = навык + разум - offset
		"staff_mana_cost": 4,       # ману за удар посоха
		"chain_min_targets": 4,
		"chain_max_targets": 6,
		"chain_radius": 160.0,
	},
	"economy": {
		"start_gold": 20,           # ТУТ БЫЛО 20. Этап 2 поднимет до 400:
		"sell_price_div": 2,        # продажа = цена / div (зашито в двух местах)
		"loot_gold_multiplier": 1.0,
	},
	"loot": {
		"enemy_potion_chance": 45,   # было randi()%100 < 45
		"enemy_gear_chance": 35,
		"npc_citizen_potion_chance": 50,
		"npc_guard_potion_chance": 25,
		"npc_guard_gear_chance": 30,
	},
	"progression": {
		"unit_exp_base": 100,
	},
	"movement": {
		"accel": 1100.0,   # дублируется в player.gd и enemy.gd
		"decel": 1800.0,
		"speed_multiplier": 1.0,
	},
	"autosave": {
		"interval": 60.0,
	},
	"metal": {
		# Опорная точка — цена слитка металла, статы считаются от неё.
		# Проверено на данных: Crossbow = слиток x 1600 сходится у 15 металлов.
		"price_per_defence": 1600,     # золота за единицу защиты
		"price_per_damage": 800,       # золота за единицу среднего урона
		"price_per_absorption": 12000,
		"absorption_min": 1,
		"absorption_max": 6,
	},
	"spawn": {
		"herb_region_grid": 4,
		"herb_min_distance": 6,
		"city_radius": 8,
		"city_gap": 2,
	},
	"mob_tier": {
		# Множители по тирам мобов (идея из AION). Тиров Серых в игре ещё нет,
		# место заведено заранее — см. аудит, пакет C.
		"hp_multiplier": 1.0,
		"damage_multiplier": 1.0,
	},
	"zone": {
		# Плоские ключи вида zone.<name>.<key> — ConfigFile не умеет вложенные
		# секции, поэтому зоны живут одной секцией с префиксом.
		#
		# ВАЖНО: значения ниже = ТЕКУЩЕЕ поведение генератора, а не желаемое.
		# Сейчас зоны различаются только по Серым (GRAY_ZONE), а стражи и
		# горожане одинаковы везде. Этап баланса поднимет Серых в ранних зонах,
		# этап спавна разведёт стражей по зонам. Пока дефолты = как было.
		"start.gray_count_min": 6,     "start.gray_count_max": 10,
		"start.gray_hp_min": 25,       "start.gray_hp_max": 45,
		"start.gray_damage_min": 4,    "start.gray_damage_max": 6,
		"start.guard_hp_min": 60,      "start.guard_hp_max": 100,
		"start.guard_damage_min": 6,   "start.guard_damage_max": 10,
		"start.guard_count_min": 3,    "start.guard_count_max": 5,
		"start.citizen_hp": 30,
		"start.citizen_count_min": 6,  "start.citizen_count_max": 10,
		"start.captain_hp": 120,       "start.captain_damage": 12,
		"start.interest_points": 0,    # руины/стоянки/святилища — этап спавна
		"start.tree_density": 0.06,

		"mid.gray_count_min": 10,      "mid.gray_count_max": 14,
		"mid.gray_hp_min": 45,         "mid.gray_hp_max": 75,
		"mid.gray_damage_min": 6,      "mid.gray_damage_max": 9,
		"mid.guard_hp_min": 60,        "mid.guard_hp_max": 100,
		"mid.guard_damage_min": 6,     "mid.guard_damage_max": 10,
		"mid.guard_count_min": 3,      "mid.guard_count_max": 5,
		"mid.citizen_hp": 30,
		"mid.citizen_count_min": 6,    "mid.citizen_count_max": 10,
		"mid.captain_hp": 120,         "mid.captain_damage": 12,
		"mid.interest_points": 0,
		"mid.tree_density": 0.08,

		"hard.gray_count_min": 14,     "hard.gray_count_max": 18,
		"hard.gray_hp_min": 70,        "hard.gray_hp_max": 120,
		"hard.gray_damage_min": 9,     "hard.gray_damage_max": 14,
		"hard.guard_hp_min": 60,       "hard.guard_hp_max": 100,
		"hard.guard_damage_min": 6,    "hard.guard_damage_max": 10,
		"hard.guard_count_min": 3,     "hard.guard_count_max": 5,
		"hard.citizen_hp": 30,
		"hard.citizen_count_min": 6,   "hard.citizen_count_max": 10,
		"hard.captain_hp": 120,        "hard.captain_damage": 12,
		"hard.interest_points": 0,
		"hard.tree_density": 0.10,

		"faction.gray_count_min": 12,  "faction.gray_count_max": 16,
		"faction.gray_hp_min": 50,     "faction.gray_hp_max": 95,
		"faction.gray_damage_min": 7,  "faction.gray_damage_max": 11,
		"faction.guard_hp_min": 60,    "faction.guard_hp_max": 100,
"faction.guard_damage_min": 6, "faction.guard_damage_max": 10,
		"faction.guard_count_min": 3,  "faction.guard_count_max": 5,
		"faction.citizen_hp": 30,
		"faction.citizen_count_min": 6, "faction.citizen_count_max": 10,
		"faction.captain_hp": 120,     "faction.captain_damage": 12,
		"faction.interest_points": 0,
		"faction.tree_density": 0.09,
	},
}

static var _cfg: ConfigFile = null
static var _loaded := false
static var _unknown_keys: PackedStringArray = PackedStringArray()


static func load_all() -> void:
	## Читает res-эталон, поверх — пользовательский файл. Ошибка любого из
	## них не фатальна: игра идёт на дефолтах.
	_loaded = true
	_unknown_keys = PackedStringArray()
	var cfg := ConfigFile.new()
	var res_err := cfg.load(RES_PATH)
	if res_err != OK:
		push_warning("GameConfig: не читается %s (ошибка %d) — беру дефолты" % [RES_PATH, res_err])
	var user_err := cfg.load(USER_PATH)
	if user_err != OK and user_err != ERR_FILE_NOT_FOUND:
		push_warning("GameConfig: не читается %s (ошибка %d) — он проигнорирован" % [USER_PATH, user_err])
	_cfg = cfg


static func _ensure() -> void:
	if not _loaded:
		load_all()


static func _default_for(section: String, key: String) -> Variant:
	var sec: Variant = DEFAULTS.get(section, null)
	if sec is Dictionary:
		return (sec as Dictionary).get(key, null)
	return null


static func geti(section: String, key: String) -> int:
	_ensure()
	var d: Variant = _default_for(section, key)
	if _cfg != null and _cfg.has_section_key(section, key):
		return int(_cfg.get_value(section, key, d))
	if d == null:
		push_warning("GameConfig: неизвестный ключ %s.%s" % [section, key])
		return 0
	return int(d)


static func getf(section: String, key: String) -> float:
	_ensure()
	var d: Variant = _default_for(section, key)
	if _cfg != null and _cfg.has_section_key(section, key):
		return float(_cfg.get_value(section, key, d))
	if d == null:
		push_warning("GameConfig: неизвестный ключ %s.%s" % [section, key])
		return 0.0
	return float(d)


## Ключ зоны вида "start.gray_hp_min" живёт в секции [zone].
static func zonei(zone: String, key: String) -> int:
	return geti("zone", "%s.%s" % [zone, key])


static func zonef(zone: String, key: String) -> float:
	return getf("zone", "%s.%s" % [zone, key])


static func unknown_keys() -> PackedStringArray:
	return _unknown_keys


## Все известные ключи — для валидатора и дампа значений.
static func known_keys() -> Array[String]:
	var out: Array[String] = []
	for section in DEFAULTS:
		for key in (DEFAULTS[section] as Dictionary):
			out.append("%s.%s" % [section, key])
	return out


## Скопировать эталон из репозитория в пользовательский файл, чтобы его
## можно было крутить руками. Идемпотентно: если файл уже есть — не трогаем.
static func seed_user_file() -> bool:
	if FileAccess.file_exists(USER_PATH):
		return false
	var cfg := ConfigFile.new()
	if cfg.load(RES_PATH) != OK:
		push_warning("GameConfig: нечего копировать, %s не читается" % RES_PATH)
		return false
	var dir := USER_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	# set_value для каждого известного ключа, иначе save() создаст пустой файл:
	# ConfigFile не хранит комментарии, а нам нужен читаемый файл.
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			cfg.set_value(section, key, (DEFAULTS[section] as Dictionary)[key])
	var err := cfg.save(USER_PATH)
	if err != OK:
		push_warning("GameConfig: не записался %s (ошибка %d)" % [USER_PATH, err])
		return false
	return true