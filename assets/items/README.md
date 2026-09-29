# Одежда и броня — Allodshome

Текстуры одежды, нарезанные из атласа `import/ChatGPTArmor1.png` и перекрашенные
в цвета металлов фракций.

---

## Каталоги

| Каталог | Что внутри | Кол-во |
|---|---|---|
| `base/` | неокрашенные текстуры, 3 сета × 9 слотов × 4 качества | 108 |
| `faction/common/` | бронза, железо, золото | 54 |
| `faction/light_alliance/` | argentum, lutetium, lanthanum, terbium | 72 |
| `faction/fire_hordes/` | wolfram, chromium, cobalt, titanium | 72 |
| `faction/reapers/` | thorium, uranium, plutonium, radium | 72 |
| `faction/druid_circle/` | gallium, yttrium, promethium, neodymium | 72 |

**Итого 450 PNG.** Контактные листы (`_contact_sheet.png`) — выход dev-инструмента,
в `.gitignore`.

---

## Именование

```text
base/{set}_{slot}_{quality}.png                 неокрашенная
faction/{group}/{metal}_{set}_{slot}_{quality}.png   перекрашенная
```

`set` = `light` | `heavy` | `magic`
`slot` = `head`, `chest`, `bracers`, `gloves`, `legs`, `ring`, `amulet`, `shirt`, `cloak`
`quality` = `cheap` | `common` | `good` | `elite`

**Качество = тир металла.** У каждой группы 4 металла и 4 качества, они
сопоставлены один к одному: `cheap` = 1-й металл группы, `elite` = 4-й.
Поэтому у металла ровно 18 файлов (2 сета × 9 слотов), а не 72.

| группа | cheap | common | good | elite |
|---|---|---|---|---|
| `common` | bronze | iron | steel | gold |
| `light_alliance` | argentum | lutetium | lanthanum | terbium |
| `fire_hordes` | wolfram | chromium | cobalt | titanium |
| `reapers` | thorium | uranium | plutonium | radium |
| `druid_circle` | gallium | yttrium | promethium | neodymium |

Цвета — в `faction_palette.json` (источник правды для генератора). Первые 19
значений совпадают с таблицей в `assets/loot_icons/README.md`; `gold`
(212, 175, 55) добавлен как 4-й тир группы `common`.

---

## Формат

Текстура = прямоугольник по содержимому предмета, **длинная сторона 80 px**,
пропорции исходника сохранены, фон прозрачный. Размеров 29, от `(59, 80)`
(амулет по вертикали) до `(80, 77)`.

Квадрат 80×80 из `import/ChatGPTArmor1_atlas_description.md` **невозможен**:
все 108 предметов нарисованы горизонтально, ячейки атласа шире высоты
(129…147 × 66…85 px). Замер: центральный квадрат срезает медиану 15% и
максимум 44% ширины предмета, бока теряют 95 предметов из 108. Поэтому по
решению игрока выбран прямоугольник по содержимому — обрезки нет.

---

## Перекраска: дуотон по светлоте

Тон исходного пикселя заменяется на цвет металла, светлота и блики берутся из
исходника. Значение пикселя раскладывается по рампе:

```text
тень   = цвет × 0.22
середина = цвет
блик   = mix(цвет, белый, 0.72)
```

Альфа-канал копируется **байт в байт** (проверено на всех 342 файлах).

**Почему не зональная перекраска** («красить только металл, кожу оставить»):
замер по base показал, что зоны по цвету неразделимы — синяя рубашка
`light_shirt_common` даёт 52% насыщенных пикселей, а золотое кольцо
`heavy_ring_elite` — 61%. «Самоцвет» и «ткань» выглядят одинаково, и
классификатор зон давал бы случайный результат.

**Калибровка тёмных металлов.** У металлов с `V < 0.62` (cobalt, plutonium,
thorium, wolfram) середина рампы поднимается до `V = 0.46`, иначе предмет
уходит в почти чёрный и сливается с тёмным UI склада. Проверено на замере:
plutonium `(60,40,80)` → середина `(87,58,117)`.

---

## Генерация

```powershell
# 1. Нарезка атласа в base/ (нужно один раз, дальше base/ — источник)
python tests/extract_chatgpt_armor.py

# 2. Перекраска base/ в faction/
python tests/gen_faction_armor_tint.py --report   # только отчёт
python tests/gen_faction_armor_tint.py            # перекрасить всё
python tests/gen_faction_armor_tint.py --sheet    # + контактные листы
python tests/gen_faction_armor_tint.py --check    # сверить SHA256 с диском
```

Оба скрипта детерминированы: `random.*` не используется, `--check` сверяет
SHA256 перегенерации с файлами на диске.

---

## Известные ограничения

- **`magic_*` (36 файлов) не перекрашивается** — по решению игрока магическая
  одежда своя, с оттенком фракции она не вяжется. Лежит только в `base/`.
- **`steel` (4-й тир `common` по позиции — он же `good`) не перекрашивается**:
  в палитре помечен `is_base: true`, это сами файлы `base/`. Сталь = вид
  «как есть», файл не дублируется.
- **12 металлов из 20 не имеют ни одного предмета** в `assets/items/item_db.json`:
  argentum, lutetium, lanthanum, wolfram, chromium, cobalt, thorium, uranium,
  gallium, yttrium, promethium, neodymium. Текстуры для них созданы, но
  показать их пока нечем — нужны предметы.
- **Эти ассеты пока не подключены к игре.** `item_db.json` у 508 предметов
  ссылается на 508 уникальных иконок в `assets/inventory/`.
