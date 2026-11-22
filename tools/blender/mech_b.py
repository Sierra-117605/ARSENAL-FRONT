"""案Bの装甲と駆動系。座標は左右 X、前方 +Y、高さ Z（Godot では前方 -Z）。"""
from math import cos, sin, tau, radians
from pathlib import Path

import bpy

bpy.ops.wm.read_factory_settings(use_empty=True)


def finish(name, color, metallic, roughness, glow=0):
    # 線形色で塗装・鋳物・切削面・光学窓を分ける。
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Emission Color"].default_value = (*color, 1)
    shader.inputs["Emission Strength"].default_value = glow
    return mat


materials = [
    finish("Armor", (.19, .225, .145), .35, .46),
    finish("Ceramic", (.32, .32, .24), .32, .48),
    finish("Graphite", (.046, .054, .052), .5, .43),
    finish("Titanium", (.27, .29, .26), .77, .32),
    finish("Optic", (1, .27, .025), .2, .27, 2),
]
ARMOR, PALE, DARK, STEEL, LENS = range(len(materials))


class Part:
    """閉じた断面をつないで作った装甲・軸を部位ひとつにまとめる。"""

    def __init__(self, name, origin):
        self.name = name
        self.origin = origin
        self.vertices = []
        self.faces = []
        self.slots = []

    def loft(self, rings, slot):
        start = len(self.vertices)
        count = len(rings[0])
        for ring in rings:
            self.vertices.extend(ring)
        faces = [tuple(reversed(range(start, start + count)))]
        for level in range(len(rings) - 1):
            lower = start + level * count
            for i in range(count):
                j = (i + 1) % count
                faces.append((lower+i, lower+j, lower+j+count, lower+i+count))
        top = start + (len(rings)-1)*count
        faces.append(tuple(range(top, top+count)))
        self.faces.extend(faces)
        self.slots.extend([slot]*len(faces))

    def shell(self, slot, *sections):
        # 各段の中心・幅・奥行きをずらし、胸や脛の外板に折れ面を作る。
        rings = []
        for z, x, y, w, d in sections:
            a, b = w/2, d/2
            rings.append([(x+i*a, y+j*b, z) for i, j in
                          [(-.59,-1),(.59,-1),(1,-.57),(1,.40),
                           (.50,1),(-.50,1),(-1,.40),(-1,-.57)]])
        self.loft(rings, slot)

    def axle(self, slot, x, y, z, radius, length, axis="x"):
        rings = []
        for end in [-length/2, length/2]:
            ring = []
            for i in range(16):
                a, b = radius*cos(tau*i/16), radius*sin(tau*i/16)
                offset = {"x": (end,a,b), "y": (b,end,a), "z": (a,b,end)}[axis]
                ring.append(tuple(p+v for p,v in zip((x,y,z),offset)))
            rings.append(ring)
        self.loft(rings, slot)

    def build(self, bevel=.032):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.location = self.origin
        for mat in materials:
            mesh.materials.append(mat)
        for face, slot in zip(mesh.polygons, self.slots):
            face.material_index = slot
            face.use_smooth = True
        # 広い面の向きを保ちつつ、面取りの帯に光が乗るようにする。
        edge = obj.modifiers.new("面取り", "BEVEL")
        edge.width = bevel
        edge.segments = 3
        edge.harden_normals = True
        normals = obj.modifiers.new("面積で重みづけした法線", "WEIGHTED_NORMAL")
        normals.keep_sharp = True
        return obj


torso = Part("Torso", (0,0,3.09))
torso.shell(DARK, (-.65,0,0,.83,.70),(-.32,0,0,1.18,.86),(.32,0,-.03,1.82,1.14),(.61,0,-.05,1.35,.79))
for s in [-1,1]:
    # 左右に割れた胸甲は中央へせり出し、脇へ鋭く絞る。
    torso.shell(ARMOR, (-.26,.27*s,.31,.39,.48),(.20,.48*s,.30,.88,.74),(.54,.48*s,.07,.86,.86),(.63,.45*s,.01,.56,.54))
    torso.shell(PALE, (.17,.47*s,.53,.64,.28),(.30,.49*s,.50,.76,.36),(.39,.49*s,.44,.7,.3))
    torso.axle(STEEL, .91*s,0,.27,.18,.64)
for i in range(3):
    torso.shell(STEEL, (-.55+i*.11,0,.32,.54,.18),(-.50+i*.11,0,.37,.56,.20))
torso.build(.045)

hip = Part("Hip",(0,0,2.11))
hip.shell(DARK,(-.19,0,0,1,.7),(.19,0,0,.84,.6))
for s in [-1,1]:
    hip.shell(ARMOR,(-.41,s*.46,.29,.34,.26),(-.10,s*.43,.26,.55,.44),(.14,s*.34,.17,.48,.45))
hip.build()

