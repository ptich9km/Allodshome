#!/usr/bin/env python3
"""Stage 1 integration: cut seedream magenta buildings -> 96x96, register in structure_db.

Approved set (player review 10.10). Old Alice folders stay on disk, only
generator pools switch. GEN_VERSION bump lives in map_generator.gd separately.
"""
import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
OUT_DB = REPO / "assets/structures/structure_db.json"

# seedream magenta is noisy (~[250,20,190]), not pure #FF00FF.
# Sample bg from border pixels (median), flood-fill with L1 tolerance.
BG_TOL = 110

# folder -> source png (approved variants only)
SOURCES: dict[str, Path] = {
    # functional (human theme, shared)
    "shop_s1": REPO / "import/_stage1b_functional/shop_v1.png",
    "inn_s1": REPO / "import/_stage1b_functional/inn_v1.png",
    "inn_s2": REPO / "import/_stage1b_functional/inn_v2.png",
    "blacksmith_s1": REPO / "import/_stage1b_functional/blacksmith_v2.png",
    "train_s1": REPO / "import/_stage1b_functional/train_v1.png",
    "druidshop_s1": REPO / "import/_stage1b_functional/alchemy_v2.png",
    "house_s1": REPO / "import/_stage1b_functional/house_v1.png",
    "house_s2": REPO / "import/_stage1b_functional/house_v2.png",
    "barracks_s1": REPO / "import/_stage1b_functional/barracks_v1.png",
    "barracks_s2": REPO / "import/_stage1b_functional/barracks_v2.png",
    # ork
    "ork_house_a1": REPO / "import/_stage1_houses/ork_a_v1.png",
    "ork_house_a2": REPO / "import/_stage1_houses/ork_a_v2.png",
    "ork_house_b1": REPO / "import/_stage1_houses/ork_b_v1.png",
    "ork_house_b2": REPO / "import/_stage1_houses/ork_b_v2.png",
    "ork_decor_1": REPO / "import/_stage1_houses/decor_ork_v1.png",
    "ork_decor_2": REPO / "import/_stage1_houses/decor_ork_v2.png",
    # druid
    "druid_house_a1": REPO / "import/_stage1_houses/druid_a_v1.png",
    "druid_house_a2": REPO / "import/_stage1_houses/druid_a_v2.png",
    "druid_house_b1": REPO / "import/_stage1_houses/druid_b_v1.png",
    "druid_house_b2": REPO / "import/_stage1_houses/druid_b_v2.png",
    "druid_decor_1": REPO / "import/_stage1_houses/decor_druid_v1.png",
    # necro
    "necro_house_a1": REPO / "import/_stage1_houses/necro_a_v1.png",
    "necro_house_a2": REPO / "import/_stage1_houses/necro_a_v2.png",
    "necro_house_b1": REPO / "import/_stage1_houses/necro_b_v1.png",
    "necro_house_b2": REPO / "import/_stage1_houses/necro_b_v2.png",
    "necro_decor_1": REPO / "import/_stage1_houses/decor_necro_v2.png",
}

# functional kinds: folder prefix -> structure_db fields
FUNCTIONAL = {
    "shop_s1": ("Trade Shop (seedream)", True),
    "inn_s1": ("Tavern Inn (seedream)", True),
    "inn_s2": ("Tavern Inn variant (seedream)", True),
    "blacksmith_s1": ("Blacksmith Forge (seedream)", True),
    "train_s1": ("Training Hall (seedream)", True),
    "druidshop_s1": ("Herbalist Apothecary (seedream)", True),
}


