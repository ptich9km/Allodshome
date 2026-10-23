#!/usr/bin/env python3
"""WAV-мастера музыки -> OGG q4 для игры.

Почему OGG: 90 секунд стерео в WAV — это ~16 МБ, в OGG q4 — ~2.5 МБ при том же
восприятии для эмбиента. WAV-мастера лежат в `import/audio_src/music/` (gitignore),
в репозиторий идут только OGG.

Запуск:
  python tests/gen_music_ogg.py --check
  python tests/gen_music_ogg.py --ffmpeg C:\\path\\to\\ffmpeg.exe
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "import" / "audio_src" / "music"
OUT = REPO / "assets" / "audio" / "music"
QUALITY = "4"  # ~128 kbps Vorbis

# WAV-мастер -> файл в assets/audio/music
MAP = {
    "1MainTheme.wav": "menu_main.ogg",
    "2OldCity_Rest.wav": "town_rest_1.ogg",
    "2OldCity_Rest2.wav": "town_rest_2.ogg",
    "3Ancient_place.wav": "ancient_1.ogg",
    "3Ancient_place2.wav": "ancient_2.ogg",
    "4Exploration_Atmosphere.wav": "explore_1.ogg",
    "4Exploration_Atmosphere2.wav": "explore_2.ogg",
    "5Fight_is_mylife.wav": "combat_1.ogg",
}


def find_ffmpeg(explicit: str) -> str:
    if explicit:
        return explicit
    env = os.environ.get("FFMPEG", "").strip()
    if env:
        return env
    found = shutil.which("ffmpeg")
    if found:
        return found
    sys.exit("ffmpeg не найден: передай --ffmpeg или задай FFMPEG")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--ffmpeg", default="")
    args = ap.parse_args()

    missing = [n for n in MAP if not (SRC / n).exists()]
    if missing:
        print("нет WAV-мастеров:")
        for n in missing:
            print("  " + n)
        return 1
    print(f"мастеров на месте: {len(MAP)}")
    if args.check:
        return 0

    ffmpeg = find_ffmpeg(args.ffmpeg)
    OUT.mkdir(parents=True, exist_ok=True)
    for src, dst in MAP.items():
        target = OUT / dst
        cmd = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
               "-i", str(SRC / src), "-vn", "-map_metadata", "-1",
               "-c:a", "libvorbis", "-q:a", QUALITY, str(target)]
        subprocess.run(cmd, check=True)
        print(f"  {dst}: {target.stat().st_size / 1_048_576:.2f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
