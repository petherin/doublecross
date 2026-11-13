#!/usr/bin/env python3
"""Builds, poses and renders the two spy agents as isometric sprite sheets.

Everything is made from scratch in code with Blender's Python API (bpy):
the model, materials, lighting, camera, poses and the final sprite sheets.
Run it with a Python that has the `bpy` module (Blender 4.2 as a module):

    python3.11 -m venv .blendenv
    .blendenv/bin/pip install bpy==4.2.0 pillow
    .blendenv/bin/python tools/blender/build_agents.py            # full render
    .blendenv/bin/python tools/blender/build_agents.py --preview  # quick test

Output (in assets/sprites/):
    agent_crimson.png, agent_cobalt.png   sprite sheets
    agents.json                           frame size, foot anchor, animations

Sheet layout: one row per direction (8 rows, direction d faces the game's
floor angle d * 45 degrees), animations laid out left to right in the order
listed in ANIMS. The camera matches the game's 2:1 isometric projection.
"""
import json
import math
import os
import shutil
import sys
import tempfile

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agent_model  # noqa: E402  (the detailed, skeleton-posed model)
from bpy_extras.object_utils import world_to_camera_view

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "sprites")
PREVIEW = "--preview" in sys.argv

FRAME = 96 if PREVIEW else 192          # pixels per frame (square)
SAMPLES = 8 if PREVIEW else 32
DIRECTIONS = 8

# Animation name -> number of frames.
ANIMS = [("idle", 2), ("walk", 8), ("search", 4), ("swing", 4), ("hurt", 1), ("down", 1)]

AGENTS = {
    "crimson": {"coat": (0.5, 0.025, 0.04), "band": (1.0, 0.18, 0.2), "hat": (0.05, 0.02, 0.02)},
    "cobalt": {"coat": (0.03, 0.14, 0.5), "band": (0.2, 0.55, 1.0), "hat": (0.015, 0.03, 0.08)},
}


# ------------------------------------------------------------------ scene setup

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    try:
        scene.cycles.denoiser = "OPENIMAGEDENOISE"
    except TypeError:
        pass
    scene.render.film_transparent = True
    scene.render.resolution_x = FRAME
    scene.render.resolution_y = FRAME
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    # Ink outlines, like the rest of the game's art.
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = "ABSOLUTE"
    scene.render.line_thickness = 1.4 if PREVIEW else 2.2
    vl = scene.view_layers[0]
    vl.use_freestyle = True
    ls = vl.freestyle_settings.linesets.new("ink") if not vl.freestyle_settings.linesets else vl.freestyle_settings.linesets[0]
    ls.select_by_visibility = True
    ls.select_by_edge_types = True
    ls.select_silhouette = True
    ls.select_external_contour = True
    ls.select_border = False
    ls.select_crease = False
    if ls.linestyle is None:
        ls.linestyle = bpy.data.linestyles.new("ink")
    ls.linestyle.color = (0.03, 0.03, 0.05)
    ls.linestyle.thickness = 1.0
    # Dim cool ambient light.
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.32, 0.36, 0.45, 1.0)
    bg.inputs[1].default_value = 0.35
    return scene


def _aimed(obj, at=(0, 0, 0.9)):
    aim = bpy.data.objects.new(obj.name + "_aim", None)
    bpy.context.collection.objects.link(aim)
    aim.location = at
    t = obj.constraints.new("TRACK_TO")
    t.target = aim
    t.track_axis = "TRACK_NEGATIVE_Z"
    t.up_axis = "UP_Y"


def add_lights():
    # Key light from the upper left of the screen, like the game's lamps.
    bpy.ops.object.light_add(type="SUN", location=(-2.0, -2.5, 5.0))
    key = bpy.context.object
    key.data.energy = 3.8
    key.data.color = (1.0, 0.93, 0.82)
    key.data.angle = math.radians(12)
    _aimed(key)
    # Soft fill from the camera side.
    bpy.ops.object.light_add(type="SUN", location=(4.0, -4.0, 2.0))
    fill = bpy.context.object
    fill.data.energy = 1.7
    fill.data.color = (0.85, 0.9, 1.0)
    _aimed(fill)
    # Cool rim light from behind.
    bpy.ops.object.light_add(type="SUN", location=(-4.0, 4.0, 3.0))
    rim = bpy.context.object
    rim.data.energy = 2.4
    rim.data.color = (0.6, 0.75, 1.0)
    _aimed(rim)


