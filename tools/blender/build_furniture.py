#!/usr/bin/env python3
"""Models and renders every piece of furniture as isometric sprites.

Each type is built from scratch with bpy, in *game units* (1 Blender unit =
1 game floor unit), using the same footprints and heights as the game
(scripts/world.gd TYPES and room_view.gd HEIGHTS), then rendered for each
wall it can stand against, with a matching normal map.

    .blendenv/bin/python tools/blender/build_furniture.py [--preview] [--only safe,console]

Output: assets/sprites/furniture/<type>_<wall>.png (+ _n.png normal maps)
and assets/sprites/furniture.json with each sprite's anchor (the pixel where
the centre of the footprint sits on the floor) and its scale.

Projection: the game draws floor x as (k, k/2) pixels per unit and height
as 1 pixel per unit (k = 0.68). An orthographic camera 30 degrees above the
horizon gives the same floor projection with heights foreshortened by
cos(30), so models are built 1/cos(30) taller to match.
"""
import json
import math
import os
import shutil
import sys
import tempfile

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_agents as BA  # noqa: E402  (scene, lights, normal-map helpers)
from agent_model import _principled, _fabric  # noqa: E402

ROOT = BA.ROOT
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "furniture")
PREVIEW = "--preview" in sys.argv
RES = 1.0 if PREVIEW else 2.0      # sprite pixels per game pixel
ISO_K = 0.68
ZS = 1.0 / math.cos(math.radians(30))   # height stretch to match the game

# Footprints along the top wall (width along x, depth along y) and heights.
TYPES = {
    "desk": (150, 70, 40), "console": (180, 60, 52), "cabinet": (70, 60, 72),
    "locker": (110, 50, 120), "crate": (80, 80, 58), "shelf": (160, 45, 112),
    "safe": (75, 75, 62), "plant": (55, 55, 24), "rack": (140, 40, 100), "sofa": (170, 70, 24),
}
WALL_TYPES = ["desk", "console", "cabinet", "locker", "shelf", "safe", "plant", "rack", "sofa"]
FRONT_TYPES = ["desk", "crate", "safe", "plant", "sofa", "console"]
FREE_TYPES = ["crate", "desk", "plant"]
# Blender rotation for each wall. Models face Blender -Y (the game's +y),
# i.e. they stand against the top wall; the game's angles are mirrored.
WALL_ROT = {"top": 0.0, "bottom": 180.0, "left": 90.0, "right": -90.0, "free": 0.0}


def variants():
    out = []
    for t in TYPES:
        walls = set()
        if t in WALL_TYPES:
            walls |= {"top", "left"}
        if t in FRONT_TYPES:
            walls |= {"bottom", "right"}
        if t in FREE_TYPES:
            walls.add("free")
        out += [(t, w) for w in sorted(walls)]
    return out


# ------------------------------------------------------------------ building blocks

