#!/usr/bin/env python3
"""Renders the room surfaces as tileable textures with normal maps.

    .blendenv/bin/python tools/blender/build_rooms.py [--preview]

Output (assets/sprites/room/):
    floor.png, floor_n.png   steel tread plate, 128x128 game units
    wall.png,  wall_n.png    riveted wall panels, 128 wide x 110 high (WALL_H)

Both are rendered straight-on with an orthographic camera, so the normal
maps are in texture space and the room's 2D lights shade the bars, seams
and rivets. The game tiles them along the floor and walls.
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_agents as BA  # noqa: E402  (scene reset, normal-map helpers)

OUT_DIR = os.path.join(BA.ROOT, "assets", "sprites", "room")
PREVIEW = "--preview" in sys.argv
PX = 1 if PREVIEW else 2           # texture pixels per game unit
SAMPLES = 8 if PREVIEW else 48
WALL_H = 110.0


def mat(name, rgb, rough=0.55, metal=0.7, grime=0.0, scale=0.05):
    """Principled steel, optionally mottled with noise-driven grime."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if grime > 0.0:
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = scale
        noise.inputs["Detail"].default_value = 6.0
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.35
        ramp.color_ramp.elements[0].color = (rgb[0] * (1 - grime), rgb[1] * (1 - grime), rgb[2] * (1 - grime), 1)
        ramp.color_ramp.elements[1].position = 0.65
        ramp.color_ramp.elements[1].color = (*rgb, 1)
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    return m


def box(name, size, loc, m, bevel=0.6, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(m)
    if bevel > 0:
        b = o.modifiers.new("bevel", "BEVEL")
        b.width = bevel
        b.segments = 3
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def rivet(loc, m, r=1.8, axis="z"):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=16, ring_count=8)
    o = bpy.context.object
    o.scale = (1, 1, 0.6) if axis == "z" else (1, 0.6, 1)
    o.data.materials.append(m)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def setup(width, height, cam_loc, cam_rot):
    scene = BA.reset_scene()
    scene.render.engine = "CYCLES"
    scene.render.resolution_x = int(width * PX)
    scene.render.resolution_y = int(height * PX)
    scene.render.film_transparent = False
    scene.render.use_freestyle = False
    scene.cycles.samples = SAMPLES
    scene.view_settings.view_transform = "Standard"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("world")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.05, 0.05, 0.06, 1)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = max(width, height)
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = cam_loc
    cam.rotation_euler = cam_rot
    scene.camera = cam
    return scene


def lights(dirs):
    """Soft, even light: the game adds its own lamps through the normal map."""
    for d, energy, col in dirs:
        bpy.ops.object.light_add(type="SUN", location=(0, 0, 0))
        light = bpy.context.object
        light.data.energy = energy
        light.data.color = col
        light.data.angle = math.radians(25)
        light.rotation_euler = d


def render(scene, name):
    os.makedirs(OUT_DIR, exist_ok=True)
    scene.render.filepath = os.path.join(OUT_DIR, name + ".png")
    bpy.ops.render.render(write_still=True)
    BA.render_normal(scene, os.path.join(OUT_DIR, name + "_n.png"), BA.normal_material())
    print("wrote", name, flush=True)


def floor():
    """Steel tread plate seen from above: a bevelled plate, raised diagonal
    bars in a herringbone and a rivet in each corner. Tiles every 128 units."""
    scene = setup(128, 128, (0, 0, 300), (0, 0, 0))
    lights([((math.radians(35), 0, math.radians(-40)), 2.6, (1.0, 0.96, 0.9)),
            ((math.radians(40), 0, math.radians(140)), 1.3, (0.85, 0.9, 1.0))])
    steel = mat("plate", (0.42, 0.44, 0.48), 0.5, 0.75, grime=0.35, scale=0.04)
    bar = mat("bar", (0.5, 0.52, 0.56), 0.4, 0.8)
    seam = mat("seam", (0.22, 0.23, 0.26), 0.7, 0.6)
    box("ground", (200, 200, 4), (0, 0, -5), seam, 0)
    box("plate", (126.5, 126.5, 4), (0, 0, -2), steel, 0.8)
    for i in range(8):
        for j in range(8):
            ang = math.radians(45 if (i + j) % 2 == 0 else -45)
            box("bar", (9.5, 2.4, 1.6), (-56 + i * 16, -56 + j * 16, 0.6), bar, 0.5, (0, 0, ang))
    for sx in (-1, 1):
        for sy in (-1, 1):
            rivet((sx * 59, sy * 59, 0.2), bar, 2.2)
    render(scene, "floor")


def wall():
    """Two riveted panels seen straight on, with a seam between them, a
    skirting board and a cap rail. Tiles every 128 units, WALL_H high."""
    scene = setup(128, WALL_H, (0, -300, WALL_H / 2), (math.radians(90), 0, 0))
    lights([((math.radians(60), 0, math.radians(-25)), 2.4, (1.0, 0.96, 0.9)),
            ((math.radians(110), 0, math.radians(30)), 1.2, (0.85, 0.9, 1.0))])
    steel = mat("panel", (0.36, 0.39, 0.45), 0.55, 0.7, grime=0.4, scale=0.03)
    trim = mat("trim", (0.2, 0.22, 0.26), 0.7, 0.5)
    dark = mat("backing", (0.04, 0.045, 0.06), 0.9, 0.2)
    skirt = mat("skirting", (0.16, 0.17, 0.2), 0.6, 0.6, grime=0.5, scale=0.06)
    box("backing", (200, 4, 200), (0, 6, WALL_H / 2), dark, 0)
    for z0, z1 in ((11.0, 60.0), (63.0, 104.0)):
        h = z1 - z0
        box("panel", (125, 3, h), (0, 1.5, z0 + h / 2), steel, 1.2)
        for sx in (-1, 1):
            for z in (z0 + 6, z1 - 6):
                rivet((sx * 56, -0.2, z), trim, 1.7, axis="y")
    box("skirting", (128, 4.5, 11), (0, 0.75, 5.5), skirt, 0.5)
    box("rail", (128, 3.5, 4), (0, 1.25, WALL_H - 2), trim, 0.5)
    render(scene, "wall")


if __name__ == "__main__":
    floor()
    wall()
    print("done:", OUT_DIR)
