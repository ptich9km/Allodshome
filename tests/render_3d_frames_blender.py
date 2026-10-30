"""Blender stage of tests/render_3d_frames.py: raw 4x frames + manifest.

Runs INSIDE Blender (no Pillow there), called by the driver:

    blender --background --factory-startup --python tests/render_3d_frames_blender.py \
        -- --job <work>/job.json

Two modes come from the job:

  * **actions** (a rigged model): one file, four actions named idle/walk/attack/
    die. We sample frames out of the actions and orbit the camera.
  * **poses** (no rig, e.g. 12 separate ComfyUI generations): every slot of the
    set points at its own mesh file. Each file is imported into a clean scene,
    fitted by its own silhouette and rendered from every requested direction.

No image processing here: normalization, outlining and contact sheets belong to
the driver, which has Pillow.
"""
import argparse
import json
import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ACTIONS = ["idle", "walk", "attack", "die"]
SAMPLES = {"idle": 1, "walk": 4, "attack": 3, "die": 4}
FIT_MARGIN = 1.12   # camera margin around the union of the rendered poses
# Camera yaw per FILE direction (0 = in front of the model, it faces -Y).
# The 4-dir order is UnitAnim.FILE_DIR_4: 0=down, 1=left, 2=up, 3=right.
DIR_AZIMUTH = {0: 0.0, 1: 60.0, 2: 180.0, 3: -60.0}

FIT_SIZE = 2.2      # orthographic view size in metres, filled by add_camera
FIT_TARGET = Vector((0.0, 0.0, 1.0))


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--job", required=True)
    return ap.parse_args(argv)


def action_key(action) -> str:
    """idle/walk/attack/die from any reasonable action name.

    Real files rarely carry a bare name: glTF exports `Armature|Idle`, Mixamo
    gives `Armature|mixamo.com|walk`, Blender appends `.001`. Tokenising on
    separators is much less brittle than prefix matching, and a name that is
    just `mixamo.com` matches nothing — which is honest.
    """
    tokens = re.split(r"[^a-z0-9]+", action.name.lower())
    for want in ACTIONS:
        if want in tokens:
            return want
    key = action.name.split("|")[-1].strip().lower()
    for want in ACTIONS:
        if key.startswith(want + ".") or key.startswith(want + "_"):
            return want
    return key


def open_blend(path: Path) -> None:
    bpy.ops.wm.open_mainfile(filepath=str(path))


