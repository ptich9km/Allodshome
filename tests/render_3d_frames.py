"""Render a 3D character (.blend / .glb) into the game's 12-frame hero sprites.

Driver side: finds Blender, renders the raw frames through
`tests/render_3d_frames_blender.py` (that part runs inside Blender, which has no
Pillow), then normalizes the frames with Pillow into what the game expects.

The game is 2D: a hero set is 12 PNG frames of 64x64, `dirs: 1` + horizontal
mirror, laid out as idle 1 + move 4 + attack 3 + dying 4, pivot in the feet at
(32, 62). A 3D model gives us any number of views and poses for free while the
game keeps its 2D renderer.

    python tests/render_3d_frames.py --blend C:/Temp/hero.blend --name hero_brute
    python tests/render_3d_frames.py --glb C:/Temp/hero.glb --name hero_brute \
        --out C:/Temp/out --outline

Blender is looked up in --blender, then $BLENDER, then PATH, then the newest
"C:/Program Files/Blender Foundation/Blender */blender.exe".

Normalization: one zoom for all 12 frames, measured on `idle` (a character must
not breathe in size between frames), anchored on the model origin projected to
screen (the pivot does not jitter when an arm swings). Both are why the camera
does not have to be pixel-perfect.

Not done on purpose: 8 directions, palette quantization. The outline is one flag
because a painted 2D sprite has a dark contour that a 3D render does not.
"""
import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT_SIZE = 64            # final frame, same as every other unit set
PIVOT_X = 32             # feet pivot, see _entry.json of existing sets
PIVOT_Y = 62
FIGURE_PX = 54           # height of the figure inside the frame (unit_figure_metrics)
RENDER_SCALE = 4         # render 4x and downsample once: 64 -> 256

BLENDER_STAGE = Path(__file__).resolve().parent / "render_3d_frames_blender.py"


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser()
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--blend", help="source .blend (preferred)")
    src.add_argument("--glb", help="source .glb / .gltf (fallback)")
    ap.add_argument("--name", required=True,
                    help="unit set name, e.g. hero_brute (folder and units_db key)")
    ap.add_argument("--out", default="",
                    help="output folder, default assets/units/hero/<name>")
    ap.add_argument("--figure-px", type=float, default=FIGURE_PX,
                    help="figure height inside the 64px frame (default 54)")
    ap.add_argument("--directions", type=int, default=4, choices=[1, 4],
                    help="1 = side view + mirror, 4 = down/left/up/right "
                         "(default 4: a 3D model gives all four for free)")
    ap.add_argument("--azimuth", type=float, default=-60.0,
                    help="camera yaw in degrees, 0 = straight in front of the model")
    ap.add_argument("--elevation", type=float, default=20.0,
                    help="camera height in degrees above the horizon")
    ap.add_argument("--model-yaw", type=float, default=0.0,
                    help="extra yaw of the model if it does not face -Y")
    ap.add_argument("--outline", action="store_true",
                    help="add a 1px dark outline, closer to the painted sprites")
    ap.add_argument("--static", action="store_true",
                    help="the mesh has no rig/actions (a ComfyUI generation): "
                         "render its single pose in every slot, for a look test "
                         "at game scale only")
    ap.add_argument("--keep-renders", action="store_true",
                    help="keep the 4x frames next to the output (debugging)")
    ap.add_argument("--blender", default="", help="path to the Blender executable")
    return ap.parse_args()


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def find_blender(explicit: str) -> Path:
    if explicit:
        if not Path(explicit).exists():
            raise SystemExit("--blender path does not exist: %s" % explicit)
        return Path(explicit)
    env = os.environ.get("BLENDER", "")
    if env and Path(env).exists():
        return Path(env)
    on_path = shutil.which("blender")
    if on_path:
        return Path(on_path)
    # Newest installed Blender, so a machine with 4.2 and 5.2 picks 5.2.
    found = []
    for pattern in (r"C:\Program Files\Blender Foundation\Blender*\blender.exe",
                    "/Applications/Blender.app/Contents/MacOS/Blender",
                    "/usr/bin/blender"):
        found.extend(glob.glob(pattern))
    if not found:
        raise SystemExit(
            "Blender not found. Pass --blender <path> or set the BLENDER "
            "environment variable.")
    found.sort()
    return Path(found[-1])


def render_raw(args: argparse.Namespace, work: Path) -> dict:
    job = {
        "source": str(Path(args.blend or args.glb).resolve()),
        "blend": bool(args.blend),
        "render_px": OUT_SIZE * RENDER_SCALE,
        "azimuth": args.azimuth,
        "elevation": args.elevation,
        "model_yaw": args.model_yaw,
        "directions": args.directions,
        "static": args.static,
        "work_dir": str(work),
        "manifest": str(work / "manifest.json"),
    }
    job_path = work / "job.json"
    job_path.write_text(json.dumps(job, indent=1), encoding="utf-8")
    blender = find_blender(args.blender)
    cmd = [str(blender), "--background", "--factory-startup",
           "--python", str(BLENDER_STAGE), "--", "--job", str(job_path)]
    print("blender:", blender)
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0 or not Path(job["manifest"]).exists():
        tail = (result.stdout or "")[-4000:] + (result.stderr or "")[-4000:]
        raise SystemExit("Blender render failed:\n" + tail)
    return json.loads(Path(job["manifest"]).read_text(encoding="utf-8"))


