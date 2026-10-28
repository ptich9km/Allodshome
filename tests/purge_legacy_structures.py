"""Чистка Аллодовских зданий (ids 1..179) из structure_db.json и assets/structures.

Оставляем только наши здания: 200..206 (перерисованы Alice) и 207..232
(seedream). Записи < 200 — оригинальные тайл-сеты Аллодов 32x32, их папки
удаляются целиком вместе с .import-файлами. Числовые папки (1, 2, 15, 67 …)
в базе не значатся — это остатки старых нарезок, тоже удаляются.

Использование:
    python tests/purge_legacy_structures.py            # показать, что будет
    python tests/purge_legacy_structures.py --apply    # удалить
    python tests/purge_legacy_structures.py --check    # сторож: 0 к возврату

`--check` возвращает 1, если остались записи < 200 или папки без записи.
"""

import io
import json
import os
import shutil
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.path.join(REPO, "assets", "structures", "structure_db.json")
ROOT = os.path.join(REPO, "assets", "structures")
KEEP_LOWEST = 200  # наши здания начинаются с 200
KEEP_DIRS = {"_src"}


def load_db() -> dict:
    with io.open(DB_PATH, encoding="utf-8") as fh:
        return json.load(fh)


def split_db(db: dict) -> tuple:
    keep, drop = {}, {}
    for key, rec in db.items():
        try:
            tid = int(key)
        except (TypeError, ValueError):
            drop[key] = rec
            continue
        if tid < KEEP_LOWEST:
            drop[key] = rec
        else:
            keep[key] = rec
    return keep, drop


def folders_of(records) -> set:
    return {str(r.get("folder", "")) for r in records if str(r.get("folder", ""))}


def main(argv) -> int:
    apply = "--apply" in argv
    check = "--check" in argv

    db = load_db()
    keep, drop = split_db(db)
    kept_folders = folders_of(keep.values())
    drop_folders = sorted(folders_of(drop.values()) - kept_folders)

    on_disk = sorted(
        name for name in os.listdir(ROOT)
        if os.path.isdir(os.path.join(ROOT, name)) and name not in KEEP_DIRS
    )
    orphan = sorted(set(on_disk) - kept_folders)

    print("structure_db: %d записей, из них legacy (<%d): %d, наших: %d"
          % (len(db), KEEP_LOWEST, len(drop), len(keep)))
    print("папок legacy по базе: %d" % len(drop_folders))
    print("папок на диске вне базы (мусор): %d %s"
          % (len(orphan), orphan[:12]))

    if check:
        bad = len(drop) + len(orphan)
        if bad:
            print("RESULT: FAIL purge_legacy_structures — к чистке %d (записи %d, папки %d)"
                  % (bad, len(drop), len(orphan)))
            return 1
        print("RESULT: OK purge_legacy_structures")
        return 0

    if not apply:
        print("DRY RUN: запусти с --apply, чтобы удалить")
        return 0

    removed_dirs = 0
    for folder in sorted(set(drop_folders) | set(orphan)):
        path = os.path.join(ROOT, folder)
        if os.path.isdir(path):
            shutil.rmtree(path)
            removed_dirs += 1

    with io.open(DB_PATH, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(keep, fh, ensure_ascii=False, indent=1)
        fh.write("\n")

    print("удалено папок: %d, записей: %d, осталось записей: %d"
          % (removed_dirs, len(drop), len(keep)))
    print("RESULT: OK purge_legacy_structures")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