def cut_magenta(path: Path) -> Image.Image:
    im = Image.open(path).convert("RGB")
    a = np.asarray(im, dtype=np.int16)
    h, w = a.shape[:2]
    # median color of border pixels = actual bg (seedream magenta is noisy)
    border = np.concatenate([
        a[0, :].reshape(-1, 3), a[-1, :].reshape(-1, 3),
        a[:, 0].reshape(-1, 3), a[:, -1].reshape(-1, 3),
    ])
    bg_color = np.median(border, axis=0)
    dist = np.abs(a - bg_color).sum(axis=2)
    bg = dist <= BG_TOL
    # flood fill from borders (4-connectivity)
    visited = np.zeros_like(bg, dtype=bool)
    q: deque[tuple[int, int]] = deque()
    for x in range(w):
        for y in (0, h - 1):
            if bg[y, x] and not visited[y, x]:
                visited[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if bg[y, x] and not visited[y, x]:
                visited[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and bg[ny, nx] and not visited[ny, nx]:
                visited[ny, nx] = True
                q.append((ny, nx))
    alpha = np.where(visited, 0, 255).astype(np.uint8)
    rgba = np.dstack([np.asarray(im), alpha])
    # bbox of opaque pixels
    ys, xs = np.where(alpha > 0)
    if len(ys) == 0:
        raise RuntimeError(f"empty cutout: {path}")
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    return Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")


def kill_magenta_halo(rgba: np.ndarray) -> np.ndarray:
    """Anti-aliased edge pixels keep magenta tint; suppress it."""
    r = rgba[:, :, 0].astype(np.int16)
    g = rgba[:, :, 1].astype(np.int16)
    b = rgba[:, :, 2].astype(np.int16)
    a = rgba[:, :, 3]
    # magenta-ish: R and B both much stronger than G (salmon banners keep G)
    magenta = (g < 90) & ((r - g) > 90) & ((b - g) > 70)
    # edge pixel: has transparent neighbor within 2px
    transparent = a <= 8
    has_trans = np.zeros_like(transparent)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            has_trans |= np.roll(np.roll(transparent, dy, 0), dx, 1)
    halo = magenta & has_trans & (a > 0)
    out = rgba.copy()
    out[halo, 3] = 0
    return out


def fit_96(content: Image.Image) -> Image.Image:
    """Fit content into 128x128, bottom-aligned, centered horizontally.

    128 px при футпринте 3x3 (96 px): здание чуть крупнее NPC, крыша
    свешивается по бокам как в настоящих RPG. Даунскейл 1024->128 = 8x,
    качество не страдает.
    """
    cw, ch = content.size
    scale = min(128.0 / cw, 128.0 / ch)
    nw, nh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
    resized = content.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    canvas.paste(resized, ((128 - nw) // 2, 128 - nh), resized)
    arr = np.asarray(canvas).copy()
    return Image.fromarray(kill_magenta_halo(arr), "RGBA")


def db_entry(tid: int, folder: str, desc: str, usable: int) -> dict:
    return {
        "id": tid,
        "desc": desc,
        "folder": folder,
        "prefix": "house",
        "tile_width": 3,
        "tile_height": 3,
        "full_height": 3,
        "sel": [0, 96, 0, 96],
        "shadow_y": 0,
        "phases": 1,
        "anim_mask": "",
        "anim_frame": [],
        "anim_time": [],
        "picture": folder,
        "icon_id": tid,
        "indestructible": 1,
        "usable": usable,
        "flat": 0,
        "light_radius": 0,
        "light_pulse": 0,
        "variable_size": 0,
        "tiles_per_frame": 1,
        "whole_image": 1,
    }


def main() -> None:
    db = json.loads(OUT_DB.read_text(encoding="utf-8"))
    existing_folders = {v.get("folder") for v in db.values() if isinstance(v, dict)}
    next_id = max(int(k) for k in db.keys()) + 1

    added, skipped, failed = [], [], []
    for folder, src in SOURCES.items():
        if not src.exists():
            failed.append(f"{folder}: missing {src}")
            continue
        out_dir = REPO / "assets/structures" / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        out_png = out_dir / "house-001.png"
        content = cut_magenta(src)
        fit_96(content).save(out_png)
        print(f"cut {folder}: content={content.size} -> {out_png.name}")

        if folder in existing_folders:
            # refresh art only, keep db entry (id stable)
            for v in db.values():
                if isinstance(v, dict) and v.get("folder") == folder:
                    print(f"  db exists id={v['id']}, art refreshed")
                    break
            skipped.append(folder)
            continue

        desc, usable = FUNCTIONAL.get(folder, (f"{folder} (seedream)", 0))
        db[str(next_id)] = db_entry(next_id, folder, desc, 1 if usable else 0)
        print(f"  db +{next_id} usable={int(bool(usable))}")
        added.append((next_id, folder))
        next_id += 1

    OUT_DB.write_text(json.dumps(db, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"\nadded={len(added)} refreshed={len(skipped)} failed={len(failed)}")
    for f in failed:
        print("FAIL", f)
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