MIN_ALPHA = 24   # ignore the antialiasing halo when measuring the figure


def content_bbox(img: Image.Image):
    """Bounding box of the visible figure.

    A plain `getbbox()` counts a 1-2px transparent-ish fringe that the LANCZOS
    downscale leaves around the silhouette; measured on that fringe the figure
    came out ~13% smaller than the game's own metric (47px instead of 54).
    """
    hard = img.getchannel("A").point(lambda v: 255 if v >= MIN_ALPHA else 0)
    return hard.getbbox()


def normalize(manifest: dict, args: argparse.Namespace, out_dir: Path) -> list:
    render_px = int(manifest["render_px"])
    pivots = manifest["pivots"]
    frames = manifest["frames"]

    # One zoom for every frame AND every direction: measured on the tallest
    # idle view, so the character keeps the same size whichever way it faces.
    refs = [f for f in frames if f["action"] == "idle"] or [frames[0]]
    ref_h = 0.0
    for ref in refs:
        small = Image.open(ref["path"]).convert("RGBA") \
            .resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
        box = content_bbox(small)
        if box is not None:
            ref_h = max(ref_h, float(box[3] - box[1]))
    if ref_h < 1.0:
        raise SystemExit("the idle frames are fully transparent - nothing rendered")
    # The 1px outline grows the figure by 2px, so the render itself is aimed at
    # figure_px-2: the painted sets keep their contour INSIDE the 54px quota.
    ratio = (args.figure_px - (2.0 if args.outline else 0.0)) / ref_h \
        * (OUT_SIZE / float(render_px))
    # One correction pass: the fringe threshold is approximate, so measure the
    # resized references once and fix the ratio. Without it the figure lands on
    # 52-53px instead of the 54px the rest of the sets use.
    probe_size = max(1, int(round(render_px * ratio)))
    inner_px = args.figure_px - (2.0 if args.outline else 0.0)
    worst = 1.0
    for ref in refs:
        probe = Image.open(ref["path"]).convert("RGBA").resize(
            (probe_size, probe_size), Image.LANCZOS)
        probe_box = content_bbox(probe)
        if probe_box is not None:
            probe_h = max(1.0, float(probe_box[3] - probe_box[1]))
            worst = max(worst, probe_h / inner_px)
    ratio /= worst

    size = max(1, int(round(render_px * ratio)))
    offsets = {}
    for dir_key, pivot in pivots.items():
        offsets[str(dir_key)] = (
            int(round(PIVOT_X - pivot[0] * ratio)),
            int(round(PIVOT_Y - pivot[1] * ratio)),
        )

    out_paths = []
    for n, item in enumerate(frames, start=1):
        big = Image.open(item["path"]).convert("RGBA").resize(
            (size, size), Image.LANCZOS)
        offset_x, offset_y = offsets[str(item["dir"])]
        # The pivot is the projected world origin, but the feet have depth: seen
        # from 20 degrees above, the near edge of the boot lands a couple of
        # pixels BELOW the origin and gets cut. Lift only as much as needed, so
        # standing frames keep their pivot and a lying body rests on the ground
        # line instead of sinking through it.
        box = content_bbox(big)
        oy = offset_y
        if box is not None:
            bottom = oy + box[3] - 1        # bbox is exclusive, this is the pixel
            if bottom > PIVOT_Y:
                oy -= bottom - PIVOT_Y
        canvas = _composite(big, offset_x, oy)
        if _edge_hit(canvas):
            print("WARN %s dir%d[%d]: content touches the frame edge - the pose "
                  "is wider than the frame. Check that it stays near the pivot, "
                  "or lower --figure-px (%.1f)"
                  % (item["action"], item["dir"], item["index"], args.figure_px))
        if args.outline:
            canvas = add_outline(canvas)
        target = out_dir / ("sprites-%03d.png" % n)
        canvas.save(target)
        out_paths.append(target)
    return out_paths


def _composite(big: Image.Image, left: int, top: int) -> Image.Image:
    """Paste `big` at a possibly negative offset.

    `Image.paste(img, (negative, ...), img)` is NOT the same as compositing: it
    loses the rows/columns that fall outside the canvas and shifts the rest, so
    a figure placed partly above the frame came out 2px shorter. Crop the source
    explicitly instead.
    """
    canvas = Image.new("RGBA", (OUT_SIZE, OUT_SIZE), (0, 0, 0, 0))
    src = (max(0, -left), max(0, -top),
           min(big.width, OUT_SIZE - left), min(big.height, OUT_SIZE - top))
    if src[2] <= src[0] or src[3] <= src[1]:
        return canvas
    canvas.alpha_composite(big.crop(src), (max(0, left), max(0, top)))
    return canvas


