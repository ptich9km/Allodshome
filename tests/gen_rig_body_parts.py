#!/usr/bin/env python3
"""Генерация 6 частей тела для 2D-рига через KodikRouter/seedream.

Каждая часть генерируется отдельно на магентном фоне (255,0,255).
2 варианта на часть для выбора лучшего.

Запуск:
    python tests/gen_rig_body_parts.py              # все 6 частей × 2
    python tests/gen_rig_body_parts.py --part torso # только torso
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GEN = REPO / "tests" / "gen_image_kodik.py"
OUT_DIR = REPO / "import" / "_rig_parts"
MODEL = "bytedance-seed/seedream-5-0-flash"

# Общий префикс: pixel art, профиль вправо, магентный фон
BASE = (
    "Pixel art game asset, single isolated body part on solid magenta background "
    "(RGB 255,0,255), side profile view facing right, fantasy warrior style, "
    "clean hard edges, no anti-aliasing, no text, no watermark, "
    "no thin details, no chains, no flowing cloth. "
)

PARTS = {
    "torso": (
        BASE +
        "A fantasy warrior TORSO only: leather chest armor with shoulder pauldron, "
        "belt at bottom, neck opening at top. NO arms, NO head, NO legs. "
        "Centered on canvas, the waist at the bottom edge."
    ),
    "head": (
        BASE +
        "A fantasy warrior HEAD only: side profile facing right, short brown hair, "
        "determined expression, no helmet. NO body attached. "
        "Centered on canvas, the neck at the bottom edge."
    ),
    "arm": (
        BASE +
        "A fantasy warrior UPPER ARM only: shoulder to elbow, leather bracer, "
        "no hand. Hanging straight down. NO torso attached. "
        "Centered on canvas, the shoulder at the top edge."
    ),
    "forearm": (
        BASE +
        "A fantasy warrior FOREARM with fist: elbow to hand, leather bracer, "
        "closed fist at bottom. Hanging straight down. NO upper arm attached. "
        "Centered on canvas, the elbow at the top edge."
    ),
    "thigh": (
        BASE +
        "A fantasy warrior UPPER LEG only: hip to knee, leather pants, "
        "no foot. Hanging straight down. NO torso attached. "
        "Centered on canvas, the hip at the top edge."
    ),
    "shin": (
        BASE +
        "A fantasy warrior LOWER LEG with boot: knee to foot, leather boot, "
        "no knee detail. Hanging straight down. NO thigh attached. "
        "Centered on canvas, the knee at the top edge."
    ),
}


def gen_part(part: str, variant: int, seed: int | None) -> bool:
    out = OUT_DIR / f"{part}_v{variant}.png"
    cmd = [
        sys.executable, str(GEN),
        "--model", MODEL,
        "--prompt", PARTS[part],
        "--out", str(out),
        "--size", "1024x1024",
    ]
    if seed is not None:
        cmd += ["--seed", str(seed)]
    print(f"  {part} v{variant}...", end=" ", flush=True)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    if r.returncode == 0 and out.exists():
        size = out.stat().st_size
        print(f"OK ({size} bytes)")
        return True
    else:
        print(f"FAIL: {r.stderr[:200] if r.stderr else 'no output'}")
        return False


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--part", default="", help="только одна часть")
    ap.add_argument("--variants", type=int, default=2)
    args = ap.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    parts = [args.part] if args.part else list(PARTS.keys())
    ok = 0
    fail = 0
    for part in parts:
        for v in range(args.variants):
            seed = hash(part) % 100000 + v * 7919  # детерминированный seed
            if gen_part(part, v, seed):
                ok += 1
            else:
                fail += 1
    print(f"\nИтого: {ok} OK, {fail} FAIL")


if __name__ == "__main__":
    main()