head = Part("Head",(0,.10,4.02))
head.shell(DARK,(-.23,0,.0,.32,.52),(-.06,0,.04,.56,.73),(.15,0,0,.50,.61))
head.shell(ARMOR,(.00,0,.06,.60,.81),(.13,0,.02,.59,.76),(.23,0,-.10,.38,.48))
head.axle(STEEL,-.26,-.12,.18,.035,.39,"z")
head.build(.022)
visor = Part("Visor",(0,.52,3.95))
visor.shell(DARK,(-.075,0,0,.39,.10),(.05,0,.01,.49,.12))
visor.shell(LENS,(-.035,-.035,.06,.28,.035),(.017,-.026,.062,.34,.04))
visor.build(.02)

for s, suffix in [(-1,"L"),(1,"R")]:
    shoulder = Part("Shoulder"+suffix,(s*1.6,0,3.42))
    shoulder.axle(DARK,-s*.23,0,0,.29,.83)
    shoulder.axle(STEEL,s*.18,0,0,.21,.10)
    shoulder.shell(ARMOR,(-.21,s*.23,0,.63,.82),(.05,s*.20,.02,1.03,1.22),(.39,-s*.06,-.04,.68,.76),(.45,-s*.14,-.13,.45,.52))
    shoulder.shell(PALE,(-.27,s*.30,.08,.53,.73),(-.10,s*.34,.03,.72,.92),(-.045,s*.30,.01,.66,.88))
    shoulder.build(.04)

    arm = Part("Arm"+suffix,(s*1.3,0,2.35))
    arm.shell(DARK,(-.72,0,.02,.29,.33),(-.41,0,.02,.32,.36),(.63,0,0,.30,.30))
    arm.shell(ARMOR,(.11,0,.01,.29,.35),(.51,s*.04,0,.46,.48),(.66,s*.04,-.04,.40,.36))
    arm.axle(STEEL,0,0,.025,.16,.44)
    arm.shell(ARMOR,(-.57,s*.025,.07,.36,.42),(-.23,s*.06,.11,.49,.57),(-.06,s*.045,.06,.41,.44))
    arm.shell(STEEL,(-.82,0,.05,.29,.30),(-.64,0,.07,.34,.34))
    arm.build()

    leg = Part("Leg"+suffix,(s*.55,0,1.05))
    leg.shell(DARK,(-.94,0,-.03,.28,.37),(-.29,0,-.02,.40,.50),(.12,0,0,.31,.45),(.94,0,0,.42,.54))
    leg.shell(ARMOR,(.12,0,.07,.40,.52),(.54,s*.06,.04,.65,.73),(.87,s*.03,-.04,.54,.61))
    leg.axle(DARK,0,.025,0,.21,.64)
    leg.axle(STEEL,s*.32,.025,0,.146,.07)
    leg.shell(PALE,(-.18,0,.23,.28,.37),(.02,0,.28,.49,.51),(.15,0,.19,.39,.38))
    leg.shell(ARMOR,(-.89,0,.045,.34,.47),(-.45,s*.04,.08,.57,.67),(-.19,s*.04,.085,.60,.74),(-.11,s*.04,.00,.49,.48))
    leg.axle(STEEL,s*.19,-.24,-.53,.066,.77,"z")
    leg.build(.036)

    foot = Part("Foot"+suffix,(s*.55,.15,.15))
    foot.shell(DARK,(-.15,0,.07,.78,1.42),(-.065,0,.08,.8,1.42))
    foot.shell(ARMOR,(-.06,0,.12,.77,1.36),(.057,0,.14,.69,1.24),(.16,0,-.08,.48,.65))
    foot.shell(PALE,(-.035,0,.62,.57,.30),(.055,0,.57,.47,.29))
    foot.build(.024)

pack = Part("BackPack",(0,-.90,3.14))
pack.shell(DARK,(-.65,0,0,.75,.58),(.55,0,0,1,.74))
for s in [-1,1]:
    pack.shell(ARMOR,(-.80,s*.62,-.05,.42,.61),(-.44,s*.62,-.11,.62,.83),(.42,s*.55,.02,.61,.78),(.82,s*.54,-.12,.42,.58))
    pack.axle(STEEL,s*.60,-.41,-.42,.22,.32,"y")
    pack.axle(DARK,s*.60,-.58,-.42,.17,.04,"y")
    for i in range(4):
        pack.shell(STEEL,(-.04+i*.12,s*.54,-.36,.38,.12),(.02+i*.12,s*.54,-.39,.40,.16))
pack.build()

barrel = Part("Barrel",(1.3,.60,1.75))
barrel.axle(DARK,0,0,0,.12,1.60,"z")
barrel.shell(ARMOR,(-.29,0,0,.25,.29),(.37,0,0,.36,.40),(.78,0,0,.33,.37))
barrel.axle(STEEL,0,0,-.62,.146,.25,"z")
barrel.axle(DARK,0,0,-.76,.137,.10,"z")
barrel.build(.02).rotation_euler.x = radians(90)

# Blender の原点は組み立て時の位置。Godot は各部位のローカル頂点のみ使う。
destination = Path(__file__).resolve().parents[2] / "assets/models/mech_b.glb"
destination.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(destination), export_format="GLB", export_apply=True)
