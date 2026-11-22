"""案Bの装甲と駆動系。座標は左右 X、前方 +Y、高さ Z（Godot では前方 -Z）。"""
import argparse
import sys
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
    finish("Armor", (.19, .225, .145), .04, .88),
    finish("Ceramic", (.32, .32, .24), .06, .84),
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

    def ridged_plate(self, slot, *sections):
        # 前面の左右を峰で折り、横一枚だった装甲に別々の向きの反射面を作る。
        rings = []
        for z, x, y, width, depth, ridge in sections:
            w, d = width/2, depth/2
            rings.append([(x+u*w, y+v*d, z) for u, v in
                          [(-.65,-1),(.65,-1),(1,-.4),(1,.42),(.66,.88),
                           (0,1+ridge/d),(-.66,.88),(-1,.42),(-1,-.4)]])
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
    torso.ridged_plate(PALE, (.23,.47*s,.52,.68,.34,.075),
                       (.32,.49*s,.49,.78,.37,.095),(.42,.49*s,.43,.67,.31,.05))
    torso.ridged_plate(ARMOR, (-.18,.31*s,.49,.37,.30,.06),
                       (.16,.46*s,.52,.69,.35,.10),(.20,.47*s,.50,.67,.32,.08))
    torso.axle(STEEL, .91*s,0,.27,.18,.64)
for i in range(3):
    torso.shell(STEEL, (-.55+i*.11,0,.32,.54,.18),(-.50+i*.11,0,.37,.56,.20))
torso.build(.045)

hip = Part("Hip",(0,0,2.11))
hip.shell(DARK,(-.19,0,0,1,.7),(.19,0,0,.84,.6))
for s in [-1,1]:
    hip.shell(ARMOR,(-.41,s*.46,.29,.34,.26),(-.10,s*.43,.26,.55,.44),(.14,s*.34,.17,.48,.45))
hip.build()

def build_low_head():
    # 首の二段の旋回環の上に、前後に細長いセンサー架台を載せる。
    head = Part("Head", (0, .10, 4.02))
    head.axle(DARK, 0, -.03, -.245, .162, .16, "z")
    head.axle(STEEL, 0, -.03, -.215, .175, .055, "z")
    head.shell(DARK, (-.19, 0, .005, .32, .49), (-.075, 0, .045, .54, .70),
               (.085, 0, -.035, .55, .84))

    # 額は中央を前に突き出し、左右をこめかみまで引いた折れ面にする。
    # 横断面を前後につなぎ、後頭部は低く薄い形に絞る。
    brow_sections = [
        # 前後位置、半幅、下面の高さ、上面の高さ
        (-.66, .108, .045, .118), (-.35, .265, .048, .265),
        (-.075, .385, .058, .300), (.285, .345, .067, .217),
        (.565, .128, .038, .113),
    ]
    rings = []
    for y, width, low, high in brow_sections:
        # +Y に向かって断面をつなぐ。左右の稜線で天面と斜面を分ける。
        rings.append([(x * width, y, z) for x, z in [
            (-.82, low), (-1, low + .031), (-.62, high - .025),
            (0, high), (.62, high - .025), (1, low + .031), (.82, low)]])
    head.loft(rings, ARMOR)
    for side in [-1, 1]:
        # 頬の先を前下方へ振り、レンズの両脇に奥行きのある開口を残す。
        head.shell(PALE, (-.170, side*.205, .195, .082, .20),
                   (-.114, side*.252, .113, .130, .47),
                   (.013, side*.303, -.050, .127, .51))
        head.axle(DARK, side*.304, -.168, -.016, .110, .088)
        head.axle(STEEL, side*.351, -.168, -.016, .067, .026)
    # 後頭部の放熱口は額の張り出しの下に納める。
    for y in [-.47, -.36, -.25]:
        head.shell(DARK, (-.067, 0, y, .286, .066), (.069, 0, y-.045, .344, .073))
    head.build(.022)

    # センサーは独立した既存部位。奥まった光学窓と片側の補助レンズに分ける。
    visor = Part("Visor", (0, .52, 3.95))
    visor.shell(DARK, (-.074, 0, -.030, .322, .155),
                (-.003, 0, -.008, .474, .188), (.077, 0, -.040, .48, .18))
    visor.axle(STEEL, -.056, .112, -.003, .098, .127, "y")
    visor.axle(DARK, -.056, .173, -.003, .081, .036, "y")
    # 主レンズを凸面にして、横からも発光面の厚みが見えるようにする。
    rings = []
    for depth, radius in [(.186, .066), (.211, .068), (.239, .050), (.250, .018)]:
        rings.append([(-.056 + radius*sin(tau*i/16), depth, -.003 + radius*cos(tau*i/16))
                      for i in range(16)])
    visor.loft(rings, LENS)
    visor.shell(LENS, (.005, .132, .077, .093, .030), (.036, .128, .079, .101, .032))
    visor.build(.02)


