#!/usr/bin/env python3
"""Сборка звуковой библиотеки игры из бесплатных CC0-паков.

Источник — `import/audio_src/` (скачанные паки, в git не идут).
Результат — файлы в `assets/audio/sfx/{ui,combat,magic}/` и индекс
`assets/audio/sound_db.json` (ключ -> файлы + шина + громкость).

Зачем отдельный скрипт: вручную переименовывать 130 файлов и держать
соответствие «ключ -> вариант» невозможно; при замене пака скрипт
перезапускается и индекс пересобирается из таблицы ниже.

Запуск:
  python tests/gen_audio_db.py --check     # только проверить источники
  python tests/gen_audio_db.py             # скопировать + записать индекс

Лицензии и провенанс — `docs/audio-credits.md`.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import wave
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "import" / "audio_src"
OUT = REPO / "assets" / "audio" / "sfx"
INDEX = REPO / "assets" / "audio" / "sound_db.json"

# Пак -> префикс внутри import/audio_src
P = {
    "ki": "kenney_interface-sounds/Audio",
    "ku": "kenney_ui-audio/Audio",
    "kimp": "kenney_impact-sounds/Audio",
    "krpg": "kenney_rpg-audio/Audio",
    "rpg": "rpg_sound_pack/RPG Sound Pack",
    "r80": "80-CC0-RPG-SFX_0",
    "sw": "swishes/swishes",
    "stn": "impact_-_starninjas",
    "water": "water-splash-slime-sfx",
    "dl": "dl",
    "cure": "dl/curemagic",
}

# key -> (шина, gain_db, pitch_jitter, [исходники])
# gain — стартовая калибровка на слух, дальше правится в JSON без кода.
LIB: dict[str, tuple[str, float, float, list[str]]] = {}


def add(key: str, bus: str, gain: float, jitter: float, files: list[str]) -> None:
    LIB[key] = (bus, gain, jitter, files)


# --- UI -------------------------------------------------------------------
add("ui.hover", "UI", -11.0, 0.05,
    [f"{P['ku']}/rollover{i}.ogg" for i in range(1, 7)])
add("ui.click", "UI", -9.0, 0.04,
    [f"{P['ki']}/click_001.ogg"] + [f"{P['ku']}/click{i}.ogg" for i in range(1, 6)])
add("ui.confirm", "UI", -7.0, 0.03,
    [f"{P['ki']}/confirmation_{i:03d}.ogg" for i in range(1, 5)])
add("ui.back", "UI", -9.0, 0.04,
    [f"{P['ki']}/back_{i:03d}.ogg" for i in range(1, 5)])
add("ui.error", "UI", -6.0, 0.02,
    [f"{P['ki']}/error_{i:03d}.ogg" for i in range(1, 5)])
add("ui.book_open", "UI", -7.0, 0.02, [f"{P['krpg']}/bookOpen.ogg"])
add("ui.page", "UI", -9.0, 0.04,
    [f"{P['r80']}/book_{i:02d}.ogg" for i in range(1, 5)])
add("ui.scroll", "UI", -11.0, 0.05,
    [f"{P['ki']}/scroll_{i:03d}.ogg" for i in range(1, 6)])
add("ui.notify", "UI", -8.0, 0.03,
    [f"{P['ki']}/bong_001.ogg"] + [f"{P['ki']}/question_{i:03d}.ogg" for i in range(1, 4)])
add("ui.message_in", "UI", -9.0, 0.03,
    [f"{P['ki']}/maximize_{i:03d}.ogg" for i in range(1, 5)])
add("ui.message_out", "UI", -9.0, 0.03,
    [f"{P['ki']}/minimize_{i:03d}.ogg" for i in range(1, 5)])
add("ui.complete", "UI", -7.0, 0.02,
    [f"{P['r80']}/item_gem_{i:02d}.ogg" for i in range(1, 5)])
add("ui.fail", "UI", -7.0, 0.02,
    [f"{P['ki']}/error_{i:03d}.ogg" for i in range(5, 9)])
add("ui.equip", "UI", -7.0, 0.03, [
    f"{P['rpg']}/inventory/chainmail1.wav",
    f"{P['rpg']}/inventory/chainmail2.wav",
    f"{P['rpg']}/inventory/armor-light.wav",
    f"{P['rpg']}/inventory/cloth.wav",
    f"{P['rpg']}/inventory/cloth-heavy.wav",
])
add("ui.unequip", "UI", -9.0, 0.04, [
    f"{P['rpg']}/inventory/cloth.wav",
    f"{P['rpg']}/inventory/cloth-heavy.wav",
    f"{P['rpg']}/inventory/wood-small.wav",
])
add("ui.craft", "UI", -7.0, 0.03,
    [f"{P['r80']}/metal_{i:02d}.ogg" for i in range(1, 4)])
add("ui.coins", "UI", -9.0, 0.04,
    [f"{P['r80']}/item_coins_{i:02d}.ogg" for i in range(1, 5)])

# --- Бой ------------------------------------------------------------------
add("combat.swing.light", "SFX", -5.0, 0.06,
    [f"{P['sw']}/swish-{i}.wav" for i in range(1, 5)])
add("combat.swing.heavy", "SFX", -3.0, 0.06,
    [f"{P['sw']}/swish-{i}.wav" for i in range(9, 14)])
add("combat.miss", "SFX", -5.0, 0.06,
    [f"{P['sw']}/swish-{i}.wav" for i in range(5, 9)])
add("combat.hit.flesh", "SFX", -2.0, 0.04,
    [f"{P['kimp']}/impactSoft_heavy_{i:03d}.ogg" for i in range(1, 5)]
    + [f"{P['kimp']}/impactPunch_medium_{i:03d}.ogg" for i in range(1, 3)])
add("combat.hit.armor", "SFX", -2.0, 0.04,
    [f"{P['kimp']}/impactMetal_medium_{i:03d}.ogg" for i in range(1, 4)]
    + [f"{P['kimp']}/impactPlate_heavy_{i:03d}.ogg" for i in range(1, 3)])
add("combat.hit.wood", "SFX", -4.0, 0.05,
    [f"{P['kimp']}/impactWood_medium_{i:03d}.ogg" for i in range(1, 4)])
add("combat.hit.shield", "SFX", -2.0, 0.04,
    [f"{P['stn']}/impact.{i}.ogg" for i in range(1, 6)])
add("combat.hit.magic", "SFX", -3.0, 0.04,
    [f"{P['stn']}/impact.{i}.ogg" for i in range(6, 11)])
add("combat.weapon.sword", "SFX", -5.0, 0.04,
    [f"{P['krpg']}/drawKnife{i}.ogg" for i in range(1, 4)])
add("combat.weapon.axe", "SFX", -4.0, 0.04,
    [f"{P['krpg']}/chop.ogg", f"{P['kimp']}/impactWood_heavy_001.ogg"])
add("combat.weapon.blunt", "SFX", -4.0, 0.04,
    [f"{P['kimp']}/impactWood_heavy_{i:03d}.ogg" for i in range(1, 4)])
add("combat.bow", "SFX", -4.0, 0.05, ["__bake_bow__"])
add("combat.death", "SFX", -3.0, 0.03,
    [f"{P['r80']}/creature_die_01.ogg", f"{P['kimp']}/impactSoft_heavy_003.ogg"])
add("combat.body_fall", "SFX", -4.0, 0.04,
    [f"{P['kimp']}/impactSoft_heavy_004.ogg",
     f"{P['kimp']}/impactGeneric_light_001.ogg"])

# --- Магия ----------------------------------------------------------------
add("magic.fire.arrow", "SFX", -4.0, 0.04,
    [f"{P['r80']}/spell_fire_0{i}.ogg" for i in (1, 2)])
add("magic.fire.bolt", "SFX", -3.0, 0.03,
    [f"{P['r80']}/spell_fire_0{i}.ogg" for i in (3, 4)])
add("magic.fire.wall", "SFX", -4.0, 0.03,
    [f"{P['r80']}/spell_fire_0{i}.ogg" for i in (5, 6)])
add("magic.fire.ward", "SFX", -5.0, 0.03,
    [f"{P['r80']}/spell_fire_07.ogg", f"{P['dl']}/magical_1.ogg"])
add("magic.ice.bolt", "SFX", -5.0, 0.03,
    [f"{P['dl']}/magical_1.ogg", f"{P['dl']}/magical_2.ogg"])
add("magic.poison.cloud", "SFX", -5.0, 0.04,
    [f"{P['water']}/slime_{i:02d}.ogg" for i in range(1, 4)])
add("magic.blizzard", "SFX", -4.0, 0.03,
    [f"{P['dl']}/magical_3.ogg", f"{P['dl']}/magical_4.ogg"])
add("magic.water.ward", "SFX", -5.0, 0.04,
    [f"{P['water']}/splash_{i:02d}.ogg" for i in range(1, 4)])
add("magic.acid.stream", "SFX", -5.0, 0.04,
    [f"{P['water']}/slime_{i:02d}.ogg" for i in range(4, 7)])
add("magic.lightning", "SFX", -4.0, 0.03,
    [f"{P['dl']}/electricspell.ogg", f"{P['dl']}/electricspell2.ogg"])
add("magic.prismatic", "SFX", -4.0, 0.03,
    [f"{P['dl']}/magical_4.ogg", f"{P['dl']}/magical_5.ogg"])
add("magic.invisibility", "SFX", -5.0, 0.03,
    [f"{P['dl']}/magical_5.ogg", f"{P['dl']}/magical_6.ogg"])
add("magic.air.ward", "SFX", -5.0, 0.03,
    [f"{P['dl']}/magical_6.ogg", f"{P['dl']}/magical_7.ogg"])
add("magic.darkness", "SFX", -5.0, 0.03,
    [f"{P['dl']}/magical_2.ogg", f"{P['dl']}/magical_3.ogg"])
add("magic.earth.bolt", "SFX", -4.0, 0.03,
    ["dl/Earth Element Magic Spell_4.ogg"] + [f"{P['r80']}/stones_{i:02d}.ogg" for i in (1, 2)])
add("magic.earth.wall", "SFX", -4.0, 0.03,
    ["dl/Earth Element Magic Spell_3.ogg", f"{P['r80']}/stones_03.ogg"])
add("magic.curse.stone", "SFX", -5.0, 0.03,
    [f"{P['r80']}/stones_04.ogg", f"{P['dl']}/magical_3.ogg"])
add("magic.earth.ward", "SFX", -5.0, 0.03,
    ["dl/Earth Element Magic Spell_4.ogg", f"{P['r80']}/stones_02.ogg"])
add("magic.diamond.dust", "SFX", -5.0, 0.04,
    [f"{P['r80']}/item_gem_{i:02d}.ogg" for i in range(1, 4)])
add("magic.bless", "SFX", -5.0, 0.03,
    [f"{P['cure']}/Cure{i}.wav" for i in range(1, 4)])
add("magic.haste", "SFX", -5.0, 0.03,
    [f"{P['dl']}/magical_6.ogg", f"{P['dl']}/magical_7.ogg"])
add("magic.heal", "SFX", -5.0, 0.03,
    [f"{P['dl']}/healing.ogg"] + [f"{P['cure']}/Cure{i}.wav" for i in range(4, 7)])
add("magic.drain", "SFX", -5.0, 0.03,
    [f"{P['dl']}/magical_7.ogg", f"{P['dl']}/magical_2.ogg"])
add("magic.shield", "SFX", -5.0, 0.03,
    [f"{P['stn']}/impact.{i}.ogg" for i in (1, 2)] + [f"{P['dl']}/magical_1.ogg"])
add("magic.summon", "SFX", -4.0, 0.03,
    [f"{P['dl']}/magical_6.ogg", f"{P['dl']}/magical_3.ogg"])
add("magic.animate_dead", "SFX", -5.0, 0.03,
    [f"{P['dl']}/magical_3.ogg", f"{P['dl']}/magical_7.ogg"])
add("magic.teleport", "SFX", -5.0, 0.02,
    [f"{P['dl']}/teleport.wav", f"{P['dl']}/teleport.ogg"])
add("magic.curse", "SFX", -5.0, 0.03,
    [f"{P['dl']}/magical_2.ogg", f"{P['dl']}/magical_5.ogg"])
add("magic.slow", "SFX", -5.0, 0.03,
    [f"{P['dl']}/magical_3.ogg", f"{P['dl']}/magical_4.ogg"])
add("magic.light", "SFX", -7.0, 0.03,
    [f"{P['ki']}/bong_001.ogg", f"{P['dl']}/magical_5.ogg"])
add("magic.control_spirit", "SFX", -5.0, 0.03,
    [f"{P['dl']}/magical_7.ogg", f"{P['dl']}/magical_4.ogg"])


# --- Сборка лука из двух CC0-сэмплов -------------------------------------
def _read_wav_mono(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as w:
        ch, sw, rate = w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(w.getnframes())
    if sw == 2:
        data = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    elif sw == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        v = np.where(v & 0x800000, v - 0x1000000, v)
        data = v.astype(np.float32) / 8388608.0
    elif sw == 4:
        data = np.frombuffer(raw, dtype="<i4").astype(np.float32) / 2147483648.0
    else:
        raise SystemExit(f"{path}: неподдерживаемая разрядность {sw * 8}-bit")
    if ch > 1:
        data = data.reshape(-1, ch).mean(axis=1)
    return data, rate


def _write_wav_mono(path: Path, data: np.ndarray, rate: int) -> None:
    peak = float(np.max(np.abs(data))) or 1.0
    data = data / peak * 0.72
    pcm = np.clip(data * 32767.0, -32768, 32767).astype("<i2")
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


def bake_bow(dest_dir: Path) -> list[str]:
    """Тетива: свист + деревянный щелчок через 28 мс. Всё CC0, без CC-BY."""
    made: list[str] = []
    swish = ["swish-1.wav", "swish-2.wav", "swish-3.wav"]
    for i, name in enumerate(swish, start=1):
        a, rate = _read_wav_mono(SRC / P["sw"] / name)
        b, brate = _read_wav_mono(SRC / P["rpg"] / "inventory" / "wood-small.wav")
        if brate != rate:
            # ресемплим простым линейным индексом — для 0.2 с этого достаточно
            idx = (np.arange(int(len(b) * rate / brate)) * brate / rate).astype(int)
            b = b[np.clip(idx, 0, len(b) - 1)]
        offset = int(0.028 * rate)
        total = max(len(a), offset + len(b))
        out = np.zeros(total, dtype=np.float32)
        out[:len(a)] += a * 0.9
        out[offset:offset + len(b)] += b * 0.55
        fname = f"bow_{i:02d}.wav"
        _write_wav_mono(dest_dir / fname, out, rate)
        made.append(fname)
    return made


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="только проверить исходники")
    args = ap.parse_args()

    missing = []
    for key, (_bus, _gain, _jit, files) in LIB.items():
        for f in files:
            if f == "__bake_bow__":
                for n in ("swish-1.wav", "swish-2.wav", "swish-3.wav"):
                    if not (SRC / P["sw"] / n).exists():
                        missing.append(f"{key}: {P['sw']}/{n}")
                continue
            if not (SRC / f).exists():
                missing.append(f"{key}: {f}")
    if missing:
        print("НЕТ ИСХОДНИКОВ:")
        for m in missing:
            print("  " + m)
        return 1
    print(f"источники на месте: {len(LIB)} ключей, "
          f"{sum(len(v[3]) for v in LIB.values())} записей")
    if args.check:
        return 0

    if OUT.exists():
        # voice/ принадлежит gen_voice_kodik.py — не трогаем, иначе платные
        # реплики пришлось бы генерировать заново.
        for sub in ("ui", "combat", "magic"):
            shutil.rmtree(OUT / sub, ignore_errors=True)
    keys: dict[str, dict] = {}
    copied = 0
    for key, (bus, gain, jitter, files) in sorted(LIB.items()):
        family = key.split(".")[0]
        dest_dir = OUT / family
        dest_dir.mkdir(parents=True, exist_ok=True)
        slug = key.split(".", 1)[1].replace(".", "_")
        rels: list[str] = []
        if files == ["__bake_bow__"]:
            for name in bake_bow(dest_dir):
                rels.append(f"{family}/{name}")
                copied += 1
        else:
            for i, src in enumerate(files, start=1):
                s = SRC / src
                ext = s.suffix.lower()
                name = f"{slug}_{i:02d}{ext}"
                shutil.copy2(s, dest_dir / name)
                rels.append(f"{family}/{name}")
                copied += 1
        keys[key] = {"bus": bus, "gain_db": gain, "pitch_jitter": jitter, "files": rels}

    preserved: dict = {}
    if INDEX.exists():
        try:
            old = json.loads(INDEX.read_text(encoding="utf-8")).get("keys", {})
            # Голоса живут в отдельном генераторе gen_voice_kodik.py; не терять их.
            preserved = {k: v for k, v in old.items() if str(k).startswith("voice.")}
        except (ValueError, OSError):
            preserved = {}
    keys.update(preserved)

    INDEX.write_text(json.dumps({"version": 1, "keys": keys}, ensure_ascii=False, indent=2),
                     encoding="utf-8")
    print(f"скопировано {copied} файлов, ключей {len(keys)} -> {INDEX.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
