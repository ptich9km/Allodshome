"""Blender stage of tests/render_3d_frames.py: render raw 4x frames + manifest.

Runs INSIDE Blender (no Pillow there), called by the driver:

    blender --background --factory-startup --python tests/render_3d_frames_blender.py \
        -- --job <work>/job.json

Reads the job, loads the model, finds the four actions (idle/walk/attack/die),
puts an orthographic 3/4 camera and a key light from the upper left, renders the
sampled frames on a transparent background and writes a manifest with the
screen position of the model origin (the feet pivot). No image processing here:
normalization, outlining and contact sheets belong to the driver, which has
Pillow.
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


def pose_bounds(host, found: dict, schedule: list) -> tuple:
    """World-space bounds over every pose we are going to render.

    `obj.bound_box` is not reliable here: it is the REST bbox (and may be stale
    right after joining/importing), while a death pose can be three times wider
    than the rest pose. Measuring the evaluated meshes keeps every frame inside
    the camera instead of silently clipping arms and legs.
    """
    scene = bpy.context.scene
    lo = Vector((1.0e9, 1.0e9, 1.0e9))
    hi = Vector((-1.0e9, -1.0e9, -1.0e9))
    for key, frame in schedule:
        assign_action(host, found[key])
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


def setup_render(job: dict, lo: Vector, hi: Vector) -> None:
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

    size = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, 0.5) * FIT_MARGIN
    target = (lo + hi) / 2.0
    az = math.radians(float(job["azimuth"]))
    el = math.radians(float(job["elevation"]))
    dist = max(6.0, size * 4.0)
    cam_data = bpy.data.cameras.new("UnitCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = size
    cam = bpy.data.objects.new("UnitCam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = target + Vector((
        math.sin(az) * math.cos(el),
        -math.cos(az) * math.cos(el),
        math.sin(el),
    )) * dist
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam

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
    # The camera was just created and moved; until the depsgraph is rebuilt its
    # matrix_world is still identity, and world_to_camera_view would answer
    # "the origin is in the middle of the frame" instead of the feet.
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


def main() -> None:
    args = parse_args()
    job = json.loads(Path(args.job).read_text(encoding="utf-8"))
    work = Path(job["work_dir"])
    work.mkdir(parents=True, exist_ok=True)
    render_px = int(job["render_px"])

    load_model(job)
    found = find_actions()
    host = animation_host()
    schedule = [(key, frame) for key in ACTIONS
                for frame in sample_frames(found[key])]
    lo, hi = pose_bounds(host, found, schedule)
    setup_render(job, lo, hi)
    pivot = pivot_px(render_px)

    scene = bpy.context.scene
    frames = []
    for key in ACTIONS:
        assign_action(host, found[key])
        for index, frame in enumerate(sample_frames(found[key])):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            path = work / ("%s_%02d_%04d.png" % (key, index, frame))
            scene.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
            frames.append({
                "action": key, "index": index, "frame": frame, "path": str(path),
            })

    manifest = {"render_px": render_px, "pivot": pivot, "frames": frames}
    Path(job["manifest"]).write_text(
        json.dumps(manifest, indent=1), encoding="utf-8")
    print("RENDERED %d frames, pivot=(%.1f, %.1f) px of %d"
          % (len(frames), pivot[0], pivot[1], render_px))


main()