def import_mesh(path: Path) -> None:
    """Empty scene + one mesh file. Format by suffix: generators disagree."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    suffix = path.suffix.lower()
    if suffix in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=str(path))
    elif suffix == ".obj":
        bpy.ops.wm.obj_import(filepath=str(path))
    elif suffix == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(path))
    else:
        raise SystemExit(
            "unsupported mesh format: %s (expected .glb/.gltf/.obj/.fbx; "
            "for .blend use --blend)" % suffix)


def strip_cameras_and_lights() -> None:
    for obj in list(bpy.data.objects):
        if obj.type in {"CAMERA", "LIGHT"}:
            bpy.data.objects.remove(obj, do_unlink=True)


def apply_model_yaw(yaw_deg: float) -> None:
    yaw = math.radians(yaw_deg)
    if not yaw:
        return
    for obj in bpy.data.objects:
        if obj.parent is None and obj.type in {"MESH", "ARMATURE", "EMPTY"}:
            obj.rotation_mode = "XYZ"
            obj.rotation_euler.z += yaw


def find_actions() -> dict:
    found = {}
    for action in bpy.data.actions:
        key = action_key(action)
        if key in ACTIONS:
            found.setdefault(key, action)
    missing = [a for a in ACTIONS if a not in found]
    if missing:
        names = ", ".join(a.name for a in bpy.data.actions) or "none"
        raise SystemExit(
            "missing actions: %s (found in file: %s). Actions must be named "
            "exactly idle/walk/attack/die. If the .blend has them, they were "
            "probably dropped on save: enable Fake User (the shield icon) on "
            "each Action or keep them as NLA strips. A mesh with no rig at all "
            "cannot animate - use --static for a look test, or --poses with "
            "one mesh per frame." % (", ".join(missing), names))
    return found


def animation_host():
    for kind in ("ARMATURE", "MESH"):
        for obj in bpy.data.objects:
            if obj.type == kind:
                return obj
    raise SystemExit("no armature or mesh found in the file")


def assign_action(host, action) -> None:
    if host.animation_data is None:
        host.animation_data_create()
    host.animation_data.action = action
    # Blender 4.4+ slotted actions: several slots can live in one action, and
    # the wrong slot silently renders a frozen pose.
    slots = getattr(action, "slots", None)
    if hasattr(host.animation_data, "action_slot") and slots:
        if len(slots) > 0:
            host.animation_data.action_slot = slots[0]


def scene_bounds() -> tuple:
    """World-space bounds of the evaluated meshes in the current pose."""
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    lo = Vector((1.0e9, 1.0e9, 1.0e9))
    hi = Vector((-1.0e9, -1.0e9, -1.0e9))
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        ev = obj.evaluated_get(depsgraph)
        mesh = ev.to_mesh()
        for vertex in mesh.vertices:
            world = ev.matrix_world @ vertex.co
            lo.x = min(lo.x, world.x)
            lo.y = min(lo.y, world.y)
            lo.z = min(lo.z, world.z)
            hi.x = max(hi.x, world.x)
            hi.y = max(hi.y, world.y)
            hi.z = max(hi.z, world.z)
        ev.to_mesh_clear()
    if lo.x > hi.x:
        return Vector((-1.0, -1.0, 0.0)), Vector((1.0, 1.0, 1.8))
    return lo, hi


def pose_bounds(host, found: dict, frames: list) -> tuple:
    """Bounds over every pose we render, in the FIRST direction only.

    `obj.bound_box` is not reliable here: it is the REST bbox (and may be stale
    right after joining/importing), while a death pose can be three times wider
    than the rest pose. The actions must be applied while measuring: a .blend
    saved in a death pose otherwise reports bounds of that pose only.
    """
    scene = bpy.context.scene
    lo = Vector((1.0e9, 1.0e9, 1.0e9))
    hi = Vector((-1.0e9, -1.0e9, -1.0e9))
    current_action = None
    for key, _dir, _index, frame in frames:
        if found and key != current_action:
            assign_action(host, found[key])
            current_action = key
        scene.frame_set(frame)
        one_lo, one_hi = scene_bounds()
        lo.x = min(lo.x, one_lo.x)
        lo.y = min(lo.y, one_lo.y)
        lo.z = min(lo.z, one_lo.z)
        hi.x = max(hi.x, one_hi.x)
        hi.y = max(hi.y, one_hi.y)
        hi.z = max(hi.z, one_hi.z)
    return lo, hi


def pick_engine(scene) -> None:
    # EEVEE Next (4.2) -> EEVEE (5.x, renamed) -> Workbench (flat fallback).
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
        try:
            scene.render.engine = engine
            return
        except TypeError:
            continue
    raise SystemExit("no usable render engine found")


def setup_scene(job: dict) -> None:
    scene = bpy.context.scene
    render_px = int(job["render_px"])
    # Standard view transform: Filmic/AgX washes out a 64px sprite, and the
    # game draws sprites without a tone mapper.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    scene.render.resolution_x = render_px
    scene.render.resolution_y = render_px
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.fps = 24
    pick_engine(scene)

    # Key light from the screen upper left: the painted sprites are lit that way.
    key_data = bpy.data.lights.new("Key", type="SUN")
    key_data.energy = 3.0
    key_data.angle = math.radians(12.0)
    key = bpy.data.objects.new("Key", key_data)
    key.rotation_euler = Vector((0.82, -0.22, -1.0)).normalized() \
        .to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(key)
    # Weak fill so the shadow side is not a black hole.
    fill_data = bpy.data.lights.new("Fill", type="SUN")
    fill_data.energy = 1.2
    fill = bpy.data.objects.new("Fill", fill_data)
    fill.rotation_euler = Vector((-0.7, 0.6, -0.6)).normalized() \
        .to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(fill)

    if scene.world is None:
        scene.world = bpy.data.worlds.new("UnitWorld")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs[0].default_value = (0.32, 0.34, 0.36, 1.0)
        bg.inputs[1].default_value = 0.55


def add_camera(lo: Vector, hi: Vector) -> object:
    global FIT_SIZE, FIT_TARGET
    scene = bpy.context.scene
    FIT_SIZE = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, 0.5) * FIT_MARGIN
    FIT_TARGET = (lo + hi) / 2.0
    cam_data = bpy.data.cameras.new("UnitCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = FIT_SIZE
    cam = bpy.data.objects.new("UnitCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def aim_camera(cam, azimuth_deg: float, elevation_deg: float) -> None:
    """Point the camera at the model from a yaw/elevation around its centre."""
    size = FIT_SIZE
    target = FIT_TARGET
    az = math.radians(azimuth_deg)
    el = math.radians(elevation_deg)
    dist = max(6.0, size * 4.0)
    cam.location = target + Vector((
        math.sin(az) * math.cos(el),
        -math.cos(az) * math.cos(el),
        math.sin(el),
    )) * dist
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    # The camera was just moved; until the depsgraph is rebuilt its matrix_world
    # is stale and world_to_camera_view would answer for the old pose.
    bpy.context.view_layer.update()


def sample_frames(action) -> list:
    """Frames to render per action, in game order.

    walk excludes its last frame: in a cycle the first and the last pose are
    equal, so it would be sampled twice. attack and die include the last frame:
    for them the finish is part of the action.
    """
    start = int(round(action.frame_range[0]))
    end = int(round(action.frame_range[1]))
    key = action_key(action)
    if end <= start:
        return [start]
    count = SAMPLES[key]
    if count == 1:
        return [int(round((start + end) / 2.0))]
    if key == "walk":
        step = (end - start) / float(count)
        return [int(round(start + step * i)) for i in range(count)]
    step = (end - start) / float(count - 1)
    return [int(round(start + step * i)) for i in range(count)]


def pivot_px(render_px: int) -> list:
    from bpy_extras.object_utils import world_to_camera_view
    scene = bpy.context.scene
    co = world_to_camera_view(scene, scene.camera, Vector((0.0, 0.0, 0.0)))
    pivot = [co.x * render_px, (1.0 - co.y) * render_px]
    if not (0.0 <= pivot[0] <= render_px and 0.0 <= pivot[1] <= render_px):
        raise SystemExit(
            "the model origin (feet pivot) is outside the camera frame: "
            "%.0f, %.0f of %d. Move the model to the world origin or its feet "
            "to Z=0 and rerun." % (pivot[0], pivot[1], render_px))
    return pivot


def build_schedule(found: dict, directions: int) -> list:
    """Frames in the order the game reads them: block, then direction, then phase.

    UnitAnim computes `frame = block_offset + file_dir * phases + phase`, so the
    driver must write the PNGs exactly in this order.
    """
    schedule = []
    for key in ACTIONS:
        for file_dir in range(directions):
            if found:
                sampled = sample_frames(found[key])
            else:
                # Static mesh (a ComfyUI generation has no rig yet): the same
                # pose fills every slot, only the camera turns.
                sampled = [1] * SAMPLES[key]
            for index, frame in enumerate(sampled):
                schedule.append((key, file_dir, index, frame))
    return schedule


def azimuth_for(job: dict, file_dir: int) -> float:
    return float(job["azimuth"]) if int(job.get("directions", 1)) == 1 \
        else DIR_AZIMUTH[file_dir % 4]


def render_actions(job: dict, work: Path) -> tuple:
    """Rigged model: one file, four actions. Returns frames + pivots."""
    directions = int(job.get("directions", 1))
    elevation = float(job.get("elevation", 20.0))
    source = Path(job["source"])
    if job.get("blend"):
        open_blend(source)
    else:
        import_mesh(source)
    strip_cameras_and_lights()
    apply_model_yaw(float(job.get("model_yaw", 0.0)))
    static = bool(job.get("static", False))
    found = {} if static else find_actions()
    host = animation_host()
    schedule = build_schedule(found, directions)

    setup_scene(job)
    lo, hi = pose_bounds(host, found, schedule)
    cam = add_camera(lo, hi)

    scene = bpy.context.scene
    frames = []
    pivots = {}
    current_action = None
    current_dir = -1
    for key, file_dir, index, frame in schedule:
        if file_dir != current_dir:
            aim_camera(cam, azimuth_for(job, file_dir), elevation)
            pivots[str(file_dir)] = pivot_px(int(job["render_px"]))
            current_dir = file_dir
        if key != current_action and found:
            assign_action(host, found[key])
            current_action = key
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        path = work / ("%s_d%d_%02d_%04d.png" % (key, file_dir, index, frame))
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        frames.append({
            "action": key, "dir": file_dir, "index": index,
            "frame": frame, "path": str(path),
        })
    return frames, pivots


def render_poses(job: dict, work: Path) -> tuple:
    """Rig-less workflow: one mesh per frame, fitted by its own silhouette."""
    directions = int(job.get("directions", 1))
    elevation = float(job.get("elevation", 20.0))
    poses = job["poses"]            # [{action, index, file}, ...]
    frames = []
    for item in poses:
        source = Path(item["file"])
        open_mesh = source
        if source.suffix.lower() == ".blend":
            open_blend(open_mesh)
            bpy.context.scene.frame_set(1)
        else:
            import_mesh(open_mesh)
        strip_cameras_and_lights()
        apply_model_yaw(float(job.get("model_yaw", 0.0)))
        setup_scene(job)
        lo, hi = scene_bounds()
        cam = add_camera(lo, hi)
        for file_dir in range(directions):
            aim_camera(cam, azimuth_for(job, file_dir), elevation)
            path = work / ("%s_d%d_%02d_%s.png"
                           % (item["action"], file_dir, item["index"],
                              source.stem))
            bpy.context.scene.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
            frames.append({
                "action": item["action"], "dir": file_dir,
                "index": item["index"], "frame": 1, "path": str(path),
            })
    # Engine order: block, then direction, then phase.
    order = {k: i for i, k in enumerate(ACTIONS)}
    frames.sort(key=lambda f: (order[f["action"]], f["dir"], f["index"]))
    return frames, {}


def main() -> None:
    args = parse_args()
    job = json.loads(Path(args.job).read_text(encoding="utf-8-sig"))
    work = Path(job["work_dir"])
    work.mkdir(parents=True, exist_ok=True)
    mode = str(job.get("mode", "actions"))

    if mode == "poses":
        frames, pivots = render_poses(job, work)
    else:
        frames, pivots = render_actions(job, work)

    manifest = {
        "mode": mode,
        "render_px": int(job["render_px"]),
        "directions": int(job.get("directions", 1)),
        "pivots": pivots,
        "frames": frames,
    }
    Path(job["manifest"]).write_text(
        json.dumps(manifest, indent=1), encoding="utf-8")
    print("RENDERED %d frames (%s), %d direction(s)"
          % (len(frames), mode, manifest["directions"]))


main()