class Kit:
    def __init__(self, parent):
        self.parent = parent

    def _obj(self, name, me, mat, loc, rot=(0, 0, 0)):
        o = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(o)
        o.parent = self.parent
        o.location = loc
        o.rotation_euler = rot
        if mat:
            o.data.materials.append(mat)
        return o

    def box(self, size, loc, mat, bevel=1.2, rot=(0, 0, 0)):
        """size and loc in game units; loc is the box centre, z already stretched."""
        bpy.ops.mesh.primitive_cube_add(size=1)
        o = bpy.context.object
        o.scale = size
        bpy.ops.object.transform_apply(scale=True)
        o.parent = self.parent
        o.location = loc
        o.rotation_euler = rot
        o.data.materials.append(mat)
        if bevel:
            b = o.modifiers.new("bevel", "BEVEL")
            b.width = bevel
            b.segments = 2
            for p in o.data.polygons:
                p.use_smooth = True
        return o

    def cyl(self, r, depth, loc, mat, verts=24, rot=(0, 0, 0), r2=None, bevel=0.0):
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r if r2 is None else r2, depth=depth)
        o = bpy.context.object
        o.parent = self.parent
        o.location = loc
        o.rotation_euler = rot
        o.data.materials.append(mat)
        for p in o.data.polygons:
            p.use_smooth = True
        if bevel:
            b = o.modifiers.new("bevel", "BEVEL")
            b.width = bevel
            b.segments = 2
        return o

    def sphere(self, r, loc, mat, scale=(1, 1, 1), segs=16):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=segs // 2, radius=r)
        o = bpy.context.object
        o.parent = self.parent
        o.location = loc
        o.scale = scale
        o.data.materials.append(mat)
        for p in o.data.polygons:
            p.use_smooth = True
        return o

    def text(self, body, size, loc, mat, rot=(math.radians(90), 0, 0)):
        cu = bpy.data.curves.new("txt", "FONT")
        cu.body = body
        cu.size = size
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        cu.extrude = 0.15
        o = bpy.data.objects.new("txt", cu)
        bpy.context.collection.objects.link(o)
        o.parent = self.parent
        o.location = loc
        o.rotation_euler = rot
        o.data.materials.append(mat)
        return o


def emission(name, color, strength=3.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1)
    em.inputs["Strength"].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


