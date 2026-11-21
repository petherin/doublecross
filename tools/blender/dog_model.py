"""Nacho: a scruffy, wire-coated apricot hound (think Spinone), built and
posed in code like the agents.

The body, legs and tail are "skin" meshes over a stick skeleton (Blender's
Skin + Subdivision modifiers), roughened by a displacement so the coat looks
wiry and tousled. The head (skull, long muzzle, beard, brown nose, amber
eyes, long feathered ears and a lower jaw that opens to bark) rides on an
empty that follows the neck. A red collar sits round the neck.

Nacho faces +X, with +Y to his left and +Z up. One unit is a metre; he
stands about 0.62 m at the shoulder.
"""
import math

import bpy
from mathutils import Matrix, Vector

import agent_model as AM

# Linear colours (Blender's), i.e. sRGB ~ #d98c4d ginger, #edc28c pale.
COAT = (0.76, 0.36, 0.13)       # apricot / ginger
COAT_LIGHT = (0.9, 0.62, 0.34)  # paler chest, legs and beard
NOSE = (0.34, 0.13, 0.11)       # liver-brown nose
EYE = (0.2, 0.06, 0.012)        # amber-brown eyes

# Animation name -> frame count (see pose()).
ANIMS = [("idle", 2), ("walk", 8), ("sniff", 4), ("sit", 2), ("bark", 4), ("growl", 2), ("bite", 3), ("poo", 2)]


def _fur(name, color, light):
    """A coat material: two tones mottled by noise, with a wiry bump."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.85
    try:
        p.inputs["Sheen Weight"].default_value = 0.6
        p.inputs["Sheen Tint"].default_value = (*light, 1.0)
    except KeyError:
        pass
    tc = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 9.0
    noise.inputs["Detail"].default_value = 6.0
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (*color, 1.0)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (*light, 1.0)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], p.inputs["Base Color"])
    # Fine curly strands.
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "RINGS"
    wave.inputs["Scale"].default_value = 60.0
    wave.inputs["Distortion"].default_value = 18.0
    wave.inputs["Detail"].default_value = 4.0
    nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.45
    nt.links.new(wave.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
    return m


def _scruff(obj, strength=0.022, size=0.06):
    """Roughens a mesh's outline into a tousled, wiry coat."""
    tex = bpy.data.textures.new(obj.name + "_scruff", "CLOUDS")
    tex.noise_scale = size
    tex.noise_depth = 2
    d = obj.modifiers.new("scruff", "DISPLACE")
    d.texture = tex
    d.strength = strength
    d.mid_level = 0.5
    d.texture_coords = "LOCAL"


def _hair(obj, material, count, length, curl=0.6):
    """Real rendered hair: a wiry, curly coat over the mesh."""
    mod = obj.modifiers.new("hair", "PARTICLE_SYSTEM")
    ps = mod.particle_system.settings
    ps.type = "HAIR"
    ps.use_advanced_hair = True
    ps.count = count
    ps.hair_length = length
    ps.emit_from = "FACE"
    ps.use_modifier_stack = True
    ps.child_type = "INTERPOLATED"
    ps.child_percent = 2
    ps.rendered_child_count = 3
    ps.clump_factor = 0.55
    ps.roughness_1 = 0.03
    ps.roughness_1_size = 0.6
    ps.roughness_endpoint = 0.02
    ps.kink = "CURL"
    ps.kink_amplitude = 0.006 * curl
    ps.kink_frequency = 3.0
    ps.root_radius = 0.0028
    ps.tip_radius = 0.001
    ps.radius_scale = 1.0
    ps.use_hair_bspline = True
    ps.display_step = 3
    ps.render_step = 4
    obj.data.materials.append(material)
    ps.material = len(obj.data.materials)
    return ps


def _ellipsoid(name, r, loc, scale, material, parent, rot=(0, 0, 0)):
    o = AM._prim_sphere(name, r, loc, scale, material, parent)
    o.rotation_euler = rot
    return o


