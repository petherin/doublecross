"""Detailed, procedurally sculpted spy model with a forward-kinematics skeleton.

The body is built from "skin" meshes: a stick-figure skeleton whose vertices
carry a radius, which Blender's Skin + Subdivision modifiers turn into smooth,
organic shapes. Posing moves the skeleton's vertices (forward kinematics), so
elbows and knees bend and the coat follows the torso. Rigid parts (head, hat,
glasses, belt, cosh...) ride on empties that are moved with the joints.

Agents face +X, with +Y to their left and +Z up. One unit is a metre.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

# ------------------------------------------------------------------ skeleton

# joint -> (parent, rest offset from parent in the parent's frame)
JOINTS = {
    "pelvis": (None, (0.0, 0.0, 0.95)),
    "spine": ("pelvis", (0.0, 0.0, 0.2)),
    "chest": ("spine", (0.0, 0.0, 0.2)),
    "neck": ("chest", (0.0, 0.0, 0.17)),
    "head": ("neck", (0.0, 0.0, 0.1)),
    "shoulder_l": ("chest", (0.0, 0.205, 0.04)),
    "elbow_l": ("shoulder_l", (0.0, 0.0, -0.29)),
    "wrist_l": ("elbow_l", (0.0, 0.0, -0.26)),
    "hand_l": ("wrist_l", (0.0, 0.0, -0.09)),
    "shoulder_r": ("chest", (0.0, -0.205, 0.04)),
    "elbow_r": ("shoulder_r", (0.0, 0.0, -0.29)),
    "wrist_r": ("elbow_r", (0.0, 0.0, -0.26)),
    "hand_r": ("wrist_r", (0.0, 0.0, -0.09)),
    "hip_l": ("pelvis", (0.0, 0.1, -0.03)),
    "knee_l": ("hip_l", (0.0, 0.0, -0.43)),
    "ankle_l": ("knee_l", (0.0, 0.0, -0.42)),
    "toe_l": ("ankle_l", (0.17, 0.0, -0.045)),
    "heel_l": ("ankle_l", (-0.06, 0.0, -0.045)),
    "hip_r": ("pelvis", (0.0, -0.1, -0.03)),
    "knee_r": ("hip_r", (0.0, 0.0, -0.43)),
    "ankle_r": ("knee_r", (0.0, 0.0, -0.42)),
    "toe_r": ("ankle_r", (0.17, 0.0, -0.045)),
    "heel_r": ("ankle_r", (-0.06, 0.0, -0.045)),
}


def rot(fwd=0.0, side=0.0, twist=0.0):
    """A joint rotation in degrees: `fwd` swings a hanging limb forwards
    (towards +X), `side` swings it towards +Y, `twist` turns about Z."""
    return (Matrix.Rotation(math.radians(twist), 4, "Z")
            @ Matrix.Rotation(math.radians(side), 4, "X")
            @ Matrix.Rotation(math.radians(-fwd), 4, "Y"))


def solve(angles, root=Matrix.Identity(4)):
    """World (agent-local) matrix of every joint for the given joint angles."""
    out = {}
    for name, (par, off) in JOINTS.items():
        base = out[par] if par else root
        out[name] = base @ Matrix.Translation(Vector(off)) @ angles.get(name, Matrix.Identity(4))
    return out


# ------------------------------------------------------------------ materials

def _principled(name, color, rough=0.6, metal=0.0, coat=0.0, sss=0.0, sheen=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if coat and "Coat Weight" in p.inputs:
        p.inputs["Coat Weight"].default_value = coat
    if sss and "Subsurface Weight" in p.inputs:
        p.inputs["Subsurface Weight"].default_value = sss
        p.inputs["Subsurface Radius"].default_value = (0.9, 0.35, 0.2)
        p.inputs["Subsurface Scale"].default_value = 0.02
    if sheen and "Sheen Weight" in p.inputs:
        p.inputs["Sheen Weight"].default_value = sheen
    return m


def _fabric(name, color, scale=180.0, strength=0.25, rough=0.75, sheen=0.25):
    """Woven cloth: fine noise bump plus slight colour variation."""
    m = _principled(name, color, rough, sheen=sheen)
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = scale
    wave.inputs["Distortion"].default_value = 3.0
    wave.bands_direction = "DIAGONAL"
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 25.0
    mixc = nt.nodes.new("ShaderNodeMix")
    mixc.data_type = "RGBA"
    mixc.inputs["Factor"].default_value = 0.12
    mixc.inputs["A"].default_value = (*color, 1)
    mixc.inputs["B"].default_value = (*(c * 0.6 for c in color), 1)
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = strength
    nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    nt.links.new(wave.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(noise.outputs["Fac"], mixc.inputs["Factor"])
    nt.links.new(mixc.outputs["Result"], p.inputs["Base Color"])
    nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
    return m


# ------------------------------------------------------------------ mesh helpers

def _link(obj, parent=None):
    bpy.context.collection.objects.link(obj)
    if parent:
        obj.parent = parent
        obj.matrix_parent_inverse.identity()
    return obj


def _empty(name, parent=None):
    return _link(bpy.data.objects.new(name, None), parent)


def _smooth_all(me):
    for p in me.polygons:
        p.use_smooth = True


class SkinPart:
    """A skin-modifier mesh following a list of joints (or computed points)."""

    def __init__(self, name, material, nodes, edges, radii, parent, subdiv=2):
        self.nodes = nodes
        me = bpy.data.meshes.new(name)
        me.from_pydata([(0, 0, 0)] * len(nodes), edges, [])
        self.obj = _link(bpy.data.objects.new(name, me), parent)
        self.obj.data.materials.append(material)
        skin = self.obj.modifiers.new("skin", "SKIN")
        skin.use_smooth_shade = True
        skin.branch_smoothing = 0.6
        sub = self.obj.modifiers.new("subd", "SUBSURF")
        sub.levels = subdiv
        sub.render_levels = subdiv
        sv = me.skin_vertices[0].data
        for i, r in enumerate(radii):
            sv[i].radius = r if isinstance(r, tuple) else (r, r)
        sv[0].use_root = True

    def update(self, points):
        me = self.obj.data
        for i, n in enumerate(self.nodes):
            me.vertices[i].co = points[n]
        me.update()


def _mesh_obj(name, verts, faces, material, parent, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    if smooth:
        _smooth_all(me)
    obj = _link(bpy.data.objects.new(name, me), parent)
    obj.data.materials.append(material)
    return obj


def _prim_sphere(name, r, loc, scale, material, parent, segs=24):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=segs // 2, radius=r)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    _smooth_all(me)
    obj = _link(bpy.data.objects.new(name, me), parent)
    obj.data.materials.append(material)
    obj.location = loc
    obj.scale = scale
    return obj


def _prim_box(name, size, loc, material, parent, rot_xyz=(0, 0, 0), bevel=0.006):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = _link(bpy.data.objects.new(name, me), parent)
    obj.data.materials.append(material)
    obj.location = loc
    obj.rotation_euler = rot_xyz
    if bevel:
        b = obj.modifiers.new("bevel", "BEVEL")
        b.width = bevel
        b.segments = 2
        _smooth_all(me)
    return obj


def _lathe(name, profile, material, parent, segs=48, shape=None, cap_top=True):
    """Revolves (radius, height) points about Z. `shape(theta, r, z, i)` may
    return a modified (r, z) per vertex for asymmetric shapes."""
    verts, faces = [], []
    n = len(profile)
    for s in range(segs):
        th = s / segs * math.tau
        for i, (r, z) in enumerate(profile):
            if shape:
                r, z = shape(th, r, z, i)
            verts.append((r * math.cos(th), r * math.sin(th), z))
    for s in range(segs):
        a = s * n
        b = ((s + 1) % segs) * n
        for i in range(n - 1):
            faces.append((a + i, b + i, b + i + 1, a + i + 1))
    if cap_top:
        c = len(verts)
        last = profile[-1]
        verts.append((0, 0, (shape(0, 0, last[1], n - 1)[1] if shape else last[1])))
        for s in range(segs):
            a = s * n + n - 1
            b = ((s + 1) % segs) * n + n - 1
            faces.append((a, b, c))
    return _mesh_obj(name, verts, faces, material, parent)


# ------------------------------------------------------------------ the agent

class Agent:
    def __init__(self, colors):
        self.root = _empty("root")
        self.rig = _empty("rig", self.root)     # whole-body transform (falls, etc.)
        self.attach = {}
        mats = self._materials(colors)
        self._body(mats)
        self._head(mats, colors)
        self._tailoring(mats)
        self._cosh(mats)
        self.pose("idle", 0, 2)

    # ---------------------------------------------------------- materials
    def _materials(self, c):
        coat = c["coat"]
        return {
            "coat": _fabric("coat", coat),
            "coat_dark": _fabric("coat_dark", tuple(x * 0.55 for x in coat), strength=0.15),
            "trousers": _fabric("trousers", (0.06, 0.065, 0.08), scale=260, strength=0.15),
            "skin": _principled("skin", (0.85, 0.6, 0.45), 0.5, sss=0.15),
            "glove": _principled("glove", (0.035, 0.03, 0.03), 0.28, coat=0.4),
            "shoe": _principled("shoe", (0.02, 0.02, 0.022), 0.15, coat=0.8),
            "hat": _fabric("hat", c["hat"], scale=400, strength=0.08, rough=0.85, sheen=0.5),
            "band": _principled("band", c["band"], 0.35, sheen=0.3),
            "lens": _principled("lens", (0.01, 0.012, 0.02), 0.04, metal=0.3, coat=1.0),
            "frame": _principled("frame", (0.02, 0.02, 0.02), 0.3, metal=0.8),
            "brow": _principled("brow", (0.08, 0.05, 0.035), 0.8),
            "hair": _principled("hair", (0.06, 0.04, 0.03), 0.35, coat=0.3),
            "lip": _principled("lip", (0.45, 0.17, 0.13), 0.5),
            "gold": _principled("gold", (1.0, 0.72, 0.25), 0.25, metal=1.0),
            "button": _principled("button", (0.08, 0.06, 0.05), 0.3, coat=0.6),
            "wood": _principled("wood", (0.4, 0.24, 0.13), 0.55),
            "leather": _principled("leather", (0.07, 0.05, 0.04), 0.35, coat=0.3),
        }

    # ---------------------------------------------------------- skinned body
    def _body(self, m):
        self.points = {}
        # Trench coat: torso and flared skirt, plus sleeves.
        self.coat = SkinPart(
            "coat", m["coat"],
            ["coat_neck", "chest", "spine", "pelvis", "skirt", "hem",
             "sh_l", "elbow_l", "wrist_l", "sh_r", "elbow_r", "wrist_r"],
            [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (1, 6), (6, 7), (7, 8), (1, 9), (9, 10), (10, 11)],
            [(0.12, 0.15), (0.165, 0.25), (0.148, 0.212), (0.17, 0.235), (0.195, 0.255), (0.225, 0.28),
             0.1, 0.075, 0.072, 0.1, 0.075, 0.072],
            self.rig)
        # Trousers.
        self.legs = SkinPart(
            "trousers", m["trousers"],
            ["pelvis", "hip_l", "knee_l", "ankle_l", "hip_r", "knee_r", "ankle_r"],
            [(0, 1), (1, 2), (2, 3), (0, 4), (4, 5), (5, 6)],
            [(0.13, 0.2), 0.092, 0.076, 0.062, 0.092, 0.076, 0.062],
            self.rig)
        # Polished shoes with heels and slightly squared toes.
        self.shoes = SkinPart(
            "shoes", m["shoe"],
            ["ankle_l", "toe_l", "heel_l", "ankle_r", "toe_r", "heel_r"],
            [(0, 1), (0, 2), (3, 4), (3, 5)],
            [(0.05, 0.055), (0.045, 0.05), (0.045, 0.048), (0.05, 0.055), (0.045, 0.05), (0.045, 0.048)],
            self.rig)
        # Black leather gloves (a loose fist with a thumb).
        self.gloves = SkinPart(
            "gloves", m["glove"],
            ["wrist_l", "hand_l", "thumb_l", "wrist_r", "hand_r", "thumb_r"],
            [(0, 1), (0, 2), (3, 4), (3, 5)],
            [(0.04, 0.045), (0.042, 0.052), 0.02, (0.04, 0.045), (0.042, 0.052), 0.02],
            self.rig)
        self.neck = SkinPart("neck", m["skin"], ["chest_top", "head_base"], [(0, 1)], [0.058, 0.06], self.rig, 1)

    # ---------------------------------------------------------- head
    def _head(self, m, colors):
        self.attach["head"] = _empty("head_rig", self.rig)
        # Cartoon proportions: a big head reads better at sprite size.
        head = _empty("head_scale", self.attach["head"])
        head.scale = (1.3, 1.3, 1.3)
        head.location = (0, 0, 0.01)

        # Skull: a sphere pushed into a head shape (jaw, chin, cranium).
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=40, v_segments=24, radius=1.0)
        for v in bm.verts:
            d = v.co.copy()
            x, y, z = d.x * 0.142, d.y * 0.13, d.z * 0.168
            if d.z < -0.15:   # jaw narrows, chin juts
                t = (-d.z - 0.15) / 0.85
                y *= 1.0 - 0.32 * t
                x = x * (1.0 - 0.15 * t) + (0.025 * t if d.x > 0 else 0.0)
            if d.x > 0.55 and abs(d.y) > 0.35 and -0.25 < d.z < 0.15:   # cheekbones
                y *= 1.04
            if d.x < -0.2 and d.z > 0.0:   # rounder cranium
                x *= 1.06
            v.co = Vector((x, y, z + 0.05))
        me = bpy.data.meshes.new("skull")
        bm.to_mesh(me)
        bm.free()
        _smooth_all(me)
        skull = _link(bpy.data.objects.new("skull", me), head)
        skull.data.materials.append(m["skin"])

        # The nose: long, bulbous, a little hooked.
        nose = SkinPart("nose", m["skin"], ["a", "b", "c", "d"], [(0, 1), (1, 2), (2, 3)],
                        [0.026, 0.03, 0.038, 0.03], head, 2)
        nose.update({"a": Vector((0.12, 0, 0.08)), "b": Vector((0.17, 0, 0.055)),
                     "c": Vector((0.225, 0, 0.025)), "d": Vector((0.235, 0, 0.0))})
        # Ears.
        for y in (0.13, -0.13):
            _prim_sphere("ear", 1.0, (-0.005, y, 0.045), (0.028, 0.012, 0.045), m["skin"], head)
        # Slicked hair at the back and sides (under the hat).
        hair = _prim_sphere("hair", 1.0, (-0.022, 0, 0.1), (0.135, 0.138, 0.095), m["hair"], head)
        # Heavy eyebrows.
        for s in (1, -1):
            b = SkinPart("brow", m["brow"], ["a", "b", "c"], [(0, 1), (1, 2)], [0.012, 0.015, 0.011], head, 1)
            b.update({"a": Vector((0.128, 0.02 * s, 0.112)), "b": Vector((0.13, 0.065 * s, 0.122)),
                      "c": Vector((0.115, 0.105 * s, 0.112))})
        # A sly smirk.
        mouth = SkinPart("mouth", m["lip"], ["a", "b", "c"], [(0, 1), (1, 2)], [0.007, 0.008, 0.006], head, 1)
        mouth.update({"a": Vector((0.128, 0.045, -0.035)), "b": Vector((0.14, 0.0, -0.045)),
                      "c": Vector((0.128, -0.05, -0.028))})
        # Wraparound sunglasses.
        for s in (1, -1):
            _prim_box("lens", (0.018, 0.062, 0.04), (0.135, 0.05 * s, 0.075), m["lens"], head,
                      (0, 0, math.radians(-12 * s)), 0.012)
            _prim_box("temple", (0.12, 0.008, 0.01), (0.07, 0.112 * s, 0.085), m["frame"], head, (0, 0, 0), 0)
        _prim_box("bridge", (0.012, 0.03, 0.01), (0.145, 0, 0.088), m["frame"], head, (0, 0, 0), 0)

        # Fedora: curved snap brim, pinched crown with a centre dent.
        hat = _empty("hat_rig", head)
        hat.location = (-0.018, 0, 0.18)
        hat.rotation_euler = (0, math.radians(-4), math.radians(4))
        profile = [(0.245, -0.005), (0.235, 0.0), (0.19, 0.006), (0.162, 0.012), (0.158, 0.05),
                   (0.15, 0.115), (0.135, 0.15), (0.1, 0.165), (0.05, 0.145), (0.0, 0.135)]

        def hat_shape(th, r, z, i):
            front = math.cos(th)
            if i <= 2:                       # snap brim: down at the front, up at the back
                z += -0.04 * max(0.0, front) ** 1.5 + 0.03 * max(0.0, -front) ** 1.5 * (1 if i == 0 else 0.6)
            if i >= 5:                       # front pinches
                pinch = max(0.0, front - 0.45) / 0.55
                side = abs(math.sin(th))
                r *= 1.0 - 0.16 * pinch * side
                z -= 0.02 * pinch
            if i >= 7:                       # long centre dent
                z -= 0.015 * (1 - abs(math.sin(th)))
            r *= 1.0 + 0.06 * abs(math.cos(th))   # oval, longer front-to-back
            return r, z

        crown = _lathe("fedora", profile, m["hat"], hat, 48, hat_shape)
        sol = crown.modifiers.new("thick", "SOLIDIFY")
        sol.thickness = 0.008
        sub = crown.modifiers.new("subd", "SUBSURF")
        sub.levels = 1
        sub.render_levels = 2
        band = _lathe("hatband", [(0.163, 0.013), (0.162, 0.05)], m["band"], hat, 48,
                      lambda th, r, z, i: (r * (1.0 + 0.06 * abs(math.cos(th))), z), cap_top=False)
        bs = band.modifiers.new("thick", "SOLIDIFY")
        bs.thickness = 0.006
        _prim_box("bow", (0.02, 0.012, 0.03), (-0.03, 0.168, 0.032), m["band"], hat, (0, 0, 0), 0.004)

    # ---------------------------------------------------------- tailoring
    def _tailoring(self, m):
        chest = _empty("chest_rig", self.rig)
        spine = _empty("spine_rig", self.rig)
        pelvis = _empty("pelvis_rig", self.rig)
        self.attach.update({"chest": chest, "spine": spine, "pelvis": pelvis})
        # Popped collar: a band round the back of the neck, flaring out.
        def collar_shape(th, r, z, i):
            back = -math.cos(th)
            return r * (1.0 + 0.25 * i), z + 0.03 * max(0.0, back)
        verts, faces = [], []
        seg = 24
        for s in range(seg + 1):
            th = math.radians(60 + 240 * s / seg)
            for i, (r, z) in enumerate([(0.105, 0.0), (0.12, 0.07), (0.15, 0.12)]):
                rr, zz = collar_shape(th, r, z, i)
                verts.append((rr * math.cos(th) * 0.95, rr * math.sin(th), zz))
        for s in range(seg):
            for i in range(2):
                a = s * 3 + i
                faces.append((a, a + 3, a + 4, a + 1))
        collar = _mesh_obj("collar", verts, faces, m["coat"], chest)
        collar.location = (0, 0, 0.1)
        collar.modifiers.new("thick", "SOLIDIFY").thickness = 0.014
        # Double-breasted buttons.
        for z in (-0.06, -0.15):
            for y in (0.06, -0.06):
                _prim_sphere("button", 0.016, (0.175, y, z), (1, 1, 1), m["button"], chest, 12)
        # Belt and buckle.
        belt = _lathe("belt", [(0.158, -0.035), (0.158, 0.035)], m["coat_dark"], spine, 40,
                      lambda th, r, z, i: (r * (1.0 if abs(math.sin(th)) < 0.01 else 1.0), z), cap_top=False)
        belt.scale = (1.0, 1.39, 1.0)
        belt.modifiers.new("thick", "SOLIDIFY").thickness = 0.02
        _prim_box("buckle", (0.02, 0.07, 0.055), (0.165, 0, 0), m["gold"], spine, (0, 0, 0), 0.004)

    # ---------------------------------------------------------- cosh
    def _cosh(self, m):
        hand = _empty("hand_r_rig", self.rig)
        self.attach["hand_r"] = hand
        self.cosh = _empty("cosh", hand)
        h = SkinPart("cosh_handle", m["wood"], ["a", "b"], [(0, 1)], [0.022, 0.02], self.cosh, 1)
        h.update({"a": Vector((-0.04, 0, -0.02)), "b": Vector((0.24, 0, -0.02))})
        _prim_sphere("cosh_head", 0.055, (0.3, 0, -0.02), (1.5, 1, 1), m["leather"], self.cosh)

    # ---------------------------------------------------------- posing
    def _set_visible(self, obj, on):
        obj.hide_render = not on
        for c in obj.children_recursive:
            c.hide_render = not on

    def pose(self, anim, i, n):
        a, root, show_cosh = _pose_angles(anim, i, n)
        J = solve(a)
        self.rig.matrix_basis = root
        P = {k: v.to_translation() for k, v in J.items()}
        # Points that aren't joints.
        P["coat_neck"] = (J["chest"] @ Matrix.Translation((0.0, 0, 0.12))).to_translation()
        P["chest_top"] = (J["chest"] @ Matrix.Translation((0.0, 0, 0.1))).to_translation()
        P["head_base"] = (J["head"] @ Matrix.Translation((0.0, 0, -0.02))).to_translation()
        P["skirt"] = (J["pelvis"] @ Matrix.Translation((0.015, 0, -0.24))).to_translation()
        P["hem"] = (J["pelvis"] @ Matrix.Translation((0.03, 0, -0.5))).to_translation()
        P["sh_l"] = (J["shoulder_l"] @ Matrix.Translation((0, -0.02, 0.0))).to_translation()
        P["sh_r"] = (J["shoulder_r"] @ Matrix.Translation((0, 0.02, 0.0))).to_translation()
        for s in ("l", "r"):
            sign = 1 if s == "l" else -1
            P["thumb_" + s] = (J["wrist_" + s] @ Matrix.Translation((0.04, -0.012 * sign, -0.05))).to_translation()
        for part in (self.coat, self.legs, self.shoes, self.gloves, self.neck):
            part.update(P)
        self.attach["head"].matrix_basis = J["head"]
        self.attach["chest"].matrix_basis = J["chest"]
        self.attach["spine"].matrix_basis = J["spine"]
        self.attach["pelvis"].matrix_basis = J["pelvis"]
        self.attach["hand_r"].matrix_basis = J["hand_r"]
        self._set_visible(self.cosh, show_cosh)
        bpy.context.view_layer.update()


def _pose_angles(anim, i, n):
    """Joint angles for frame i of n. Returns (angles, rig matrix, cosh shown)."""
    a = {}
    ph = i / n * math.tau
    root = Matrix.Identity(4)
    cosh = False
    # Relaxed defaults: arms a little out and bent.
    a["shoulder_l"] = rot(side=8)
    a["shoulder_r"] = rot(side=-8)
    a["elbow_l"] = rot(fwd=12)
    a["elbow_r"] = rot(fwd=12)

    if anim == "idle":
        breathe = math.sin(ph)
        a["spine"] = rot(fwd=1.5 * breathe)
        a["shoulder_l"] = rot(side=8 + 2 * breathe)
        a["shoulder_r"] = rot(side=-8 - 2 * breathe)
        a["head"] = rot(twist=6 * breathe)
    elif anim == "walk":
        s = math.sin(ph)
        c = math.cos(ph)
        a["hip_l"] = rot(fwd=30 * s)
        a["hip_r"] = rot(fwd=-30 * s)
        # Knees bend as each leg swings through.
        a["knee_l"] = rot(fwd=-max(0.0, 45 * -c) - 8)
        a["knee_r"] = rot(fwd=-max(0.0, 45 * c) - 8)
        a["ankle_l"] = rot(fwd=10 * s)
        a["ankle_r"] = rot(fwd=-10 * s)
        a["shoulder_l"] = rot(fwd=-26 * s, side=7)
        a["shoulder_r"] = rot(fwd=26 * s, side=-7)
        a["elbow_l"] = rot(fwd=18 + 12 * max(0, -s))
        a["elbow_r"] = rot(fwd=18 + 12 * max(0, s))
        a["pelvis"] = Matrix.Translation((0, 0, -0.03 * abs(s))) @ rot(twist=6 * s, fwd=4)
        a["chest"] = rot(twist=-8 * s)
    elif anim == "run":
        s = math.sin(ph)
        c = math.cos(ph)
        a["hip_l"] = rot(fwd=48 * s)
        a["hip_r"] = rot(fwd=-48 * s)
        a["knee_l"] = rot(fwd=-max(0.0, 85 * -c) - 15)
        a["knee_r"] = rot(fwd=-max(0.0, 85 * c) - 15)
        a["ankle_l"] = rot(fwd=15 * s)
        a["ankle_r"] = rot(fwd=-15 * s)
        a["shoulder_l"] = rot(fwd=-50 * s, side=10)
        a["shoulder_r"] = rot(fwd=50 * s, side=-10)
        a["elbow_l"] = rot(fwd=80)
        a["elbow_r"] = rot(fwd=80)
        a["pelvis"] = Matrix.Translation((0, 0, -0.05 + 0.05 * abs(c))) @ rot(twist=10 * s, fwd=12)
        a["chest"] = rot(twist=-12 * s, fwd=6)
        a["head"] = rot(fwd=-10)
    elif anim == "crawl":
        # On hands and knees: body tipped forward to horizontal, thighs
        # straight down, shins back along the floor, arms reaching ahead.
        sw = math.sin(ph)
        root = (Matrix.Translation((-1.25, 0, 0.47 + 0.015 * abs(math.cos(ph))))
                @ Matrix.Rotation(math.radians(90), 4, "Y"))
        a["hip_l"] = rot(fwd=90 + 16 * sw, side=4)
        a["hip_r"] = rot(fwd=90 - 16 * sw, side=-4)
        a["knee_l"] = rot(fwd=-95)
        a["knee_r"] = rot(fwd=-95)
        a["shoulder_l"] = rot(fwd=128 - 16 * sw, side=6)
        a["shoulder_r"] = rot(fwd=128 + 16 * sw, side=-6)
        a["elbow_l"] = rot(fwd=-6)
        a["elbow_r"] = rot(fwd=-6)
        a["head"] = rot(fwd=-62)
    elif anim == "victory":
        # Hopping fist-pumps.
        k = math.sin(ph)
        hop = max(0.0, math.sin(ph * 2)) * 0.08
        root = Matrix.Translation((0, 0, hop))
        # (With the arm raised, a positive side angle swings it out to the right.)
        a["shoulder_r"] = rot(fwd=135 + 10 * k, side=62)
        a["elbow_r"] = rot(fwd=25 + 25 * max(0.0, -k))
        a["shoulder_l"] = rot(fwd=25, side=35)
        a["elbow_l"] = rot(fwd=95)
        a["hip_l"] = rot(fwd=10 * k)
        a["knee_l"] = rot(fwd=-20 * max(0.0, k))
        a["head"] = rot(fwd=-12, twist=10 * k)
        a["chest"] = rot(twist=8 * k, fwd=-6)
    elif anim == "search":
        wig = math.sin(ph)
        a["spine"] = rot(fwd=18)
        a["chest"] = rot(fwd=12)
        a["head"] = rot(fwd=15)
        a["hip_l"] = rot(fwd=12)
        a["hip_r"] = rot(fwd=-6)
        a["knee_l"] = rot(fwd=-20)
        a["knee_r"] = rot(fwd=-10)
        a["shoulder_l"] = rot(fwd=60 + 18 * wig, side=6)
        a["shoulder_r"] = rot(fwd=60 - 18 * wig, side=-6)
        a["elbow_l"] = rot(fwd=35 - 15 * wig)
        a["elbow_r"] = rot(fwd=35 + 15 * wig)
    elif anim == "swing":
        cosh = True
        k = i / max(1, n - 1)
        a["chest"] = rot(twist=-25 + 45 * k, fwd=-6 + 16 * k)
        a["shoulder_r"] = rot(fwd=-140 + 230 * k, side=-12)
        a["elbow_r"] = rot(fwd=70 - 60 * k)
        a["shoulder_l"] = rot(fwd=30 - 50 * k, side=14)
        a["hip_l"] = rot(fwd=18)
        a["hip_r"] = rot(fwd=-14)
        a["knee_l"] = rot(fwd=-12)
    elif anim == "hurt":
        a["spine"] = rot(fwd=-12)
        a["chest"] = rot(fwd=-10)
        a["head"] = rot(fwd=-22, twist=12)
        a["shoulder_l"] = rot(fwd=35, side=55)
        a["shoulder_r"] = rot(fwd=35, side=-55)
        a["elbow_l"] = rot(fwd=40)
        a["elbow_r"] = rot(fwd=40)
        a["hip_l"] = rot(fwd=14)
        a["knee_l"] = rot(fwd=-18)
    elif anim == "down":
        # Flat on the back, arms flung wide, one knee up.
        root = Matrix.Translation((0.88, 0, 0.17)) @ Matrix.Rotation(math.radians(-88), 4, "Y")
        a["shoulder_l"] = rot(side=80, fwd=10)
        a["shoulder_r"] = rot(side=-80, fwd=10)
        a["elbow_l"] = rot(fwd=30)
        a["elbow_r"] = rot(fwd=50)
        a["hip_l"] = rot(fwd=35, side=6)
        a["knee_l"] = rot(fwd=-60)
        a["hip_r"] = rot(side=-8)
        a["head"] = rot(twist=30)
    return a, root, cosh
