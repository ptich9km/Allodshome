#!/usr/bin/env python3
"""Удалить из units_db.json наборы ассетов Аллодов II.

ПОЧЕМУ НЕ `json.dump`. Правило §12: JSON в этом проекте правится ТЕКСТОВОЙ
вставкой, `json.dumps` нельзя. База отформатирована отступом 1 и содержит
многострочные блоки; пересборка её из разобранных словарей переформатировала
бы весь файл (прецедент: массовая правка item_db дала дифф в 20 000 строк вместо
ожидаемых 100). Здесь файл правится как ТЕКСТ: блоки вырезаются по скобкам,
остальное остаётся байт в байт.

ПРОВЕРКИ обязательны и падают с ненулевым кодом:
- результат — валидный JSON;
- число наборов уменьшилось ровно на ожидаемое;
- ни один удаляемый ключ не остался;
- каждый оставшийся ключ на месте, а его блок побайтово не изменился.

Запуск:
    python tests/purge_allods_units.py --dry-run
    python tests/purge_allods_units.py
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

DB = Path(__file__).resolve().parent.parent / "assets" / "units" / "units_db.json"

# Префиксы наборов, чей арт происходит из Аллодов II. Папки удаляются отдельно.
PREFIXES = ("humans/", "heroes/", "heroes_l/", "monsters/")


def split_top_level_blocks(text: str) -> list[tuple[str, int, int]]:
    """Найти блоки верхнего уровня объекта как (ключ, начало, конец).

    Считает скобки по всему файлу, учитывая строки. Возвращает границы так,
    что text[start:end] — это ровно блок `"key": { ... },` вместе с запятой
    и переводом строки после него.

    Глубина стартует с 1: внешняя `{` всего файла — это сам объект, а не блок
    набора. Первый вариант считал её как начало блока, искал ключ перед
    открывающей `{` (то есть в пустоте) и не находил НИ ОДНОГО блока.
    """
    blocks: list[tuple[str, int, int]] = []
    depth = 1
    start = -1
    pending = ""
    n = len(text)
    # Пропускаем ВНЕШНЮЮ `{` самого объекта: если её отдать циклу, глубина
    # уйдёт на лишний уровень и ни один блок набора не закроется — именно так
    # первая версия нашла 0 блоков против 131 набора.
    i = text.index("{") + 1
    while i < n:
        c = text[i]
        if c == '"':
            # пропускаем строку целиком, чтобы скобки внутри не считали
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == '"':
                    break
                i += 1
            i += 1
            continue
        if c == "{":
            if depth == 1:
                # блок набора начинается. Ключ — между кавычками ПЕРЕД
                # открывающей скобкой, поэтому обе кавычки ищем НАЗАД:
                # j — закрывающая, k — открывающая.
                j = text.rfind('"', 0, i)
                k = text.rfind('"', 0, j)
                start = k
                pending = text[k + 1:j]
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 1 and start >= 0:
                end = i + 1
                # захватываем запятую и перевод строки после блока
                if end < n and text[end] == ",":
                    end += 1
                if end < n and text[end] == "\n":
                    end += 1
                blocks.append((pending, start, end))
                start = -1
        i += 1
    return blocks


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true", help="только показать, что будет удалено")
    args = ap.parse_args()

    text = DB.read_text(encoding="utf-8")
    before = json.loads(text)
    n_before = len(before)

    blocks = split_top_level_blocks(text)
    if len(blocks) != n_before:
        print("[FAIL] разбор блоков не сошёлся: %d блоков против %d наборов"
              % (len(blocks), n_before))
        return 1

    doomed = [(k, s, e) for (k, s, e) in blocks if k.startswith(PREFIXES)]
    keep = [(k, s, e) for (k, s, e) in blocks if not k.startswith(PREFIXES)]

    print("наборов до: %d" % n_before)
    print("удаляется:   %d" % len(doomed))
    print("остаётся:    %d" % len(keep))

    by_prefix: dict[str, int] = {}
    for k, _, _ in doomed:
        p = k.split("/")[0] + "/"
        by_prefix[p] = by_prefix.get(p, 0) + 1
    for p, c in sorted(by_prefix.items()):
        print("   %-12s %d" % (p, c))

    # контроль: остальные наборы должны быть нетронуты
    kept_blocks = {k: text[s:e] for k, s, e in keep}

    out = text
    # вырезаем с конца, чтобы смещения не «поехали»
    for k, s, e in sorted(doomed, key=lambda b: -b[1]):
        out = out[:s] + out[e:]

    # ХВОСТОВАЯ ЗАПЯТАЯ. Если удалён ПОСЛЕДНИЙ блок файла, у нового последнего
    # блока остаётся запятая перед закрывающей скобкой объекта — JSON такой
    # файл не принимает («Illegal trailing comma»). Первая версия на этом
    # падала, и хорошо, что проверка не дала записать битый файл.
    stripped = out.rstrip()
    if not stripped.endswith("}"):
        print("[FAIL] файл не заканчивается закрывающей скобкой")
        return 1
    close_at = len(stripped) - 1
    j = close_at - 1
    while j >= 0 and stripped[j] in " \t\r\n":
        j -= 1
    if j >= 0 and stripped[j] == ",":
        out = stripped[:j] + stripped[j + 1:] + out[len(stripped):]
    elif j >= 0 and stripped[j] == "{":
        print("[FAIL] после удаления не осталось ни одного набора")
        return 1

    if args.dry_run:
        print("\n[dry-run] файл не тронут")
        return 0

    # --- проверки результата ---
    try:
        after = json.loads(out)
    except Exception as e:  # noqa: BLE001
        print("[FAIL] результат не является валидным JSON: %s" % e)
        return 1

    if len(after) != n_before - len(doomed):
        print("[FAIL] наборов после: %d, ожидалось %d"
              % (len(after), n_before - len(doomed)))
        return 1

    left = [k for k in after if k.startswith(PREFIXES)]
    if left:
        print("[FAIL] остались удаляемые наборы: %s" % left[:5])
        return 1

    # каждый оставшийся блок должен совпасть побайтово с исходным.
    # Исключение — ПОСЛЕДНИЙ оставшийся блок: у него хвостовая запятая снята
    # починкой выше, поэтому сверяем содержимое без неё.
    last_keep_key = keep[-1][0] if keep else ""
    for k, s, e in keep:
        block = kept_blocks[k]
        if k == last_keep_key:
            needle = block.rstrip(" ,\t\r\n")
            if needle and needle not in out:
                print("[FAIL] содержимое последнего блока `%s` изменилось" % k)
                return 1
            continue
        if block not in out:
            print("[FAIL] блок оставленного набора `%s` изменился" % k)
            return 1

    dropped_bytes = len(text) - len(out)

    # ФОРМА ХВОСТА. Первый прогон оставил закрывающую скобку объекта с
    # отступом 2 пробела вместо 0 — JSON от этого валиден, но файл перестаёт
    # быть тем же по виду, и такой хвост тихо тащится дальше по всей базе.
    if not out.endswith("\n }\n}\n"):
        print("[FAIL] хвост файла не соответствует исходному виду: %r" % out[-10:])
        return 1

    DB.write_text(out, encoding="utf-8", newline="")
    print("\n[ok] удалено %d наборов, %d байт" % (len(doomed), dropped_bytes))
    print("[ok] осталось наборов: %d" % len(after))
    print("[ok] все оставшиеся блоки побайтово не тронуты")
    print("[ok] хвост файла сохранил исходный вид")
    return 0


if __name__ == "__main__":
    sys.exit(main())
