#!/usr/bin/env python3
"""Показать модели изображений KodikRouter вместе с ценами.

Нужно для выбора дешёвой модели: список `/images/models` цен НЕ содержит,
цены лежат на отдельном адресе `/images/models/<id>/endpoints`, и там у
модели может быть несколько эндпоинтов с разными провайдерами — берём
самый дешёвый доступный.

Запуск:
  python tests/model_prices.py            # все модели с ценой картинки
  python tests/model_prices.py --free     # только бесплатные (цена 0)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_image_kodik import load_key, _req  # noqa: E402


def cheapest(mid: str, key: str) -> str:
    """Самая дешёвая цена картинки по всем эндпоинтам модели."""
    try:
        d = _req("GET", f"/images/models/{mid}/endpoints", None, key)
    except Exception:
        return "?"
    best = None
    for ep in d.get("endpoints", []):
        for p in ep.get("pricing", []):
            if p.get("billable") != "output_image":
                continue
            try:
                c = float(p.get("cost_usd"))
            except (TypeError, ValueError):
                continue
            if best is None or c < best:
                best = c
    if best is None:
        return "н/д"
    if best == 0:
        return "$0"
    if best < 0.001:
        return f"{best:.5f}/ток"
    return f"${best:.4f}"


def main() -> int:
    only_free = "--free" in sys.argv
    key = load_key()
    data = _req("GET", "/images/models", None, key)
    items = data.get("data", data if isinstance(data, list) else [])
    rows = []
    for it in items:
        if not isinstance(it, dict):
            continue
        mid = str(it.get("id", "?"))
        rows.append((cheapest(mid, key), mid))
    if only_free:
        rows = [r for r in rows if r[0] == "$0"]
    rows.sort(key=lambda r: (r[0] != "$0",
                             float(r[0].lstrip("$")) if r[0].startswith("$") else 9.9))
    for price, mid in rows:
        print(f"{price:>12}  {mid}")
    print(f"\nмоделей показано: {len(rows)} из {len(items)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())