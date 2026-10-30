"""Blender stage of tests/render_3d_frames.py: raw 4x frames + manifest.

Runs INSIDE Blender (no Pillow there), called by the driver:

    blender --background --factory-startup --python tests/render_3d_frames_blender.py \
        -- --job <work>/job.json

Reads the job, loads the model, finds the four actions (idle/walk/attack/die),
puts an orthographic camera and a key light from the upper left, renders the
sampled frames of every requested direction on a transparent background and
writes a manifest with the screen position of the model origin (feet pivot) per
direction. No image processing here: normalization, outlining and contact
sheets belong to the driver, which has Pillow.

Directions. The game wants `directions` file views: 1 (side view + mirror) or 4
(front/down, left, back/up, right). A 3D model gives them for free — the artist
does not draw four versions, we just move the camera. File direction order must
match `UnitAnim.FILE_DIR_4`: 0=down, 1=left, 2=up, 3=right.
"""
import argparse
import json
import math
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


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--job", required=True)
    return ap.parse_args(argv)


def action_key(action) -> str:
    key = action.name.split("|")[-1].strip().lower()
    for want in ACTIONS:
        if key == want or key.startswith(want + ".") or key.startswith(want + "_"):
            return want
    return key


def load_model(job: dict) -> None:
    source = Path(job["source"])
    if job.get("blend"):
        bpy.ops.wm.open_mainfile(filepath=str(source))
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(source))
    # A camera or light that came with the file would win over ours.
    for obj in list(bpy.data.objects):
        if obj.type in {"CAMERA", "LIGHT"}:
            bpy.data.objects.remove(obj, do_unlink=True)
    yaw = math.radians(float(job.get("model_yaw", 0.0)))
    if yaw:
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
            "each Action or keep them as NLA strips."
            % (", ".join(missing), names))
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


def pose_bounds(host, found: dict, frames: list) -> tuple:
    """World-space bounds over every pose we are going to render.

    `obj.bound_box` is not reliable here: it is the REST bbox (and may be stale
    right after joining/importing), while a death pose can be three times wider
    than the rest pose. Measuring the evaluated meshes keeps every frame inside
    the camera instead of silently clipping arms and legs. The actions must be
    applied while measuring: a .blend saved in a death pose otherwise reports
    bounds of that pose only, and every view is fitted to the wrong box.
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
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
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


FIT_SIZE = 2.2      # orthographic view size in metres, filled by add_camera
FIT_TARGET = Vector((0.0, 0.0, 1.0))


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


def main() -> None:
    args = parse_args()
    job = json.loads(Path(args.job).read_text(encoding="utf-8"))
    work = Path(job["work_dir"])
    work.mkdir(parents=True, exist_ok=True)
    render_px = int(job["render_px"])
    directions = int(job.get("directions", 1))
    elevation = float(job.get("elevation", 20.0))

    load_model(job)
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
            azimuth = float(job["azimuth"]) if directions == 1 \
                else DIR_AZIMUTH[file_dir % 4]
            aim_camera(cam, azimuth, elevation)
            pivots[str(file_dir)] = pivot_px(render_px)
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

    manifest = {
        "render_px": render_px,
        "directions": directions,
        "pivots": pivots,
        "frames": frames,
    }
    Path(job["manifest"]).write_text(
        json.dumps(manifest, indent=1), encoding="utf-8")
    print("RENDERED %d frames, %d direction(s)" % (len(frames), directions))


main()
