#!/usr/bin/env python3
"""Packs agent sprite frames tightly into atlases to keep the game small.

Rendered frames are mostly empty space, so each frame is trimmed to its
visible pixels and shelf-packed into an atlas. Positions are aligned to 4
pixels so the GPU's 4x4 block compression never mixes neighbouring frames.
Normal maps are packed with exactly the same layout at half resolution
(lighting doesn't need full detail), so one set of UVs serves both.

Used by build_agents.py; can also repack existing uniform sheets:

    python3 tools/blender/pack_sprites.py --from-sheets
"""
import json
import math
import os
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "sprites")
ALIGN = 4
PAD = 4
NORMAL_SCALE = 2   # normal maps are 1/NORMAL_SCALE size


def _up(v, a=ALIGN):
    return (v + a - 1) // a * a


def pack(colours, normals):
    """colours/normals: lists of same-size RGBA images, one per frame.
    Returns (colour atlas, normal atlas, rects) where rects[i] is
    [x, y, w, h, offset_x, offset_y] (offset = where the trimmed rect sits
    inside the original frame)."""
    trims = []
    for img in colours:
        box = img.getchannel("A").point(lambda a: 255 if a > 2 else 0).getbbox() or (0, 0, ALIGN, ALIGN)
        # Grow to the alignment grid so offsets and sizes stay block-aligned.
        x0 = box[0] // ALIGN * ALIGN
        y0 = box[1] // ALIGN * ALIGN
        x1 = min(img.width, _up(box[2]))
        y1 = min(img.height, _up(box[3]))
        trims.append((x0, y0, x1, y1))
    area = sum((t[2] - t[0] + PAD) * (t[3] - t[1] + PAD) for t in trims)
    width = min(4096, _up(int(math.sqrt(area) * 1.08), 64))
    order = sorted(range(len(trims)), key=lambda i: -(trims[i][3] - trims[i][1]))
    rects = [None] * len(trims)
    x = y = shelf_h = 0
    for i in order:
        w = trims[i][2] - trims[i][0]
        h = trims[i][3] - trims[i][1]
        if x + w > width:
            x = 0
            y += shelf_h + PAD
            shelf_h = 0
        rects[i] = [x, y, w, h, trims[i][0], trims[i][1]]
        x += _up(w + PAD)
        shelf_h = max(shelf_h, h)
    height = _up(y + shelf_h, 64)
    atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    natlas = Image.new("RGBA", (width // NORMAL_SCALE, height // NORMAL_SCALE), (128, 128, 255, 0))
    for i, r in enumerate(rects):
        t = trims[i]
        atlas.paste(colours[i].crop(t), (r[0], r[1]))
        n = normals[i].crop(t).resize((r[2] // NORMAL_SCALE, r[3] // NORMAL_SCALE), Image.LANCZOS)
        natlas.paste(n, (r[0] // NORMAL_SCALE, r[1] // NORMAL_SCALE))
    return atlas, natlas, rects


def write(name, colours, normals, meta):
    atlas, natlas, rects = pack(colours, normals)
    atlas.save(os.path.join(OUT_DIR, f"agent_{name}.png"), optimize=True)
    natlas.save(os.path.join(OUT_DIR, f"agent_{name}_n.png"), optimize=True)
    meta.setdefault("rects", {})[name] = rects
    meta["packed"] = True
    meta["sheets"][name] = f"res://assets/sprites/agent_{name}.png"
    meta["normals"][name] = f"res://assets/sprites/agent_{name}_n.png"
    return atlas.size


def from_sheets():
    """Repacks uniform sheets (frames on a grid) written by older renders."""
    path = os.path.join(OUT_DIR, "agents.json")
    with open(path) as f:
        meta = json.load(f)
    if meta.get("packed"):
        print("already packed")
        return
    fsize = meta["frame"]
    cols = meta["cols"]
    total = meta["frames_per_direction"] * meta["directions"]
    for name in list(meta["sheets"]):
        sheet = Image.open(os.path.join(OUT_DIR, f"agent_{name}.png")).convert("RGBA")
        nsheet = Image.open(os.path.join(OUT_DIR, f"agent_{name}_n.png")).convert("RGBA")
        boxes = [((k % cols) * fsize, (k // cols) * fsize, (k % cols + 1) * fsize, (k // cols + 1) * fsize) for k in range(total)]
        size = write(name, [sheet.crop(b) for b in boxes], [nsheet.crop(b) for b in boxes], meta)
        print(name, "packed into", size)
    meta.pop("cols", None)
    with open(path, "w") as f:
        json.dump(meta, f, indent=1)


if __name__ == "__main__":
    if "--from-sheets" in sys.argv:
        from_sheets()