class Dog:
    def __init__(self):
        self.root = AM._empty("dog_root")
        self.rig = AM._empty("dog_rig", self.root)
        coat = _fur("coat", COAT, COAT_LIGHT)
        pale = _fur("pale", COAT_LIGHT, (0.97, 0.85, 0.68))
        self.m = {
            "coat": coat, "pale": pale,
            "nose": AM._principled("nose", NOSE, 0.45, coat=0.2),
            "eye": AM._principled("eye", EYE, 0.05, coat=1.0),
            "pupil": AM._principled("pupil", (0.01, 0.01, 0.01), 0.05, coat=1.0),
            "mouth": AM._principled("mouth", (0.25, 0.06, 0.07), 0.4),
            "tongue": AM._principled("tongue", (0.85, 0.35, 0.38), 0.35, sss=0.2),
            "teeth": AM._principled("teeth", (0.95, 0.93, 0.85), 0.3),
            "collar": AM._principled("collar", (0.75, 0.05, 0.06), 0.4, sheen=0.3),
            "buckle": AM._principled("buckle", (0.8, 0.75, 0.6), 0.25, metal=1.0),
        }
        self._body()
        self._head()
        # One collection, so the renderer can leave the ink lines off: the
        # hair gives Nacho his outline, and lines would show the body under it.
        self.collection = bpy.data.collections.new("dog")
        bpy.context.scene.collection.children.link(self.collection)
        for o in list(bpy.data.objects):
            if o.type in ("MESH", "CURVE") and o.name not in ("cam",):
                for c in list(o.users_collection):
                    c.objects.unlink(o)
                self.collection.objects.link(o)
        self.pose("idle", 0, 2)

    # ---------------------------------------------------------- build
    def _body(self):
        m = self.m
        hair = _fur("hair", COAT, COAT_LIGHT)
        self.hair_mat = hair
        self.torso = AM.SkinPart(
            "torso", m["coat"],
            ["rump", "hip", "mid", "chest", "brisket", "neck", "head_base"],
            [(0, 1), (1, 2), (2, 3), (3, 4), (3, 5), (5, 6)],
            [(0.12, 0.13), (0.15, 0.16), (0.15, 0.165), (0.17, 0.18), (0.12, 0.11), (0.11, 0.11), (0.095, 0.095)],
            self.rig)
        _scruff(self.torso.obj, 0.025, 0.06)
        _hair(self.torso.obj, hair, 1100, 0.038)
        # Each leg is its own skin mesh (a skin needs one root per piece).
        self.legs = []
        for names, radii in (
                (["sh_l", "elbow_l", "wrist_l", "paw_l"], [0.07, 0.05, 0.04, (0.048, 0.042)]),
                (["sh_r", "elbow_r", "wrist_r", "paw_r"], [0.07, 0.05, 0.04, (0.048, 0.042)]),
                (["hp_l", "stifle_l", "hock_l", "hpaw_l"], [0.095, 0.065, 0.04, (0.048, 0.042)]),
                (["hp_r", "stifle_r", "hock_r", "hpaw_r"], [0.095, 0.065, 0.04, (0.048, 0.042)])):
            leg = AM.SkinPart("leg", m["coat"], names, [(0, 1), (1, 2), (2, 3)], radii, self.rig)
            _scruff(leg.obj, 0.015, 0.05)
            _hair(leg.obj, hair, 200, 0.03)
            self.legs.append(leg)
        self.tail = AM.SkinPart(
            "tail", m["coat"],
            ["t0", "t1", "t2", "t3", "t4", "t5"],
            [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5)],
            [0.04, 0.042, 0.04, 0.036, 0.03, 0.018],
            self.rig)
        _hair(self.tail.obj, hair, 220, 0.045)
        # The red collar round the neck.
        bpy.ops.mesh.primitive_torus_add(major_radius=0.125, minor_radius=0.022, major_segments=32,
                                         minor_segments=8)
        self.collar = bpy.context.object
        self.collar.name = "collar"
        self.collar.data.materials.append(m["collar"])
        AM._smooth_all(self.collar.data)
        self.collar_at = AM._empty("collar_at", self.rig)
        self.collar.parent = self.collar_at
        AM._prim_sphere("tag", 0.018, (0.0, 0.0, -0.135), (1, 0.4, 1.2), m["buckle"], self.collar_at)

    def _head(self):
        m = self.m
        hair = self.hair_mat
        self.head = AM._empty("head", self.rig)
        h = self.head
        h.scale = (1.2, 1.2, 1.2)
        skull = _ellipsoid("skull", 0.1, (0.0, 0, 0.04), (1.2, 0.95, 0.92), m["coat"], h)
        _hair(skull, hair, 220, 0.028)
        # Shaggy brows over the eyes.
        for s in (1, -1):
            brow = _ellipsoid("brow", 0.042, (0.08, 0.045 * s, 0.085), (1.0, 0.9, 0.5), m["pale"], h)
            _hair(brow, hair, 30, 0.025, curl=1.0)
        muzzle = _ellipsoid("muzzle", 0.075, (0.17, 0, -0.005), (1.6, 0.82, 0.8), m["pale"], h)
        _hair(muzzle, hair, 140, 0.02)
        # The beard and moustache hang below and beside the muzzle.
        beard = _ellipsoid("beard", 0.06, (0.19, 0, -0.065), (1.3, 0.95, 0.95), m["pale"], h)
        _hair(beard, hair, 150, 0.045, curl=1.2)
        _ellipsoid("nose", 0.029, (0.285, 0, 0.012), (0.8, 1.1, 0.8), m["nose"], h)
        for s in (1, -1):
            _ellipsoid("eye", 0.022, (0.108, 0.06 * s, 0.055), (0.8, 1, 1), m["eye"], h)
            _ellipsoid("pupil", 0.012, (0.124, 0.062 * s, 0.056), (0.6, 1, 1), m["pupil"], h)
        # Long, feathered ears hanging from the top of the head.
        self.ears = []
        for s in (1, -1):
            pivot = AM._empty("ear_pivot", h)
            pivot.location = (0.0, 0.085 * s, 0.07)
            ear = _ellipsoid("ear", 0.11, (-0.01, 0.025 * s, -0.12), (0.6, 0.22, 1.35), m["coat"], pivot)
            _hair(ear, hair, 110, 0.035, curl=1.3)
            self.ears.append((pivot, s))
        # The lower jaw (with tongue) hinges open to bark.
        self.jaw = AM._empty("jaw", h)
        self.jaw.location = (0.06, 0, -0.035)
        AM._prim_sphere("mouth", 0.05, (0.1, 0, -0.005), (1.6, 0.75, 0.35), m["mouth"], self.jaw)
        AM._prim_sphere("tongue", 0.035, (0.12, 0, 0.002), (1.6, 0.8, 0.3), m["tongue"], self.jaw)
        for s in (1, -1):
            AM._prim_sphere("fang", 0.009, (0.19, 0.025 * s, 0.012), (0.8, 0.8, 1.6), m["teeth"], self.jaw)
        lower = _ellipsoid("lower", 0.06, (0.11, 0, -0.03), (1.5, 0.75, 0.55), m["pale"], self.jaw)
        _hair(lower, hair, 60, 0.035, curl=1.2)

    # ---------------------------------------------------------- posing
    def pose(self, anim, i, n):
        p = _pose_params(anim, i, n)
        pts = _skeleton(p)
        self.torso.update(pts)
        for leg in self.legs:
            leg.update(pts)
        self.tail.update(pts)
        # Head: placed at the end of the neck, pitched and turned.
        self.head.location = pts["head_base"]
        self.head.rotation_euler = (0.0, math.radians(p["head_pitch"]), math.radians(p["head_yaw"]))
        self.jaw.rotation_euler = (0.0, math.radians(p["jaw"]), 0.0)
        for pivot, s in self.ears:
            pivot.rotation_euler = (math.radians(p["ear_flap"] * s), math.radians(p["ear_swing"]), 0.0)
        # Collar round the neck, square to it.
        neck_dir = (pts["head_base"] - pts["neck"]).normalized()
        self.collar_at.location = pts["neck"].lerp(pts["head_base"], 0.25)
        self.collar_at.rotation_euler = neck_dir.to_track_quat("Z", "X").to_euler()
        self.rig.location = (p["lunge"], 0.0, 0.0)