def _edge_hit(img: Image.Image) -> bool:
    alpha = img.getchannel("A").point(lambda v: 255 if v >= MIN_ALPHA else 0)
    w, h = alpha.size
    px = alpha.load()
    for x in range(w):
        if px[x, 0] > 0 or px[x, h - 1] > 0:
            return True
    for y in range(h):
        if px[0, y] > 0 or px[w - 1, y] > 0:
            return True
    return False


def add_outline(img: Image.Image) -> Image.Image:
    """1px dark contour under the sprite: the painted sets all have one.

    The ring is hardened to full opacity: a dilated antialiased alpha leaves a
    faint 1px halo that neither reads as a contour at 64px nor measures as part
    of the figure (it fell below the measurement threshold).
    """
    grown = img.getchannel("A").filter(ImageFilter.MaxFilter(3))
    grown = grown.point(lambda v: 255 if v > 8 else 0)
    line = Image.new("RGBA", img.size, (18, 16, 14, 255))
    line.putalpha(grown)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(line)
    out.alpha_composite(img)
    return out


def entry_record(name: str, source: Path, directions: int, static: bool = False) -> dict:
    view = "four views (down/left/up/right)" if directions == 4 \
        else "three-quarter east view + mirror"
    note = "STATIC POSE (no rig): a look test, not an animation" if static else \
        "idle1+move4+attack3+dying4 per view"
    return {
        "desc": "Hero: %s, 3D model %s rendered to %d frames by "
                "tests/render_3d_frames.py, %s, %s"
                % (name, source.name, 12 * directions, view, note),
        "folder": "hero/%s" % name,
        "frames": 12 * directions,
        "prefix": "sprites",
        "dirs": directions,
        # Total idle frames in the set, not per view: UnitAnim derives the
        # per-view count from dirs (4 views -> 1 frame each).
        "idle_phases": directions,
        "move": 4,
        "move_begin": 0,
        "attack": 3,
        "dying": 4,
        "decay": 0,
        "cast": 0,
        "idle": 0,
        "move_f": [],
        "move_t": [],
        "attack_f": [],
        "attack_t": [],
        "die_f": [],
        "dying_t": [],
        "w": OUT_SIZE,
        "h": OUT_SIZE,
        "cx": PIVOT_X,
        "cy": PIVOT_Y,
        "tile": None,
        "projectile": -1,
        "palette": 0,
        "blocks": 4,
        "resist": {"fire": 10, "water": 10, "air": 10, "earth": 10, "astral": 10},
    }


def write_contact_sheet(frames: list, manifest: dict, out_dir: Path) -> Path:
    """Checkerboard preview. Columns = view direction, rows = pose."""
    directions = int(manifest.get("directions", 1))
    if directions == 1:
        cols, rows, cell, order = 4, 3, OUT_SIZE * 3, list(range(len(frames)))
    else:
        # idle 1 + walk 4 + attack 3 + die 4 = 12 rows, one column per view.
        row_of = {}
        for i, item in enumerate(manifest["frames"]):
            row = {"idle": 0, "walk": 1, "attack": 5, "die": 8}[item["action"]] \
                + item["index"]
            row_of[i] = (row, item["dir"])
        cols, rows, cell, order = directions, 12, OUT_SIZE * 2, None
    sheet = Image.new("RGBA", (cell * cols, cell * rows), (0, 0, 0, 255))
    draw = ImageDraw.Draw(sheet)
    for y in range(0, sheet.height, 16):
        for x in range(0, sheet.width, 16):
            shade = (88, 88, 88, 255) if (x // 16 + y // 16) % 2 == 0 \
                else (112, 112, 112, 255)
            draw.rectangle([x, y, x + 15, y + 15], fill=shade)
    for i, path in enumerate(frames):
        img = Image.open(path).convert("RGBA").resize((cell, cell), Image.NEAREST)
        if order is None:
            row, col = row_of[i]
        else:
            row, col = i // cols, i % cols
        sheet.alpha_composite(img, (col * cell, row * cell))
    out = out_dir / "_contact_sheet.png"
    sheet.save(out)
    return out


def main() -> None:
    args = parse_args()
    source = Path(args.blend or args.glb)
    out_dir = Path(args.out) if args.out else \
        repo_root() / "assets" / "units" / "hero" / args.name
    out_dir.mkdir(parents=True, exist_ok=True)
    work = out_dir / "_renders"
    work.mkdir(exist_ok=True)

    manifest = render_raw(args, work)
    frames = normalize(manifest, args, out_dir)
    entry = entry_record(args.name, source, args.directions, args.static)
    (out_dir / "_entry.json").write_text(
        json.dumps(entry, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    sheet = write_contact_sheet(frames, manifest, out_dir)

    print("")
    print("rendered %d frames -> %s" % (len(frames), out_dir))
    print("contact sheet: %s" % sheet)
    print("")
    print("paste into assets/units/units_db.json under key \"hero/%s\":" % args.name)
    print(json.dumps(entry, ensure_ascii=False, indent=1))

    if not args.keep_renders:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
    sys.exit(0)
