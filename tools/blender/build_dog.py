#!/usr/bin/env python3
"""Renders Nacho the dog as isometric sprite sheets, like the agents.

Same camera, lights, ink outlines and frame size as build_agents.py, so he
sits at the right scale beside them. Run with the Blender-as-a-module Python:

    .blendenv/bin/python tools/blender/build_dog.py             # full render
    .blendenv/bin/python tools/blender/build_dog.py --preview   # contact sheet
                                     # of a few poses -> /tmp/dog_preview.png

Writes (in assets/sprites/):
    agent_dog.png, agent_dog_n.png   packed colour atlas and normal map
    dog.json                         frame rects, anchor, animations
    crawl_dog.png                    side-on trot for the air-duct cut-away
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
import build_agents as BA  # noqa: E402
import dog_model  # noqa: E402
import pack_sprites  # noqa: E402

CRAWL_FRAMES = 8
CRAWL_W, CRAWL_H = 288, 176


def _scene():
    scene = BA.reset_scene()
    BA.add_lights()
    return scene


def _no_ink(scene, dog):
    """Leaves Nacho out of the ink outlines (his hair is his outline)."""
    ls = scene.view_layers[0].freestyle_settings.linesets[0]
    ls.select_by_collection = True
    ls.collection = dog.collection
    ls.collection_negation = "EXCLUSIVE"


def preview():
    from PIL import Image
    scene = _scene()
    cam = BA.add_camera()
    # Close up, so the coat and face can be checked.
    cam.data.ortho_scale = 1.35
    cam.constraints[0].target.location = (0.05, 0, 0.45)
    scene.render.resolution_x = scene.render.resolution_y = 300
    scene.cycles.samples = 24
    dog = dog_model.Dog()
    _no_ink(scene, dog)
    shots = [("idle", 0, 2, 0), ("idle", 0, 2, 2), ("walk", 2, 8, 1), ("sit", 0, 2, 3),
             ("sniff", 1, 4, 6), ("bark", 0, 4, 1), ("growl", 0, 2, 7), ("poo", 1, 2, 3)]
    tiles = []
    for anim, i, n, d in shots:
        dog.root.rotation_euler = Euler((0, 0, math.radians(-45 * d)))
        dog.pose(anim, i, n)
        path = f"/tmp/dog_{anim}_{d}.png"
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        tiles.append(Image.open(path).convert("RGBA"))
    f = 300
    sheet = Image.new("RGBA", (f * 4, f * 2), (0, 0, 0, 0))
    for k, t in enumerate(tiles):
        sheet.alpha_composite(t, ((k % 4) * f, (k // 4) * f))
    sheet.save("/tmp/dog_preview.png")
    print("wrote /tmp/dog_preview.png", BA.foot_anchor(scene, cam))


def render_sprites(tmp):
    scene = _scene()
    cam = BA.add_camera()
    dog = dog_model.Dog()
    _no_ink(scene, dog)
    nmat = BA.normal_material()
    frames = []
    for d in range(BA.DIRECTIONS):
        dog.root.rotation_euler = Euler((0, 0, math.radians(-45 * d)))
        for anim, n in dog_model.ANIMS:
            for i in range(n):
                dog.pose(anim, i, n)
                path = os.path.join(tmp, f"dog_{d}_{anim}_{i}.png")
                scene.render.filepath = path
                bpy.ops.render.render(write_still=True)
                npath = path.replace(".png", "_n.png")
                BA.render_normal(scene, npath, nmat)
                frames.append((path, npath))
        print(f"  dog: direction {d + 1}/{BA.DIRECTIONS}", flush=True)
    return frames, BA.foot_anchor(scene, cam)


def render_crawl(out_dir):
    """Side-on trot, facing right, for the air-duct cut-away."""
    from PIL import Image
    scene = _scene()
    scene.render.resolution_x = CRAWL_W
    scene.render.resolution_y = CRAWL_H
    scene.render.line_thickness = 2.0
    cam_data = bpy.data.cameras.new("side")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.5
    cam = bpy.data.objects.new("side", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = Vector((0, -8, 0.42))
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = cam
    dog = dog_model.Dog()
    _no_ink(scene, dog)
    sheet = Image.new("RGBA", (CRAWL_W * CRAWL_FRAMES, CRAWL_H), (0, 0, 0, 0))
    for i in range(CRAWL_FRAMES):
        dog.pose("walk", i, CRAWL_FRAMES)
        path = f"/tmp/crawl_dog_{i}.png"
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        sheet.paste(Image.open(path).convert("RGBA"), (i * CRAWL_W, 0))
        os.remove(path)
    out = os.path.join(out_dir, "crawl_dog.png")
    sheet.save(out, optimize=True)
    print("wrote", out, flush=True)


def main():
    if BA.PREVIEW:
        preview()
        return
    from PIL import Image
    out_dir = os.path.join(BA.ROOT, "assets", "sprites")
    pack_sprites.OUT_DIR = out_dir
    meta = {"frame": BA.FRAME, "directions": BA.DIRECTIONS, "anims": {}, "sheets": {}, "normals": {}}
    col = 0
    for anim, n in dog_model.ANIMS:
        meta["anims"][anim] = {"start": col, "count": n}
        col += n
    meta["frames_per_direction"] = col
    tmp = tempfile.mkdtemp(prefix="dog_")
    try:
        frames, (ax, ay, ppm) = render_sprites(tmp)
        colours = [Image.open(f[0]).convert("RGBA") for f in frames]
        normals = []
        for k, f in enumerate(frames):
            n = Image.open(f[1]).convert("RGBA")
            n.putalpha(colours[k].getchannel("A"))
            normals.append(n)
        print("  packed into", pack_sprites.write("dog", colours, normals, meta), flush=True)
        meta["anchor"] = [round(ax, 2), round(ay, 2)]
        meta["pixels_per_metre"] = round(ppm, 3)
        with open(os.path.join(out_dir, "dog.json"), "w") as f:
            json.dump(meta, f, indent=1)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    render_crawl(out_dir)


if __name__ == "__main__":
    main()