def _pose_params(anim, i, n):
    """Pose controls for frame i of n of an animation."""
    t = i / max(1, n)
    w = math.sin(t * math.tau)
    p = {
        "gait": 0.0, "stride": 0.0, "sit": 0.0, "crouch": 0.0, "lunge": 0.0,
        "head_pitch": -8.0, "head_yaw": 0.0, "jaw": 0.0,
        "tail_up": 35.0, "tail_wag": 0.0, "ear_flap": 0.0, "ear_swing": 0.0, "breath": 0.0,
        "head_low": 0.0, "squat": 0.0,
    }
    if anim == "idle":
        p["breath"] = 0.008 * w
        p["tail_wag"] = 12.0 * w
    elif anim == "walk":
        p["gait"] = t * math.tau
        p["stride"] = 1.0
        p["tail_wag"] = 18.0 * math.sin(t * math.tau * 2)
        p["head_pitch"] = -4.0 + 3.0 * math.sin(t * math.tau * 2)
        p["ear_swing"] = 8.0 * math.sin(t * math.tau * 2)
    elif anim == "sniff":
        # Nose to the floor, snuffling from side to side.
        p["head_low"] = 1.0
        p["head_pitch"] = 45.0
        p["head_yaw"] = 22.0 * w
        p["crouch"] = 0.05
        p["tail_wag"] = 20.0 * math.cos(t * math.tau)
        p["tail_up"] = 25.0
        p["ear_flap"] = 6.0
    elif anim == "sit":
        p["sit"] = 1.0
        p["head_pitch"] = -14.0 + 3.0 * w
        p["tail_up"] = -60.0
    elif anim == "bark":
        # Head up, mouth snapping open, tail going like the clappers.
        p["head_pitch"] = -24.0
        p["jaw"] = 34.0 if i % 2 == 0 else 6.0
        p["tail_wag"] = 34.0 * (1 if i % 2 == 0 else -1)
        p["tail_up"] = 55.0
        p["ear_flap"] = 10.0 if i % 2 == 0 else 0.0
        p["crouch"] = 0.02 if i % 2 == 0 else 0.0
    elif anim == "growl":
        # Hackles up, front down, head low and forward, lip curled.
        p["crouch"] = 0.12
        p["head_pitch"] = 12.0
        p["jaw"] = 12.0 + 3.0 * w
        p["tail_up"] = 5.0
        p["tail_wag"] = 3.0 * w
        p["ear_flap"] = -8.0
    elif anim == "poo":
        # Hunched over, straining, tail up out of the way.
        p["squat"] = 1.0
        p["strain"] = 0.02 * i
        p["head_pitch"] = -10.0 + 5.0 * i
        p["tail_up"] = 78.0
        p["ear_flap"] = 4.0 * i
    elif anim == "bite":
        k = [0.0, 1.0, 0.4][i % 3]
        p["lunge"] = 0.16 * k
        p["crouch"] = 0.08 * (1.0 - k)
        p["head_pitch"] = 4.0 - 10.0 * k
        p["jaw"] = 40.0 * k
        p["tail_up"] = 20.0
    return p