def build_head_option(shape):
    # 比較案も既存の頭・光学窓の原点に取り付ける。
    head = Part("Head", (0, .10, 4.02))
    visor = Part("Visor", (0, .52, 3.95))
    head.axle(STEEL, 0, 0, -.218, .16, .16, "z")
    if shape == "mask":
        # 縦長の面甲。左右に離れた目の下で、頬骨と顎が中央へ絞られる。
        head.shell(DARK, (-.18,0,.04,.29,.47), (.18,0,.04,.59,.65),
                   (.52,0,-.05,.57,.55))
        head.shell(ARMOR, (.24,0,-.035,.69,.72), (.45,0,-.08,.64,.62),
                   (.63,0,-.12,.39,.42), (.69,0,-.12,.23,.25))
        for side in [-1,1]:
            head.shell(PALE, (-.18,side*.09,.23,.13,.25), (.03,side*.207,.25,.19,.34),
                       (.17,side*.26,.15,.16,.37))
            head.shell(ARMOR, (.215,side*.19,.22,.30,.43), (.31,side*.20,.14,.35,.49),
                       (.39,side*.17,.075,.28,.36))
            visor.shell(LENS, (.212,side*.20,-.018,.164,.057),
                        (.264,side*.181,-.012,.204,.065))
        head.shell(STEEL, (-.14,0,.29,.12,.21), (.045,0,.30,.22,.28),
                   (.21,0,.27,.12,.19))
    elif shape == "turret":
        # 幅の広い砲塔。横に広い鋳物の両端を旋回軸と側面装甲で受ける。
        head.axle(DARK, 0, -.03, .012, .33, .31, "z")
        head.shell(ARMOR, (-.08,0,-.035,.82,.66), (.07,0,-.01,1.04,.83),
                   (.34,0,-.105,.98,.80), (.46,0,-.17,.72,.57))
        for side in [-1,1]:
            head.axle(DARK, side*.46,-.06,.16,.20,.19)
            head.axle(STEEL, side*.555,-.06,.16,.132,.026)
            head.shell(PALE, (.12,side*.40,.13,.20,.43),
                       (.36,side*.405,.08,.26,.52), (.41,side*.40,.02,.20,.37))
        visor.shell(DARK, (.006,0,-.025,.65,.17), (.32,0,-.075,.62,.23))
        visor.axle(STEEL, -.085,.087,.169,.169,.101,"y")
        visor.axle(DARK, -.085,.148,.169,.130,.035,"y")
        visor.axle(LENS, -.085,.170,.169,.094,.021,"y")
        for z in [.108,.216]:
            visor.axle(LENS,.18,.074,z,.040,.032,"y")
    else:
        # 高く積んだ観測器。上の横長の窓と下の独立カメラを二股の側板で支える。
        head.shell(DARK, (-.17,0,0,.26,.37), (.12,0,.02,.47,.53),
                   (.43,0,-.09,.34,.45))
        for side in [-1,1]:
            head.shell(ARMOR, (-.12,side*.16,.06,.14,.36), (.16,side*.24,-.01,.18,.52),
                       (.58,side*.25,-.13,.14,.38), (.69,side*.24,-.19,.11,.22))
            head.axle(STEEL,side*.27,-.075,.48,.103,.12)
        head.shell(PALE, (.39,0,-.055,.42,.50), (.50,0,-.025,.48,.58),
                   (.70,0,-.09,.45,.51), (.77,0,-.145,.32,.35))
        visor.shell(DARK, (.535,0,-.195,.386,.22), (.735,0,-.235,.374,.23))
        visor.shell(LENS, (.588,0,-.074,.294,.040), (.658,0,-.082,.302,.05))
        visor.axle(STEEL,0,-.032,.165,.112,.19,"y")
        visor.axle(LENS,0,.072,.165,.063,.023,"y")
    head.build(.028)
    visor.build(.02)


# 引数なしは従来の薄型。比較案は別名で書き出し、ゲームの自機とは別に保管する。
parser = argparse.ArgumentParser()
parser.add_argument("--head", choices=["low", "mask", "turret", "tower"], default="low")
args = parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
if args.head == "low":
    build_low_head()
else:
    build_head_option(args.head)

for s, suffix in [(-1,"L"),(1,"R")]:
    shoulder = Part("Shoulder"+suffix,(s*1.6,0,3.42))
    shoulder.axle(DARK,-s*.23,0,0,.29,.83)
    shoulder.axle(STEEL,s*.18,0,0,.21,.10)
    shoulder.shell(ARMOR,(-.21,s*.23,0,.63,.82),(.05,s*.20,.02,1.03,1.22),(.39,-s*.06,-.04,.68,.76),(.45,-s*.14,-.13,.45,.52))
    shoulder.shell(PALE,(-.27,s*.30,.08,.53,.73),(-.10,s*.34,.03,.72,.92),(-.045,s*.30,.01,.66,.88))
    # 肩の内側から上腕の中心まで下ろした軸受けで、肩と腕の空隙をつなぐ。
    shoulder.shell(DARK, (-.61,-s*.30,.0,.32,.37), (-.42,-s*.30,.0,.40,.47),
                   (-.13,-s*.22,-.02,.49,.54), (.02,-s*.18,-.03,.47,.51))
    shoulder.axle(STEEL,-s*.30,.0,-.42,.142,.42)
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
    # 太ももは縦に長い一枚の折れ面。段差は外側に寄せて膝の境目を残す。
    leg.ridged_plate(ARMOR, (.12,0,.07,.40,.52,.035),(.54,s*.06,.04,.65,.73,.080),
                     (.87,s*.03,-.04,.54,.61,.045))
    leg.shell(ARMOR, (.36,s*.276,-.01,.09,.27),(.61,s*.316,-.045,.13,.37),
              (.77,s*.285,-.07,.12,.32))
    leg.axle(DARK,0,.025,0,.21,.64)
    leg.axle(STEEL,s*.32,.025,0,.146,.07)
    leg.shell(PALE,(-.18,0,.23,.28,.37),(.02,0,.28,.49,.51),(.15,0,.19,.39,.38))
    # すねは足首から膝下まで峰を通し、上端を後ろへ逃がして膝当てを独立させる。
    leg.ridged_plate(ARMOR, (-.89,0,.045,.34,.47,.045),(-.46,s*.04,.075,.55,.64,.11),
                     (-.26,s*.04,.075,.58,.71,.115),(-.145,s*.04,-.015,.47,.46,.035))
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
if args.head != "low":
    destination = destination.with_name(f"mech_b_{args.head}.glb")
destination.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(destination), export_format="GLB", export_apply=True)
