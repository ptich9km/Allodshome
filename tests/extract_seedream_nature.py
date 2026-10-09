#!/usr/bin/env python3
"""Stage 3: cut seedream nature sprites -> assets/map-objects/<name>/,
register in alm_objects.json (from 200)."""
import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
DB = REPO / "assets/map-objects/alm_objects.json"

# folder: (source, canvas_w, canvas_h) — trees tall, bushes/rocks smaller
SOURCES: dict[str, tuple[Path, int, int]] = {
    "tree_oak": (REPO / "import/_stage3_nature/tree_oak.png", 112, 128),
    "tree_oak2": (REPO / "import/_stage3_nature/tree_oak2.png", 112, 128),
    "tree_pine": (REPO / "import/_stage3_nature/tree_pine.png", 96, 128),
    "tree_birch": (REPO / "import/_stage3_nature/tree_birch.png", 96, 128),
    "tree_willow": (REPO / "import/_stage3_nature/tree_willow.png", 112, 112),
    "bush_berry": (REPO / "import/_stage3_nature/bush_berry.png", 64, 64),
    "palm": (REPO / "import/_stage3_nature/palm.png", 96, 128),
    "cactus": (REPO / "import/_stage3_nature/cactus.png", 64, 96),
    "tree_dead": (REPO / "import/_stage3_nature/tree_dead.png", 112, 128),
    "bush_thorn": (REPO / "import/_stage3_nature/bush_thorn.png", 64, 64),
    "rock": (REPO / "import/_stage3_nature/rock.png", 64, 56),
    "rock2": (REPO / "import/_stage3_nature/rock2.png", 64, 48),
}

BG_TOL = 110


def cut_bg(path: Path) -> Image.Image:
    im = Image.open(path).convert("RGB")
    a = np.asarray(im, dtype=np.int16)
    border = np.concatenate([
        a[0, :].reshape(-1, 3), a[-1, :].reshape(-1, 3),
        a[:, 0].reshape(-1, 3), a[:, -1].reshape(-1, 3),
    ])
    bg_color = np.median(border, axis=0)
    dist = np.abs(a - bg_color).sum(axis=2)
    bg = dist <= BG_TOL
    h, w = bg.shape
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
    ys, xs = np.where(alpha > 0)
    if len(ys) == 0:
        raise RuntimeError(f"empty cutout: {path}")
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    return Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")


def kill_halo(rgba: np.ndarray) -> np.ndarray:
    r = rgba[:, :, 0].astype(np.int16)
    g = rgba[:, :, 1].astype(np.int16)
    b = rgba[:, :, 2].astype(np.int16)
    a = rgba[:, :, 3]
    magenta = (g < 90) & ((r - g) > 90) & ((b - g) > 70)
    transparent = a <= 8
    has_trans = np.zeros_like(transparent)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            has_trans |= np.roll(np.roll(transparent, dy, 0), dx, 1)
    out = rgba.copy()
    out[magenta & has_trans & (a > 0), 3] = 0
    return out


def fit_canvas(content: Image.Image, cw: int, ch: int) -> Image.Image:
    scale = min(cw / content.size[0], ch / content.size[1])
    nw, nh = max(1, int(round(content.size[0] * scale))), max(1, int(round(content.size[1] * scale)))
    resized = content.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    canvas.paste(resized, ((cw - nw) // 2, ch - nh), resized)
    arr = np.asarray(canvas).copy()
    return Image.fromarray(kill_halo(arr), "RGBA")


def main() -> None:
    db = json.loads(DB.read_text(encoding="utf-8"))
    existing_folders = {v.get("folder") for v in db.values() if isinstance(v, dict)}
    next_id = max(int(k) for k in db.keys()) + 1

    for folder, (src, cw, ch) in SOURCES.items():
        if not src.exists():
            print(f"FAIL missing {src}")
            sys.exit(1)
        out_dir = REPO / "assets/map-objects" / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        content = cut_bg(src)
        sprite = fit_canvas(content, cw, ch)
        sprite.save(out_dir / "sprites-001.png")
        print(f"cut {folder}: content={content.size} canvas={cw}x{ch}")

        if folder in existing_folders:
            for v in db.values():
                if isinstance(v, dict) and v.get("folder") == folder:
                    v["w"], v["h"] = cw, ch
                    v["cx"], v["cy"] = cw // 2, ch
                    break
            print("  exists, art+size refreshed")
            continue
        db[str(next_id)] = {
            "folder": folder, "index": 0, "w": cw, "h": ch,
            "cx": cw // 2, "cy": ch, "phases": 1, "frames": 1,
            "desc": f"Seedream {folder}",
        }
        print(f"  alm_objects +{next_id}")
        next_id += 1

    DB.write_text(json.dumps(db, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print("done")


if __name__ == "__main__":
    main()