def _limb(top, segs, angles):
    """Points down a leg from `top`: each segment a length hanging at an angle
    (degrees, +ve swings the lower end forward, towards +X)."""
    out = [Vector(top)]
    for length, a in zip(segs, angles):
        r = math.radians(a)
        out.append(out[-1] + Vector((length * math.sin(r), 0.0, -length * math.cos(r))))
    return out


def _skeleton(p):
    """Every skeleton point for the pose controls `p`."""
    sit = p["sit"]
    crouch = p["crouch"]
    breath = p["breath"]
    if sit > 0.0:
        return _sitting(p)
    if p["squat"] > 0.0:
        return _squatting(p)
    hip_z = 0.56
    chest_z = 0.58 - crouch
    pts = {
        "rump": Vector((-0.42, 0, hip_z - 0.01)),
        "hip": Vector((-0.3, 0, hip_z)),
        "mid": Vector((-0.04, 0, (hip_z + chest_z) / 2 + 0.005 + breath)),
        "chest": Vector((0.2, 0, chest_z)),
        "brisket": Vector((0.25, 0, chest_z - 0.15)),
        "neck": Vector((0.31, 0, chest_z + 0.1)),
        "head_base": Vector((0.4, 0, chest_z + 0.26 - 0.8 * crouch)),
    }
    # Nose to the ground: the neck stretches forward and down.
    low = p["head_low"]
    pts["neck"] = pts["neck"].lerp(Vector((0.36, 0, chest_z - 0.02)), low)
    pts["head_base"] = pts["head_base"].lerp(Vector((0.5, 0, 0.26)), low)
    g = p["gait"]
    stride = p["stride"]
    for side, y in (("l", 0.095), ("r", -0.095)):
        # Trot: diagonal pairs move together (left front with right hind).
        ph = g + (0.0 if side == "l" else math.pi)
        swing = 24.0 * stride * math.sin(ph)
        lift = max(0.0, math.cos(ph)) * stride
        fz = chest_z - 0.06
        k = crouch / 0.12
        front = _limb((0.21, y, fz), [0.22, 0.2, 0.1],
                      [swing - 22.0 * k, swing - 30.0 * lift + 26.0 * k, swing + 10.0 * lift])
        for n, name in enumerate(("sh_", "elbow_", "wrist_", "paw_")):
            pts[name + side] = front[n]
        hswing = 22.0 * stride * math.sin(ph + math.pi)
        hlift = max(0.0, math.cos(ph + math.pi)) * stride
        hz = hip_z - 0.05
        hind = _limb((-0.3, y, hz), [0.22, 0.2, 0.14],
                     [hswing + 22.0, hswing - 32.0 + 20.0 * hlift, hswing + 6.0 - 25.0 * hlift])
        for n, name in enumerate(("hp_", "stifle_", "hock_", "hpaw_")):
            pts[name + side] = hind[n]
    _ground(pts)
    _tail(pts, p)
    return pts


