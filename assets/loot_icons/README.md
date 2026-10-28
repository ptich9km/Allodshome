# Loot Icons — Allodshome

Ассеты для системы лута. Все файлы — PNG с прозрачным фоном.

> **Пакет A (28.10):** 16 фракционных металлов удалены из игры. Остались
> иконки для четырёх общих металлов: `{bronze,iron,steel,gold}_{weapon,armor}.png`.

---

## Мечи (Swords) — 4 файла

Выпадают с убитых врагов как лут.

**Формат:** 32×32 PNG, прозрачный фон. bronze/iron/gold с 20.10 — производные
от одобренного атласа предметов (см. «Обновление 20.10» ниже).

**Именование:** `{material}_weapon.png`

---

## Нагрудники (Chest Armor) — 4 файла

Выпадают с убитых врагов как лут.

**Формат:** 32×32 PNG, прозрачный фон. bronze/iron/gold с 20.10 — производные
от одобренного атласа предметов (см. «Обновление 20.10» ниже).

**Именование:** `{material}_armor.png`

---

## Слитки металлов (Metal Ingots)

Слитки лежат **не здесь**, а в `assets/professions/blacksmith/`
(`{material}_ingot.png`, 80×80): в `loot_icons/` их нет — раньше секция
утверждала обратное, это устарело.

---

## Бутылки (Potion Bottles) — 6 типов × 4 кадра

Анимированные бутылки маны и жизни для лута.

**Типы:**
- `health` — бутылка жизни (красная жидкость)
- `mana` — бутылка маны (синяя жидкость)

**Размеры:**
- `small` — маленькая
- `medium` — средняя
- `large` — большая

**Файлы:**
- `{type}_{size}_frame{00-03}.png` — отдельные кадры (32×32)
- `{type}_{size}_spritesheet.png` — 4 кадра в строке (128×32)

**Анимация:** покачивание (bobbing) + блик на жидкости

---

## Обновление 20.10 — bronze/iron/gold: программные дроп-иконки

`{bronze,iron,gold}_{weapon,armor}.png` перезаписаны; `gold_{weapon,armor}.png`
созданы впервые — раньше в loot_icons золотого снаряжения не было, и любая
вещь с material="gold" рисовалась на земле монетой (`LootIcons.icon_for` →
`gold_icon()`).

- **Источник:** одобренные игроком иконки атласа предметов (установлены 20.10) —
  `assets/items/faction_w/common/{metal}_one_handed_sword_*.png` (оружие) и
  `assets/items/faction/common/{metal}_heavy_chest_*.png` (броня), 72×80.
- **Трансформация** (программная, без ИИ-генераций): alpha-crop → поворот 20°
  (BICUBIC) → вертикальный squash ×0.80 (LANCZOS) → масштаб до 28 px по большей
  стороне → центровка на холст 32×32. Отступление от «nearest only»
  (references/raster-pipeline.md) — сознательный preprocessing pass, как решено
  в tests/slice_items_atlas.py: поворот nearest даёт рваную лесенку на кромках.
- **Скрипт:** `tests/gen_loot_icons_derived.py` (чистый PIL). Превью 4 вариантов:
  `import/loot_icons_derived/_contact_sheet.png`; вариант `v2_tilt20_squash`
  выбран игроком 20.10, установлен `--variant v2_tilt20_squash --install`.
- **Код:** `LootIcons.icon_for` больше не подменяет золотое снаряжение монетой;
  деньги по-прежнему монета — `loot_drop.gd` зовёт `gold_icon()` напрямую.
- **ИИ-путь отменён:** `tests/gen_loot_icons_kodik.py` (генерация картинок
  nano-banana) встал на квоте Gemini (429) и закрыт программной деривацией.

---

## Материалы и фракции

> **Пакет A (28.10):** таблицы фракционных цветов (Альянс Света, Орды Огня,
> Пожинатели, Круг Друидов) удалены вместе с металлами — иконок и слитков
> этих 16 металлов в игре больше нет. Исторически палитра описывала 19
> металлов; сейчас источник правды — группа `common` в
> `assets/items/faction_palette.json`.

### Базовые (общие для всех)
| Материал | Цвет |
|----------|------|
| bronze | коричневый (184, 115, 51) |
| iron | серый (120, 120, 125) |
| steel | светло-серый (192, 192, 200) |
| gold | жёлтый металл (дроп-иконки с 20.10 — из атласа предметов) |

---

## Использование в Godot

```gdscript
# Лут меча с врага
var sword = load("res://assets/loot_icons/steel_weapon.png")  # 32x32

# Лут нагрудника с врага
var armor = load("res://assets/loot_icons/steel_armor.png")  # 32x32

# Анимированная бутылка
var sprite = AnimatedSprite2D.new()
var frames = SpriteFrames.new()
var sheet = load("res://assets/loot_icons/health_small_spritesheet.png")
frames.add_sprite_frame("default", sheet, 0.15)
sprite.sprite_frames = frames
sprite.play()
```

**Поток:** враг умирает → выпадает `{material}_weapon.png` или `{material}_armor.png` → игрок приносит в кузницу → получает `{material}_ingot.png` из `assets/professions/blacksmith/`. В коде иконку выбирает `scripts/loot_icons.gd` (`LootIcons.icon_for`).

---

## Генерация

Скрипты (корень проекта):
- `tests/gen_loot_icons_derived.py` — bronze/iron/gold дроп-иконки из
  одобренного атласа предметов (уменьшение + наклон, обновление 20.10)
- `generate_potion_icons.py` — бутылки 32×32 (4 кадра анимации)
- `tests/gen_loot_icons_derived.py` — bronze/iron/gold дроп-иконки из
  одобренного атласа предметов (уменьшение + наклон, обновление 20.10)
