#!/usr/bin/env python3
"""Renders the agents crawling through an air duct, seen side-on.

Used for the vent-shortcut cut-away. Same model and lights as the main
agent sprites, but an orthographic camera looking straight at the agent's
side, so the crawl reads like a cross-section of the duct.

    .blendenv/bin/python tools/blender/build_crawl.py

Writes assets/sprites/crawl_<agent>.png: FRAMES frames in a row, facing right.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agent_model  # noqa: E402
import build_agents as BA  # noqa: E402

FRAMES = 8
W, H = 288, 176


def main():
    from PIL import Image
    out_dir = os.path.join(BA.ROOT, "assets", "sprites")
    for name, colors in BA.AGENTS.items():
        scene = BA.reset_scene()
        BA.add_lights()
        scene.render.resolution_x = W
        scene.render.resolution_y = H
        scene.render.line_thickness = 2.0
        cam_data = bpy.data.cameras.new("side")
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = 2.5
        cam = bpy.data.objects.new("side", cam_data)
        bpy.context.collection.objects.link(cam)
        cam.location = Vector((0, -8, 0.42))
        cam.rotation_euler = (math.radians(90), 0, 0)
        scene.camera = cam
        agent = agent_model.Agent(colors)
        sheet = Image.new("RGBA", (W * FRAMES, H), (0, 0, 0, 0))
        for i in range(FRAMES):
            agent.pose("crawl", i, FRAMES)
            path = f"/tmp/crawl_{name}_{i}.png"
            scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            sheet.paste(Image.open(path).convert("RGBA"), (i * W, 0))
            os.remove(path)
        out = os.path.join(out_dir, f"crawl_{name}.png")
        sheet.save(out, optimize=True)
        print("wrote", out, flush=True)


if __name__ == "__main__":
    main()