def _sitting(p):
    """Sitting up, front legs straight, haunches folded under (like the
    photo by the sofa)."""
    pts = {
        "rump": Vector((-0.24, 0, 0.12)),
        "hip": Vector((-0.17, 0, 0.2)),
        "mid": Vector((-0.04, 0, 0.38)),
        "chest": Vector((0.1, 0, 0.56)),
        "brisket": Vector((0.17, 0, 0.44)),
        "neck": Vector((0.16, 0, 0.7)),
        "head_base": Vector((0.21, 0, 0.84)),
    }
    for side, y in (("l", 0.095), ("r", -0.095)):
        pts["sh_" + side] = Vector((0.13, y, 0.5))
        pts["elbow_" + side] = Vector((0.15, y, 0.3))
        pts["wrist_" + side] = Vector((0.16, y, 0.1))
        pts["paw_" + side] = Vector((0.2, y, 0.03))
        pts["hp_" + side] = Vector((-0.15, y * 1.2, 0.2))
        pts["stifle_" + side] = Vector((0.03, y * 1.4, 0.15))
        pts["hock_" + side] = Vector((-0.16, y * 1.3, 0.05))
        pts["hpaw_" + side] = Vector((0.02, y * 1.3, 0.03))
    _tail(pts, p)
    return pts


def _squatting(p):
    """Squatting to go: rump hovering over the floor, back arched, hind legs
    folded forward under him, front legs braced."""
    strain = p.get("strain", 0.0)
    pts = {
        "rump": Vector((-0.33, 0, 0.24)),
        "hip": Vector((-0.23, 0, 0.33)),
        "mid": Vector((-0.02, 0, 0.56 + strain)),
        "chest": Vector((0.2, 0, 0.58)),
        "brisket": Vector((0.25, 0, 0.44)),
        "neck": Vector((0.31, 0, 0.68)),
        "head_base": Vector((0.4, 0, 0.82 - strain)),
    }
    for side, y in (("l", 0.095), ("r", -0.095)):
        front = _limb((0.21, y, 0.52), [0.22, 0.2, 0.1], [4.0, -6.0, 2.0])
        for n, name in enumerate(("sh_", "elbow_", "wrist_", "paw_")):
            pts[name + side] = front[n]
        pts["hp_" + side] = Vector((-0.22, y * 1.15, 0.3))
        pts["stifle_" + side] = Vector((-0.04, y * 1.3, 0.2))
        pts["hock_" + side] = Vector((-0.2, y * 1.25, 0.07))
        pts["hpaw_" + side] = Vector((-0.06, y * 1.25, 0.03))
    _ground(pts)
    _tail(pts, p)
    return pts


def _ground(pts):
    """Keeps every paw on (or above) the floor."""
    for side in ("l", "r"):
        for name in ("paw_", "hpaw_"):
            pts[name + side].z = max(pts[name + side].z, 0.03)


def _tail(pts, p):
    """From the rump, curving up and back, wagging side to side."""
    base = pts["rump"] + Vector((-0.02, 0, 0.03))
    up = math.radians(p["tail_up"])
    wag = math.radians(p["tail_wag"])
    d = Vector((-math.cos(up), 0.0, math.sin(up)))
    d = Matrix.Rotation(wag, 3, "Z") @ d
    pts["t0"] = base
    cur = base
    for k in range(1, 6):
        # Each segment curls a little more upward (the tail's natural sweep).
        axis = Matrix.Rotation(wag, 3, "Z") @ Vector((0, 1, 0))
        d = (Matrix.Rotation(math.radians(-9.0 * k), 3, axis) @ d).normalized()
        cur = cur + d * 0.085
        pts["t%d" % k] = cur
