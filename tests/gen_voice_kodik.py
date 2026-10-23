#!/usr/bin/env python3
"""Озвучка реплик через KodikRouter (ElevenLabs v3) и вставка в sound_db.json.

Тексты и режиссёрские теги — `assets/audio/voice_lines.json` (правится вручную).
Файлы кладутся в `assets/audio/sfx/voice/`, индекс обновляется только для
ключей `voice.*` — остальные ветки `sound_db.json` не трогаются.

Ключ: env KODIK_API_KEY или `.kodik_key` в корне репо.

Запуск:
  python tests/gen_voice_kodik.py --list          # что отсутствует
  python tests/gen_voice_kodik.py                 # сгенерировать недостающее
  python tests/gen_voice_kodik.py --force voice.hero.male.attack.1
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = "https://api.kodikrouter.ru/v1"
REPO = Path(__file__).resolve().parent.parent
KEY_FILE = REPO / ".kodik_audio_key"
LEGACY_KEY_FILE = REPO / ".kodik_key"
LINES = REPO / "assets" / "audio" / "voice_lines.json"
DB = REPO / "assets" / "audio" / "sound_db.json"
OUT = REPO / "assets" / "audio" / "sfx" / "voice"


def load_key() -> str:
    key = os.environ.get("KODIK_AUDIO_KEY", "").strip()
    if key:
        return key
    # Отдельный ключ: ключ из `.kodik_key` выдан под картинки и не имеет
    # доступа к аудио-моделям (403 «модель не разрешена»).
    if KEY_FILE.exists():
        key = KEY_FILE.read_text(encoding="utf-8").strip()
        if key:
            return key
    key = os.environ.get("KODIK_API_KEY", "").strip()
    if key:
        return key
    if LEGACY_KEY_FILE.exists():
        key = LEGACY_KEY_FILE.read_text(encoding="utf-8").strip()
        if key:
            return key
    sys.exit(f"API key not found: set KODIK_AUDIO_KEY or create {KEY_FILE}")


def speech(key: str, model: str, voice: str, text: str, out: Path) -> None:
    body = json.dumps({
        "model": model,
        "input": text,
        "voice": voice,
        "response_format": "mp3",
    }).encode("utf-8")
    req = urllib.request.Request(BASE + "/audio/speech", data=body, method="POST")
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    # Шлюз отбивает 403 на дефолтный User-Agent Python-urllib.
    req.add_header("User-Agent", "AllodsHome/1.0")
    # Повтор с тем же ключом не спишет деньги второй раз (шлюз помнит 24 ч).
    req.add_header("Idempotency-Key", "voice-" + hashlib.sha1(
        f"{model}|{voice}|{text}".encode("utf-8")).hexdigest()[:24])
    audio = b""
    ctype = ""
    last_error = ""
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=600) as resp:
                audio = resp.read()
                ctype = resp.headers.get("Content-Type", "")
            break
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="replace")
            if e.code in (429, 500, 502, 503, 504) and attempt < 2:
                last_error = f"HTTP {e.code}: {detail[:120]}"
                print(f"  ... шлюз, попытка {attempt + 1}/3: {last_error}")
                time.sleep(4 * (attempt + 1))
                continue
            sys.exit(f"HTTP {e.code} {out.name}\n{detail}")
        except urllib.error.URLError as e:
            last_error = str(e)
            print(f"  ... сеть, попытка {attempt + 1}/3: {last_error}")
            time.sleep(3 * (attempt + 1))
    if not audio:
        sys.exit(f"{out.name}: сеть недоступна ({last_error})")
    if not ctype.startswith("audio/") or len(audio) < 2048:
        sys.exit(f"{out.name}: ответ не аудио ({ctype}, {len(audio)} B)")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(audio)
    print(f"  OK {out.name}: {len(audio) // 1024} KB")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--force", nargs="*", default=[], help="ключи, которые переозвучить")
    args = ap.parse_args()

    cfg = json.loads(LINES.read_text(encoding="utf-8"))
    model = str(cfg.get("model", "elevenlabs/eleven-v3"))
    gain = float(cfg.get("gain_db", -2.0))
    lines: list[dict] = cfg["lines"]
    OUT.mkdir(parents=True, exist_ok=True)

    todo = []
    for line in lines:
        key = str(line["key"])
        rel = "voice/" + key.split(".", 1)[1].replace(".", "_") + ".mp3"
        path = REPO / "assets" / "audio" / "sfx" / rel
        if path.exists() and key not in args.force:
            continue
        todo.append((line, rel, path))

    if args.list:
        for line, rel, path in todo:
            print(("нет  " if not path.exists() else "есть ") + rel)
        print(f"\nвсего строк: {len(lines)}, к озвучке: {len(todo)}")
        return 0
    if not todo:
        print("всё озвучено")
    else:
        api_key = load_key()
        for line, rel, path in todo:
            print(f"-> {line['key']}")
            speech(api_key, model, str(line["voice"]), str(line["text"]), path)

    db = json.loads(DB.read_text(encoding="utf-8"))
    keys: dict = db.setdefault("keys", {})
    for line in lines:
        key = str(line["key"])
        rel = "voice/" + key.split(".", 1)[1].replace(".", "_") + ".mp3"
        keys[key] = {
            "bus": "Voice",
            "gain_db": gain,
            "pitch_jitter": 0.0,
            "files": [rel],
            "subtitle": str(line.get("subtitle", "")),
        }
    DB.write_text(json.dumps(db, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"sound_db.json: voice-ключей {sum(1 for k in keys if k.startswith('voice.'))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
