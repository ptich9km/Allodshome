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
		"auto_heal_ratio": 0.45,    # авто-лечение, когда HP/макс ниже порога
		"auto_buff_interval": 2.0,  # сек между проверками авто-баффов
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
		# npc_guard_gear_chance УДАЛЁН 07.10: NPC роняют сломанную вещь
		# ВСЕГДА, а не с шансом. Шанс был частью старой модели, где NPC
		# роняли целую вещь - теперь она сломанная по определению.
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
		# absorption_min/max — потолок поглощения по металлу. Ссылается тест
		# game_config_smoke; сам игровой код их пока не читает.
		"absorption_min": 1,
		"absorption_max": 6,

		# --- Формула «металл -> статы» (этап 2, 03.10) -------------------
		# Находка: tests/gen_empty_metals_items.py масштабировал от цены
		# слитка ТОЛЬКО price, а damage/to_hit/defence копировал из образца.
		# Итог: 554 из 651 предметов 13 металлов фракций имели побайтово
		# одинаковую сигнатуру (тип, качество, урон, to_hit, защита) —
		# клон тербия. Слабый lutetium был равен тербию.
		# Теперь статы = база(тип, качество) x (слиток/слиток_реф) ^ exp.
		# Степени подобраны по существующим «настоящим» металлам, чтобы
		# переезд НЕ ломал их: bronze 1.00, iron 1.40 (было 1.38),
		# radium 7.11 (было 7.12). Монотонность по цене слитка получается
		# САМОЙ по себе, а не таблицей, которую надо поддерживать руками.
		"reference_metal": "bronze",   # слиток с множителем ровно 1.0
		"damage_exp": 0.22,
		"to_hit_exp": 0.10,            # точность растёт медленнее урона
		"defence_exp": 0.22,
		"absorption_exp": 0.15,
	},
	"craft": {
		# --- Мастерская (07.10, пакет 1) ---------------------------------
		# Кузнец/Портной/Мастер. Металл в игре существует ТОЛЬКО как
		# производная от убитых НПЦ: сломанная вещь -> переплавка -> слиток
		# -> рецепт. Лавка продаёт только свитки рецептов, книги и зелья.

		# Выход переработки сломанной вещи. Количество НЕ зависит от цены
		# металла - кратность выражается качеством вещи, иначе появилась бы
		# четвёртая валюта. Проверено по ценам слитков: bronze 2 ... radium
		# 12150, разброс в 6000 раз закрывается тремя ступенями.
		"yield_broken": 1,          # слитков из брони/оружия: Broken
		"yield_broken_fine": 2,     # Broken Fine
		"yield_broken_rare": 4,     # Broken Rare
		# Кузнец даёт ткань «вразрез» с портным: много ткани нужно портному,
		# поэтому из металлической вещи её выходит мало. Обмен асимметричен
		# намеренно - это и есть баланс двух профессий.
		"fabric_from_armor": 1,
		"fabric_from_armor_fine": 2,
		"fabric_from_armor_rare": 2,
		"fabric_from_weapon": 0,
		"fabric_from_weapon_fine": 1,
		"fabric_from_weapon_rare": 1,
		# Одежда мага: ткань + магическая эссенция.
		"fabric_from_garment": 2,
		"fabric_from_garment_fine": 4,
		"fabric_from_garment_rare": 6,
		"essence_from_garment": 1,
		"essence_from_garment_fine": 2,
		"essence_from_garment_rare": 3,

		# --- Шансы трёх уровней крафта -------------------------------
		# 80 / 15 / 5 на навыке 0. Навык сдвигает так, что сумма всегда 100:
		#   обычная    = chance_ordinary - ordinary_step * навык
		#   улучшенная = chance_improved + improved_step * навык
		#   мастерская = chance_master  + master_step  * навык
		# Навык 20 -> 52 / 33 / 15. Обычная зажата снизу floor_ordinary.
		"chance_ordinary": 80.0,
		"chance_improved": 15.0,
		"chance_master": 5.0,
		"ordinary_step": 1.4,
		"improved_step": 0.9,
		"master_step": 0.5,
		"floor_ordinary": 5.0,

		# Множители характеристик крафтовых вещей. Текстура у всех трёх
		# уровней ОДНА, различаются только числа и шейдер свечения.
		"tier_improved_mult": 1.15,
		"tier_master_mult": 1.35,

		# --- Навыки крафта ---------------------------------------------
		# Опыт за создание вещи. Формула роста уровня общая с боевыми
		# навыками (1.1^n в player.skill_to_exp) - она сама замедляет рост.
		"xp_per_craft": 20,
		"xp_per_recycle": 4,
		"xp_tier_bonus": 15,       # доп. опыт за улучшенную/мастерскую вещь

		# Мастер по улучшениям - третья вкладка. Занята заранее, чтобы её
		# добавление не сдвигало индексы остальных вкладок.
		"master_enabled": 0,

		# --- Дроп -------------------------------------------------------
		# Шанс эссенции с Серых живёт НЕ здесь, а в assets/config/
		# loot_tables.json рядом с gear_chance/potion_chance: он зависит от
		# семейства (зверь / насекомое / нежить / чудовище), и держать
		# половину таблицы в конфиге, а половину в json - это два источника
		# правды на одно число.
		"boss_intact_chance": 12,  # босс/дракон роняет ЦЕЛУЮ вещь вместо сломанной
	},
	"spawn": {
		# Размер и плотность города. city_gap — зазор между зданиями, его
		# решение от 26.09 («1 -> 2») в коде НЕ было применено: _footprint_fits
		# содержал зашитый 1, а city_layout_smoke подстроился под факт
		# (`gap >= CITY_GAP - 1`) и молча разрешал ему расти.
		#
		# Замер 03.10: при радиусе 8 и зазоре 2 в овал влезает только 3 из 5
		# функциональных зданий (магазин/таверна/кузня/школа/алхимия) — то
		# есть город мог остаться без кузни. Поэтому радиус поднят до 9:
		# зазор 2 сохраняется, все пять зданий помещаются (проверено: 8 -> 3
		# из 5, 9 -> 5 из 5).
		"herb_region_grid": 4,
		"herb_min_distance": 4,
		"city_radius": 9,
		"city_gap": 2,

		# Респавн Серых. Замер 03.10: респавна НЕ БЫЛО вообще — убил всех в зоне,
		# и зона становилась пустой навсегда. Теперь держим лимит.
		# gray_target — сколько живых Серых держим; берётся из зоны, если 0.
		# gray_respawn_min_dist — клеток от героя, чтобы зверь не появлялся на глазах.
		# 07.10 пакет B: target поднят, карты не должны быть «пустыми».
		"gray_target": 150,
		"gray_respawn_seconds": 20.0,
		"gray_respawn_min_dist": 26,
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
		"start.gray_count_min": 40,     "start.gray_count_max": 60,
		"start.gray_hp_min": 25,       "start.gray_hp_max": 45,
		"start.gray_damage_min": 4,    "start.gray_damage_max": 6,
		"start.guard_hp_min": 60,      "start.guard_hp_max": 100,
		"start.guard_damage_min": 6,   "start.guard_damage_max": 10,
		"start.guard_count_min": 5,    "start.guard_count_max": 8,
		"start.citizen_hp": 30,
		"start.citizen_count_min": 12, "start.citizen_count_max": 18,
		"start.captain_hp": 120,       "start.captain_damage": 12,
		"start.interest_points": 0,    # руины/стоянки/святилища. Зона новичка остаётся тихой: точки рядом со стартом убивают смысл первого города.
		"start.poi_hp": 60,           "start.poi_damage": 6,
		"start.tree_density": 0.18,

		"mid.gray_count_min": 120,     "mid.gray_count_max": 150,
		"mid.gray_hp_min": 45,         "mid.gray_hp_max": 75,
		"mid.gray_damage_min": 6,      "mid.gray_damage_max": 9,
		"mid.guard_hp_min": 60,        "mid.guard_hp_max": 100,
		"mid.guard_damage_min": 6,     "mid.guard_damage_max": 10,
		"mid.guard_count_min": 5,      "mid.guard_count_max": 8,
		"mid.citizen_hp": 30,
		"mid.citizen_count_min": 12,   "mid.citizen_count_max": 18,
		"mid.captain_hp": 120,         "mid.captain_damage": 12,
		"mid.interest_points": 0,
		"mid.poi_hp": 60,             "mid.poi_damage": 6,
		"mid.tree_density": 0.20,

		"hard.gray_count_min": 140,    "hard.gray_count_max": 180,
		"hard.gray_hp_min": 70,        "hard.gray_hp_max": 120,
		"hard.gray_damage_min": 9,     "hard.gray_damage_max": 14,
		"hard.guard_hp_min": 60,       "hard.guard_hp_max": 100,
		"hard.guard_damage_min": 6,    "hard.guard_damage_max": 10,
		"hard.guard_count_min": 5,     "hard.guard_count_max": 8,
		"hard.citizen_hp": 30,
		"hard.citizen_count_min": 12,  "hard.citizen_count_max": 18,
		"hard.captain_hp": 120,        "hard.captain_damage": 12,
		"hard.interest_points": 0,
		"hard.poi_hp": 60,            "hard.poi_damage": 6,
		"hard.tree_density": 0.22,

		"faction.gray_count_min": 100, "faction.gray_count_max": 130,
		"faction.gray_hp_min": 50,     "faction.gray_hp_max": 95,
		"faction.gray_damage_min": 7,  "faction.gray_damage_max": 11,
		"faction.guard_hp_min": 60,    "faction.guard_hp_max": 100,
		"faction.guard_damage_min": 6, "faction.guard_damage_max": 10,
		"faction.guard_count_min": 5,  "faction.guard_count_max": 8,
		"faction.citizen_hp": 30,
		"faction.citizen_count_min": 12, "faction.citizen_count_max": 18,
		"faction.captain_hp": 120,     "faction.captain_damage": 12,
		"faction.interest_points": 0,
		"faction.poi_hp": 60,         "faction.poi_damage": 6,
		"faction.tree_density": 0.20,
	},
	"debug": {
		# Отладочные переключатели (0 = выкл, 1 = вкл). Ключи заведены, чтобы
		# не править код ради отладки и не оставлять в сборке мусор.
		#
		# all_magic: все 31 заклинание + бесконечная мана. До 03.10 это был
		# жёсткий `static var debug_magic = true` в game.gd — то есть сборка
		# для беты отдавала всю магию, и отключить её без правки кода было
		# нельзя. Теперь это просто ключ.
		"all_magic": 1,
		#
		# fog_of_war: ЧЕСТНО — тумана войны в игре НЕТ, ни строки кода. Ключ
		# заведён заранее (как [mob_tier]), чтобы переключатель существовал
		# и его не пришлось вводить позже; сегодня он ничего не делает.
		# Когда туман появится, 1 = туман включён.
		"fog_of_war": 0,
		#
		# show_coords: подпись координат в HUD. По умолчанию выключена —
		# на экране она выглядела как отладочная, из-за чего сборка читалась
		# как debug-сборка, а не как игра.
		"show_coords": 0,
	},
	"archmage": {
		# Великий маг фракции (пакет 3.0, docs/lore/gdd_archmage.md).
		#
		# ВАЖНО про decay_base/decay_threat: это спад ЗА ОДИН ТИК, а тик идёт
		# каждые sim_interval секунд. В сутках 86400/sim_interval тиков, поэтому
		# спад в сутки = decay * 86400/sim_interval.
		#
		# Первая версия была 0.02 + 0.06, и это давало 4.32 спада в СУТКИ
		# (4320 тиков * 0.02) — фракция падала с 60 до 0 за 14 дней, а держать
		# её требовало 216 слитков в день. Прогон tests/sim_archmage_stakes.py
		# показал настоящие числа; см. коммит с этим ключом.
		"sim_interval": 20.0,     # сек между тиками мага
		"decay_base": 0.0005,     # спад за тик при global_threat = 0  -> 2.16/день
		"decay_threat": 0.0015,   # спад за тик при global_threat = 1  -> 8.64/день
		# Ставки платы. Зелье сильнее слитка намеренно: то, что нужно игроку,
		# нужно и фракции — это и есть конфликт выбора.
		"stake_ingot": 1.0,       # слиток любого металла
		"stake_gold": 1.0,        # за gold_per_stake единиц золота
		"stake_potion": 1.5,      # зелье
		"gold_per_stake": 100,    # сколько золота даёт 1.0 платы
		"power_start": 60.0,      # стартовое могущество
		"power_max": 100.0,
		"tier_1": 35.0,           # порог ступени 1 (offensive)
		"tier_2": 65.0,
		"tier_3": 90.0,
	},
	"stress": {
		# Стресс-тест движка (игрок 07.10): 1000×1000, ×100 деревьев/НПЦ.
		# enabled=1 только для прогона; в проде 0.
		"enabled": 0,
		"map_size": 1000,
		"tree_count": 83700,
		"gray_count": 7500,
		"city_guard_count": 2000,
		"city_citizen_count": 1800,
		"gen_version": 99,
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