def add_camera():
    """Orthographic camera at the game's isometric angle.

    The game draws floor x towards the screen's lower right and floor y
    towards the lower left, squashed 2:1 vertically. The game's floor axes
    are mirror-image to Blender's, so game (x, y) is Blender (x, -y): the
    camera sits 30 degrees above the horizon on the (+1, -1) diagonal, and
    a game facing angle a is a Blender rotation of -a.
    """
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.6
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    elev = math.radians(30)
    dist = 10.0
    target = Vector((0, 0, 0.92))
    direction = Vector((math.cos(elev) / math.sqrt(2), -math.cos(elev) / math.sqrt(2), math.sin(elev)))
    cam.location = target + direction * dist
    aim = bpy.data.objects.new("aim", None)
    bpy.context.collection.objects.link(aim)
    aim.location = target
    track = cam.constraints.new("TRACK_TO")
    track.target = aim
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    bpy.context.scene.camera = cam
    bpy.context.view_layer.update()
    return cam


# ------------------------------------------------------------------ materials

def mat(name, color, rough=0.6, metal=0.0, sheen=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if sheen and "Sheen Weight" in p.inputs:
        p.inputs["Sheen Weight"].default_value = sheen
    return m


# ------------------------------------------------------------------ model

def smooth(obj, bevel=0.0, subdiv=0):
    for poly in obj.data.polygons:
        poly.use_smooth = True
    if bevel:
        b = obj.modifiers.new("bevel", "BEVEL")
        b.width = bevel
        b.segments = 2
    if subdiv:
        s = obj.modifiers.new("subd", "SUBSURF")
        s.levels = subdiv
        s.render_levels = subdiv


def parent(child, par):
    child.parent = par
    child.matrix_parent_inverse.identity()


def empty(name, loc, par=None):
    e = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(e)
    e.location = loc
    if par:
        parent(e, par)
    return e


def cyl(name, r1, r2, depth, loc, material, verts=20, par=None, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth, location=(0, 0, 0))
    o = bpy.context.object
    o.name = name
    o.data.materials.append(material)
    o.rotation_euler = rot
    if par:
        parent(o, par)
    o.location = loc
    return o


def sphere(name, r, loc, material, par=None, scale=(1, 1, 1), segs=24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=segs // 2, radius=r, location=(0, 0, 0))
    o = bpy.context.object
    o.name = name
    o.data.materials.append(material)
    o.scale = scale
    smooth(o)
    if par:
        parent(o, par)
    o.location = loc
    return o


def box(name, size, loc, material, par=None, bevel=0.01):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    o = bpy.context.object
    o.name = name
    o.scale = size
    o.data.materials.append(material)
    bpy.ops.object.transform_apply(scale=True)
    smooth(o, bevel=bevel)
    if par:
        parent(o, par)
    o.location = loc
    return o


def build_agent(colors):
    """Returns a dict of the pivots used for posing. The agent faces +X."""
    coat_m = mat("coat", colors["coat"], 0.7)
    coat_dark = mat("coat_dark", tuple(c * 0.55 for c in colors["coat"]), 0.8)
    band_m = mat("band", colors["band"], 0.5)
    hat_m = mat("hat", colors["hat"], 0.5)
    skin = mat("skin", (0.86, 0.62, 0.45), 0.55)
    trousers = mat("trousers", (0.07, 0.075, 0.09), 0.8)
    shoes = mat("shoes", (0.02, 0.02, 0.025), 0.25)
    glasses = mat("glasses", (0.01, 0.01, 0.015), 0.08, metal=0.6)
    gold = mat("gold", (1.0, 0.75, 0.2), 0.3, metal=1.0)
    wood = mat("wood", (0.42, 0.26, 0.15), 0.6)
    leather = mat("leather", (0.08, 0.06, 0.05), 0.5)

    root = empty("root", (0, 0, 0))
    body = empty("body", (0, 0, 0), root)          # bobs and leans
    hips = empty("hips", (0, 0, 0.88), body)

    # Legs (pivot at the hip) and shoes.
    legs = {}
    for side, y in (("l", 0.1), ("r", -0.1)):
        pivot = empty("leg_" + side, (0, y, 0.88), body)
        leg = cyl("legmesh_" + side, 0.075, 0.065, 0.82, (0, 0, -0.41), trousers, 16, pivot)
        smooth(leg)
        box("shoe_" + side, (0.27, 0.12, 0.08), (0.06, 0, -0.84), shoes, pivot, 0.03)
        legs[side] = pivot

    # Trench coat: flared hem, belt, buckle, collar, buttons.
    coat = cyl("coat", 0.36, 0.22, 1.0, (0, 0, 0.95), coat_m, 24, body)
    coat.scale = (0.78, 1.0, 1.0)
    smooth(coat, bevel=0.02)
    cyl("hem", 0.365, 0.36, 0.06, (0, 0, 0.48), coat_dark, 24, body).scale = (0.79, 1.01, 1)
    cyl("belt", 0.296, 0.29, 0.07, (0, 0, 0.96), coat_dark, 24, body).scale = (0.8, 1.02, 1)
    box("buckle", (0.03, 0.08, 0.06), (0.24, 0, 0.96), gold, body, 0.005)
    # Broad shoulders.
    for y in (0.22, -0.22):
        sphere("shoulder", 0.11, (0, y, 1.36), coat_m, body, (1.0, 1.0, 0.75))
    for z in (1.16, 0.78):
        sphere("button", 0.022, (0.2 if z > 1 else 0.24, 0.06, z), coat_dark, body)
    collar = cyl("collar", 0.2, 0.13, 0.14, (0, 0, 1.48), coat_m, 20, body)
    collar.scale = (0.85, 1.0, 1.0)
    smooth(collar)
    box("lapel_l", (0.02, 0.07, 0.24), (0.17, 0.06, 1.32), coat_dark, body, 0.005).rotation_euler = (0.35, 0.1, 0)
    box("lapel_r", (0.02, 0.07, 0.24), (0.17, -0.06, 1.32), coat_dark, body, 0.005).rotation_euler = (-0.35, 0.1, 0)

    # Arms (pivot at the shoulder), gloved/skin hands. The right hand can hold a cosh.
    arms = {}
    for side, y in (("l", 0.27), ("r", -0.27)):
        pivot = empty("arm_" + side, (0, y, 1.38), body)
        sleeve = cyl("sleeve_" + side, 0.07, 0.06, 0.6, (0, 0, -0.3), coat_m, 16, pivot)
        smooth(sleeve)
        cyl("cuff_" + side, 0.066, 0.066, 0.05, (0, 0, -0.58), coat_dark, 16, pivot)
        sphere("hand_" + side, 0.065, (0, 0, -0.66), skin, pivot)
        arms[side] = pivot
    cosh_pivot = empty("cosh", (0, 0, -0.66), arms["r"])
    cosh = cyl("cosh_handle", 0.022, 0.022, 0.32, (0.14, 0, 0.0), wood, 12, cosh_pivot, rot=(0, math.radians(90), 0))
    cosh_head = sphere("cosh_head", 0.055, (0.32, 0, 0), leather, cosh_pivot, (1.5, 1, 1))

    # Head: face, big spy nose, sunglasses, ears, sly mouth.
    head = empty("head", (0, 0, 1.6), body)
    sphere("face", 0.168, (0, 0, 0.04), skin, head, (1.0, 0.95, 1.05))
    nose = cyl("nose", 0.05, 0.012, 0.16, (0.17, 0, 0.02), skin, 16, head, rot=(0, math.radians(80), 0))
    smooth(nose)
    box("glasses", (0.05, 0.25, 0.06), (0.13, 0, 0.08), glasses, head, 0.015)
    box("glasses_arm_l", (0.16, 0.01, 0.015), (0.04, 0.13, 0.08), glasses, head, 0)
    box("glasses_arm_r", (0.16, 0.01, 0.015), (0.04, -0.13, 0.08), glasses, head, 0)
    sphere("ear_l", 0.04, (0, 0.15, 0.04), skin, head)
    sphere("ear_r", 0.04, (0, -0.15, 0.04), skin, head)
    box("mouth", (0.02, 0.07, 0.012), (0.145, -0.02, -0.06), mat("lip", (0.4, 0.15, 0.1), 0.6), head, 0.004).rotation_euler = (0.25, 0, 0)

    # Fedora: wide brim, pinched crown, coloured band.
    brim = cyl("brim", 0.27, 0.27, 0.025, (0, 0, 0.19), hat_m, 32, head)
    smooth(brim, bevel=0.008)
    crown = cyl("crown", 0.165, 0.13, 0.17, (0, 0, 0.28), hat_m, 32, head)
    crown.scale = (1.1, 0.95, 1.0)
    smooth(crown, bevel=0.01)
    band = cyl("hatband", 0.168, 0.16, 0.05, (0, 0, 0.225), band_m, 32, head)
    band.scale = (1.1, 0.95, 1.0)

    return {"root": root, "body": body, "legs": legs, "arms": arms, "head": head, "cosh": cosh_pivot}


# ------------------------------------------------------------------ poses

def set_visible(obj, on):
    obj.hide_render = not on
    for c in obj.children_recursive:
        c.hide_render = not on


def pose(rig, anim, i, n):
    """Poses the rig for frame i of n of animation `anim`."""
    body, legs, arms, head = rig["body"], rig["legs"], rig["arms"], rig["head"]
    body.location = (0, 0, 0)
    body.rotation_euler = (0, 0, 0)
    head.rotation_euler = (0, 0, 0)
    for p in list(legs.values()) + list(arms.values()):
        p.rotation_euler = (0, 0, 0)
    arms["l"].rotation_euler = (math.radians(-6), 0, 0)
    arms["r"].rotation_euler = (math.radians(6), 0, 0)
    set_visible(rig["cosh"], False)
    ph = i / n * math.tau

    if anim == "idle":
        body.location.z = 0.008 * math.sin(ph)
        arms["l"].rotation_euler.y = math.radians(4 + 2 * math.sin(ph))
        arms["r"].rotation_euler.y = math.radians(-4 - 2 * math.sin(ph))
    elif anim == "walk":
        swing = math.radians(32) * math.sin(ph)
        legs["l"].rotation_euler.y = swing
        legs["r"].rotation_euler.y = -swing
        arms["l"].rotation_euler.y = -swing * 0.9
        arms["r"].rotation_euler.y = swing * 0.9
        body.location.z = 0.035 * abs(math.cos(ph))
        body.rotation_euler.y = math.radians(5)
        body.rotation_euler.z = math.radians(4) * math.sin(ph)
    elif anim == "search":
        # Leaning in, both hands rummaging.
        body.rotation_euler.y = math.radians(16)
        head.rotation_euler.y = math.radians(14)
        arms["l"].rotation_euler.y = math.radians(-70 - 18 * math.sin(ph))
        arms["r"].rotation_euler.y = math.radians(-70 - 18 * math.sin(ph + math.pi))
        arms["l"].rotation_euler.x = math.radians(-12)
        arms["r"].rotation_euler.x = math.radians(12)
    elif anim == "swing":
        # Overarm cosh swing: wind up, strike, follow through.
        set_visible(rig["cosh"], True)
        k = i / max(1, n - 1)
        arms["r"].rotation_euler.y = math.radians(-200 + 230 * k)
        rig["cosh"].rotation_euler.y = math.radians(-60 + 40 * k)
        body.rotation_euler.z = math.radians(-20 + 35 * k)
        body.rotation_euler.y = math.radians(-6 + 18 * k)
        arms["l"].rotation_euler.y = math.radians(25 - 35 * k)
        legs["l"].rotation_euler.y = math.radians(-18)
        legs["r"].rotation_euler.y = math.radians(14)
    elif anim == "hurt":
        body.rotation_euler.y = math.radians(-16)
        head.rotation_euler.y = math.radians(-20)
        arms["l"].rotation_euler.x = math.radians(-50)
        arms["r"].rotation_euler.x = math.radians(50)
        legs["l"].rotation_euler.y = math.radians(10)
    elif anim == "down":
        # Flat on the back, arms and legs splayed.
        body.rotation_euler.y = math.radians(-88)
        # Rotating about the feet lays the body out along -X; slide it back
        # so the agent lies centred on the spot where they stood.
        body.location = (0.85, 0, 0.13)
        arms["l"].rotation_euler.x = math.radians(-70)
        arms["r"].rotation_euler.x = math.radians(70)
        legs["l"].rotation_euler.x = math.radians(-12)
        legs["r"].rotation_euler.x = math.radians(12)
        head.rotation_euler.z = math.radians(25)


# ------------------------------------------------------------------ rendering

def foot_anchor(scene, cam):
    """Pixel position of the floor point under the agent, and pixels per metre."""
    p0 = world_to_camera_view(scene, cam, Vector((0, 0, 0)))
    p1 = world_to_camera_view(scene, cam, Vector((0, 0, 1)))
    ax = p0.x * FRAME
    ay = (1 - p0.y) * FRAME
    ppm_vertical = (p0.y - p1.y) * -FRAME
    return ax, ay, ppm_vertical


def render_agent(name, colors, tmp):
    scene = reset_scene()
    add_lights()
    cam = add_camera()
    agent = agent_model.Agent(colors)
    frames = []
    for d in range(DIRECTIONS):
        agent.root.rotation_euler = Euler((0, 0, math.radians(-45 * d)))
        row = []
        for anim, n in ANIMS:
            for i in range(n):
                agent.pose(anim, i, n)
                path = os.path.join(tmp, f"{name}_{d}_{anim}_{i}.png")
                scene.render.filepath = path
                bpy.ops.render.render(write_still=True)
                row.append(path)
        frames.append(row)
        print(f"  {name}: direction {d + 1}/{DIRECTIONS}", flush=True)
    return frames, foot_anchor(scene, cam)


def build_sheet(frames, out_path):
    from PIL import Image
    cols = len(frames[0])
    sheet = Image.new("RGBA", (cols * FRAME, len(frames) * FRAME), (0, 0, 0, 0))
    for r, row in enumerate(frames):
        for c, path in enumerate(row):
            sheet.paste(Image.open(path).convert("RGBA"), (c * FRAME, r * FRAME))
    sheet.save(out_path, optimize=True)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="agents_")
    meta = {"frame": FRAME, "directions": DIRECTIONS, "anims": {}, "sheets": {}}
    col = 0
    for anim, n in ANIMS:
        meta["anims"][anim] = {"start": col, "count": n}
        col += n
    try:
        for name, colors in AGENTS.items():
            print("Rendering", name, flush=True)
            frames, (ax, ay, ppm) = render_agent(name, colors, tmp)
            out = os.path.join(OUT_DIR, f"agent_{name}.png")
            build_sheet(frames, out)
            meta["sheets"][name] = f"res://assets/sprites/agent_{name}.png"
            meta["anchor"] = [round(ax, 2), round(ay, 2)]
            meta["pixels_per_metre"] = round(ppm, 3)
            print("  wrote", out, flush=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    with open(os.path.join(OUT_DIR, "agents.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print("done:", os.path.join(OUT_DIR, "agents.json"))


if __name__ == "__main__":
    main()