def screen_material():
    """A dark screen with a glowing green signal trace."""
    m = bpy.data.materials.new("screen")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "Z"
    wave.inputs["Scale"].default_value = 0.35
    wave.inputs["Distortion"].default_value = 6.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.82
    ramp.color_ramp.elements[0].color = (0.0, 0.05, 0.04, 1)
    ramp.color_ramp.elements[1].position = 0.95
    ramp.color_ramp.elements[1].color = (0.3, 1.0, 0.6, 1)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 2.5
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
    nt.links.new(wave.outputs["Color"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


def materials():
    return {
        "steel": _principled("steel", (0.32, 0.35, 0.4), 0.45, metal=0.6),
        "steel_dark": _principled("steel_dark", (0.14, 0.15, 0.18), 0.4, metal=0.6),
        "grey": _principled("grey", (0.42, 0.45, 0.5), 0.55, metal=0.3),
        "panel": _principled("panel", (0.17, 0.23, 0.28), 0.5, metal=0.2),
        "black": _principled("black", (0.02, 0.02, 0.025), 0.35),
        "chrome": _principled("chrome", (0.8, 0.82, 0.85), 0.15, metal=1.0),
        "brass": _principled("brass", (0.9, 0.68, 0.28), 0.3, metal=1.0),
        "green": _principled("green_locker", (0.16, 0.36, 0.28), 0.5, metal=0.3),
        "wood": _principled("wood", (0.42, 0.27, 0.15), 0.6),
        "wood_dark": _principled("wood_dark", (0.24, 0.15, 0.09), 0.55),
        "crate": _principled("crate", (0.48, 0.42, 0.25), 0.8),
        "paper": _principled("paper", (0.92, 0.9, 0.84), 0.8),
        "mug": _principled("mug", (0.85, 0.2, 0.18), 0.3, coat=0.5),
        "pot": _principled("pot", (0.5, 0.3, 0.2), 0.7),
        "soil": _principled("soil", (0.12, 0.08, 0.05), 0.95),
        "leaf": _principled("leaf", (0.12, 0.42, 0.16), 0.45, sss=0.0),
        "leaf2": _principled("leaf2", (0.18, 0.55, 0.22), 0.45),
        "sofa": _fabric("sofa", (0.36, 0.08, 0.12), scale=90, strength=0.2),
        "sofa_dark": _fabric("sofa_dark", (0.24, 0.05, 0.08), scale=90, strength=0.2),
        "red": _principled("stencil", (0.75, 0.12, 0.1), 0.7),
        "screen": screen_material(),
        "led_r": emission("led_r", (1.0, 0.2, 0.15)),
        "led_g": emission("led_g", (0.25, 1.0, 0.45)),
        "led_y": emission("led_y", (1.0, 0.8, 0.2)),
        "led_b": emission("led_b", (0.25, 0.7, 1.0)),
        "umbrella": _fabric("umbrella", (0.05, 0.05, 0.06), scale=200, strength=0.1),
        "books": [_principled(f"book{i}", c, 0.6) for i, c in enumerate([
            (0.55, 0.1, 0.1), (0.1, 0.25, 0.5), (0.8, 0.65, 0.15), (0.12, 0.4, 0.2),
            (0.85, 0.85, 0.8), (0.35, 0.15, 0.45), (0.15, 0.15, 0.17)])],
    }


# ------------------------------------------------------------------ the furniture
# All builders work in the "top wall" orientation: width along X, depth along
# Y with the front at -Y and the back (against the wall) at +Y; z from 0 up.

def build(kind, k, m):
    w, d, h = TYPES[kind]
    H = h * ZS
    getattr(sys.modules[__name__], "build_" + kind)(k, m, w, d, H)


def build_desk(k, m, w, d, H):
    top = 4 * ZS
    k.box((w, d, top), (0, 0, H - top / 2), m["wood"], 1.0)
    # Drawer pedestal on the left, legs on the right.
    pw = 42
    k.box((pw, d - 6, H - top), (-w / 2 + pw / 2 + 3, 0, (H - top) / 2), m["wood_dark"])
    for i in range(3):
        z = (H - top) * (i + 0.5) / 3
        k.box((pw - 6, 1.5, (H - top) / 3 - 3), (-w / 2 + pw / 2 + 3, -d / 2 + 2, z), m["wood"], 0.6)
        k.box((10, 1.5, 1.6), (-w / 2 + pw / 2 + 3, -d / 2 + 0.5, z), m["brass"], 0.3)
    for x in (w / 2 - 5,):
        for y in (-d / 2 + 5, d / 2 - 5):
            k.box((4, 4, H - top), (x, y, (H - top) / 2), m["wood_dark"], 0.5)
    k.box((w - pw - 10, 2, (H - top) * 0.6), (pw / 2 + 2, d / 2 - 4, (H - top) * 0.62), m["wood_dark"], 0.5)
    # Monitor, keyboard, papers, coffee mug.
    k.box((10, 8, 2), (10, 12, H + 1), m["black"], 0.5)
    k.box((3, 3, 14 * ZS), (10, 14, H + 7 * ZS), m["black"], 0.5)
    k.box((46, 4, 30 * ZS), (10, 12, H + 20 * ZS), m["black"], 1.0)
    k.box((41, 1, 25 * ZS), (10, 9.8, H + 20 * ZS), m["screen"], 0)
    k.box((34, 11, 1.6), (12, -14, H + 0.8), m["steel_dark"], 0.5)
    for i in range(3):
        k.box((26, 34, 0.4), (-40 + i * 2, -8 + i * 1.5, H + 0.3 + i * 0.4), m["paper"], 0, rot=(0, 0, math.radians(8 * i - 6)))
    k.cyl(4.5, 9 * ZS, (52, -16, H + 4.5 * ZS), m["mug"], 20, bevel=0.5)


def build_console(k, m, w, d, H):
    body = H * 0.75
    k.box((w, d, body), (0, 0, body / 2), m["panel"])
    k.box((w - 4, 2, body - 10), (0, -d / 2 - 0.5, body / 2), m["steel_dark"], 0.5)
    # Sloped control panel.
    k.box((w - 6, d * 0.75, 4), (0, -2, body + 6), m["steel"], 0.8, rot=(math.radians(-18), 0, 0))
    leds = [m["led_r"], m["led_g"], m["led_y"], m["led_b"]]
    for i in range(14):
        x = -w / 2 + 14 + i * (w - 28) / 13
        for j, y in enumerate((-12, -2)):
            k.cyl(2.2, 2, (x, y, body + 8 + j * 3.2), leds[(i + j * 2) % 4], 12, rot=(math.radians(-18), 0, 0))
    for i in range(4):
        k.cyl(4, 3, (-w / 2 + 20 + i * 14, 8, body + 11), m["black"], 16, rot=(math.radians(-18), 0, 0))
    # Back: cooling vents, a warning label and cables.
    for v in range(6):
        k.box((w * 0.5, 1.2, 1.6), (-w * 0.12, d / 2 + 0.6, body * 0.25 + v * 4.2), m["steel_dark"], 0.3)
    k.box((26, 0.6, 12), (w * 0.3, d / 2 + 0.8, body * 0.55), m["led_y"], 0.2)
    k.text("DANGER", 5, (w * 0.3, d / 2 + 1.3, body * 0.55), m["black"], rot=(math.radians(90), 0, math.radians(180)))
    for i in range(3):
        k.cyl(1.4, body * 0.7, (-w / 2 + 14 + i * 5, d / 2 + 2.5, body * 0.35), m["black"], 10)
    # Upright screen at the back.
    k.box((w * 0.55, 6, 36 * ZS), (w * 0.15, d / 2 - 4, body + 18 * ZS), m["black"], 1.2)
    k.box((w * 0.5, 1, 30 * ZS), (w * 0.15, d / 2 - 7.2, body + 18 * ZS), m["screen"], 0)


def build_cabinet(k, m, w, d, H):
    k.box((w, d, H), (0, 0, H / 2), m["grey"])
    for i in range(3):
        z = H * (i + 0.5) / 3
        k.box((w - 6, 1.6, H / 3 - 4), (0, -d / 2 - 0.3, z), m["grey"], 0.8)
        k.box((16, 3, 2.5), (0, -d / 2 - 1.5, z + 3), m["chrome"], 0.6)
        k.box((12, 0.6, 5), (0, -d / 2 - 1.2, z + 9), m["paper"], 0.2)


def build_locker(k, m, w, d, H):
    k.box((w, d, H), (0, 0, H / 2), m["green"])
    n = 3
    dw = w / n
    for i in range(n):
        x = -w / 2 + dw * (i + 0.5)
        k.box((dw - 3, 1.4, H - 8), (x, -d / 2 - 0.3, H / 2), m["green"], 0.6)
        for v in range(4):
            k.box((dw * 0.55, 1.2, 1.4), (x, -d / 2 - 1.0, H - 14 - v * 4.5), m["steel_dark"], 0.2)
        k.box((2.5, 2.5, 12), (x + dw * 0.32, -d / 2 - 1.6, H * 0.5), m["chrome"], 0.6)
        k.box((7, 0.6, 4), (x, -d / 2 - 1.1, H - 34), m["brass"], 0.3)
    k.box((w + 2, d + 2, 3), (0, 0, H + 1), m["green"], 0.8)


def build_crate(k, m, w, d, H):
    k.box((w - 4, d - 4, H - 4), (0, 0, H / 2), m["wood_dark"], 0)
    planks = 4
    for i in range(planks):
        z = H * (i + 0.5) / planks
        k.box((w, d + 0.5, H / planks - 2.2), (0, 0, z), m["crate"], 0.8)
    for sx in (-1, 1):
        for sy in (-1, 1):
            k.box((6, 6, H + 0.5), (sx * (w / 2 - 2.5), sy * (d / 2 - 2.5), H / 2), m["steel_dark"], 0.6)
    k.box((w + 0.5, 6, 6), (0, 0, H - 2.5), m["crate"], 0.5)
    k.text("TOP SECRET", 9.5, (0, -d / 2 - 0.8, H * 0.5), m["red"])
    k.text("TOP SECRET", 9.5, (w / 2 + 0.8, 0, H * 0.5), m["red"], rot=(math.radians(90), 0, math.radians(90)))


def build_shelf(k, m, w, d, H):
    t = 3
    k.box((t, d, H), (-w / 2 + t / 2, 0, H / 2), m["wood_dark"])
    k.box((t, d, H), (w / 2 - t / 2, 0, H / 2), m["wood_dark"])
    k.box((w, 2, H), (0, d / 2 - 1, H / 2), m["wood_dark"])
    rows = 4
    import random
    rnd = random.Random(7)
    for r in range(rows + 1):
        z = r * (H - t) / rows + t / 2
        k.box((w - 2 * t, d - 2, t), (0, -1, z), m["wood"], 0.4)
        if r == rows:
            continue
        x = -w / 2 + t + 1
        top_z = (H - t) / rows
        while x < w / 2 - t - 6:
            bw = rnd.uniform(3.5, 7.5)
            bh = rnd.uniform(0.62, 0.92) * (top_z - t)
            lean = math.radians(rnd.choice([0, 0, 0, 8, -6]))
            k.box((bw - 0.6, d - 10, bh), (x + bw / 2, -2, z + t / 2 + bh / 2), m["books"][rnd.randrange(7)], 0.4,
                  rot=(0, lean, 0))
            x += bw + rnd.choice([0, 0, 0.5, 6])


def build_safe(k, m, w, d, H):
    k.box((w, d, H), (0, 0, H / 2), m["steel_dark"], 3.0)
    k.box((w - 10, 3, H - 10), (0, -d / 2 - 0.8, H / 2), m["steel"], 1.5)
    k.cyl(11, 3, (-8, -d / 2 - 3, H * 0.55), m["chrome"], 32, rot=(math.radians(90), 0, 0), bevel=0.6)
    k.cyl(7.5, 4, (-8, -d / 2 - 4, H * 0.55), m["black"], 32, rot=(math.radians(90), 0, 0))
    for i in range(12):
        a = i * math.tau / 12
        k.box((0.8, 1, 2.2), (-8 + math.cos(a) * 9.5, -d / 2 - 4.6, H * 0.55 + math.sin(a) * 9.5), m["paper"], 0,
              rot=(0, -a, 0))
    hx = 16
    k.cyl(2, 3, (hx, -d / 2 - 3.5, H * 0.55), m["chrome"], 12, rot=(math.radians(90), 0, 0))
    for i in range(3):
        a = i * math.tau / 3 + 0.3
        k.box((1.4, 1.4, 11), (hx + math.cos(a) * 5, -d / 2 - 4.5, H * 0.55 + math.sin(a) * 5), m["chrome"], 0.4,
              rot=(0, -a + math.pi / 2, 0))
    for z in (H * 0.25, H * 0.75):
        k.cyl(2.2, 9, (w / 2 - 6, -d / 2 - 2, z), m["steel_dark"], 12, bevel=0.3)
    # Back: a bolted armour plate and a maker's plaque.
    k.box((w - 14, 2, H - 14), (0, d / 2 + 0.6, H / 2), m["steel"], 1.2)
    for sx in (-1, 1):
        for sz in (-1, 1):
            k.sphere(1.6, (sx * (w / 2 - 12), d / 2 + 1.8, H / 2 + sz * (H / 2 - 12)), m["chrome"])
    k.box((22, 0.6, 9), (0, d / 2 + 1.8, H * 0.62), m["brass"], 0.3)
    k.text("ACME", 5, (0, d / 2 + 2.3, H * 0.62), m["black"], rot=(math.radians(90), 0, math.radians(180)))


def build_plant(k, m, w, d, H):
    pot_h = H
    k.cyl(w * 0.36, pot_h, (0, 0, pot_h / 2), m["pot"], 28, r2=w * 0.42, bevel=0.8)
    k.cyl(w * 0.44, 3, (0, 0, pot_h), m["pot"], 28, bevel=0.6)
    k.cyl(w * 0.39, 1, (0, 0, pot_h - 1), m["soil"], 28)
    import random
    rnd = random.Random(3)
    for i in range(26):
        a = i * 2.39996
        tilt = rnd.uniform(0.25, 1.15)
        length = rnd.uniform(18, 30)
        base = Vector((math.cos(a) * 3, math.sin(a) * 3, pot_h + 2 + rnd.uniform(0, 26) * ZS))
        tip = base + Vector((math.cos(a) * math.sin(tilt), math.sin(a) * math.sin(tilt), math.cos(tilt))) * length
        mid = (base + tip) / 2
        leaf = k.sphere(1.0, mid, m["leaf"] if i % 3 else m["leaf2"], (length / 2, 4.5, 0.9), 12)
        direction = tip - base
        leaf.rotation_mode = "QUATERNION"
        leaf.rotation_quaternion = Vector((1, 0, 0)).rotation_difference(direction)


def build_rack(k, m, w, d, H):
    k.box((w, 4, H), (0, d / 2 - 2, H / 2), m["steel_dark"], 0.8)
    for x in (-w / 2 + 2, w / 2 - 2):
        k.box((4, d, H), (x, 0, H / 2), m["steel_dark"], 0.8)
    k.box((w, d, 4), (0, 0, 2), m["steel_dark"], 0.8)
    k.box((w - 8, 3, 3), (0, -d / 2 + 6, H * 0.78), m["chrome"], 0.6)
    # Batons hanging from the rail, two spy umbrellas propped up.
    for i in range(4):
        x = -w / 2 + 16 + i * 14
        k.cyl(1.8, H * 0.55, (x, -d / 2 + 6, H * 0.78 - H * 0.275), m["wood"], 12)
        k.sphere(3.6, (x, -d / 2 + 6, H * 0.78 - H * 0.56), m["black"], (1, 1, 1.4))
        k.cyl(2.4, 4, (x, -d / 2 + 6, H * 0.78 + 1), m["black"], 12)
    for i in range(2):
        x = w / 2 - 30 + i * 14
        k.cyl(4.5, H * 0.8, (x, -d / 2 + 10, H * 0.4 + 2), m["umbrella"], 10, r2=1.0)
        k.cyl(0.9, H * 0.15, (x, -d / 2 + 10, H * 0.88), m["chrome"], 8)
        k.box((7, 2, 2), (x + 3, -d / 2 + 10, H * 0.95), m["wood"], 0.5)


def build_sofa(k, m, w, d, H):
    seat = H
    back_h = 50 * ZS
    k.box((w, d, seat * 0.55), (0, 0, seat * 0.3), m["sofa_dark"], 3.0)
    for i in range(3):
        cw = (w - 30) / 3
        x = -w / 2 + 15 + cw * (i + 0.5)
        k.box((cw - 1.5, d - 22, seat * 0.5), (x, -6, seat * 0.75), m["sofa"], 4.0)
        k.box((cw - 3, 14, back_h * 0.62), (x, d / 2 - 12, seat + back_h * 0.28), m["sofa"], 4.5)
        k.sphere(1.2, (x, d / 2 - 19.5, seat + back_h * 0.36), m["sofa_dark"])
    k.box((w, 12, back_h), (0, d / 2 - 6, back_h / 2 + 2), m["sofa_dark"], 4.0)
    for sx in (-1, 1):
        k.box((14, d, seat + 12), (sx * (w / 2 - 7), 0, (seat + 12) / 2), m["sofa_dark"], 4.5)
    for sx in (-1, 1):
        for sy in (-1, 1):
            k.cyl(2, 4, (sx * (w / 2 - 8), sy * (d / 2 - 8), 2), m["wood_dark"], 10)


# ------------------------------------------------------------------ rendering

def setup_scene():
    scene = BA.reset_scene()
    BA.add_lights()
    scene.render.line_thickness = 1.0 if PREVIEW else 1.6
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.clip_end = 10000
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    elev = math.radians(30)
    direction = Vector((math.cos(elev) / math.sqrt(2), -math.cos(elev) / math.sqrt(2), math.sin(elev)))
    cam.location = direction * 3000
    aim = bpy.data.objects.new("cam_aim", None)
    bpy.context.collection.objects.link(aim)
    t = cam.constraints.new("TRACK_TO")
    t.target = aim
    t.track_axis = "TRACK_NEGATIVE_Z"
    t.up_axis = "UP_Y"
    scene.camera = cam
    # Sun lights don't care about scale, but the world light does a bit.
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.45
    return scene, cam


def render_variant(scene, cam, kind, wall, mats, nmat, tmp):
    for o in list(bpy.data.objects):
        if o.get("furniture"):
            bpy.data.objects.remove(o, do_unlink=True)
    root = bpy.data.objects.new("furn_root", None)
    bpy.context.collection.objects.link(root)
    root["furniture"] = True
    k = Kit(root)
    build(kind, k, mats)
    for o in root.children_recursive:
        o["furniture"] = True
    root.rotation_euler = (0, 0, math.radians(WALL_ROT[wall]))
    bpy.context.view_layer.update()

    # Canvas big enough for the biggest piece; pixels per Blender unit such
    # that floor x projects to (k, k/2) game pixels, times RES.
    size = int(400 * RES)
    ppu = ISO_K / math.cos(math.radians(45)) * RES
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    cam.data.ortho_scale = size / ppu
    # Put the footprint centre at 70% down the canvas so tall things fit.
    elev = math.radians(30)
    shift = (0.7 - 0.5) * cam.data.ortho_scale / math.cos(elev)
    cam.constraints[0].target.location = (0, 0, shift)
    cam.location = Vector(cam.constraints[0].target.location) + Vector(
        (math.cos(elev) / math.sqrt(2), -math.cos(elev) / math.sqrt(2), math.sin(elev))) * 3000
    bpy.context.view_layer.update()

    color = os.path.join(tmp, f"{kind}_{wall}.png")
    normal = os.path.join(tmp, f"{kind}_{wall}_n.png")
    scene.render.filepath = color
    bpy.ops.render.render(write_still=True)
    BA.render_normal(scene, normal, nmat)
    from bpy_extras.object_utils import world_to_camera_view
    p = world_to_camera_view(scene, cam, Vector((0, 0, 0)))
    anchor = (p.x * size, (1 - p.y) * size)
    return color, normal, anchor


def crop_and_save(color, normal, anchor, name):
    from PIL import Image
    c = Image.open(color).convert("RGBA")
    n = Image.open(normal).convert("RGBA")
    n.putalpha(c.getchannel("A"))
    box = c.getchannel("A").point(lambda a: 255 if a > 4 else 0).getbbox()
    pad = 2
    box = (max(0, box[0] - pad), max(0, box[1] - pad), min(c.width, box[2] + pad), min(c.height, box[3] + pad))
    c.crop(box).save(os.path.join(OUT_DIR, name + ".png"), optimize=True)
    n.crop(box).save(os.path.join(OUT_DIR, name + "_n.png"), optimize=True)
    return [round(anchor[0] - box[0], 2), round(anchor[1] - box[1], 2)]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    scene, cam = setup_scene()
    mats = materials()
    nmat = BA.normal_material()
    tmp = tempfile.mkdtemp(prefix="furn_")
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))
    path = os.path.join(ROOT, "assets", "sprites", "furniture.json")
    meta = {"scale": 1.0 / RES, "sprites": {}}
    if only and os.path.exists(path):
        with open(path) as f:
            meta = json.load(f)
    try:
        for kind, wall in variants():
            if only and kind not in only:
                continue
            color, normal, anchor = render_variant(scene, cam, kind, wall, mats, nmat, tmp)
            name = f"{kind}_{wall}"
            a = crop_and_save(color, normal, anchor, name)
            meta["sprites"][name] = {
                "color": f"res://assets/sprites/furniture/{name}.png",
                "normal": f"res://assets/sprites/furniture/{name}_n.png",
                "anchor": a,
            }
            print("  rendered", name, flush=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    with open(path, "w") as f:
        json.dump(meta, f, indent=2)
    print("done")


if __name__ == "__main__":
    main()
