"""主役機の全身を決定稿の絵から起こす。

典拠：docs/visual_log/13_hero_body/reference/ref_body.jpg（全身）
      docs/visual_log/11_hero_face/reference/ref_03_final.jpg（頭部）
要件：SPEC.md §0.18「主役機の頭部：決定稿」「全身も決定稿の絵から起こす」

座標は左右 X、前方 +Y、高さ Z（Godot では前方 -Z）。全高 4 の機体として作る。
部位の名前と原点は量産機（mech_b.py）に合わせてあるので、Godot 側はそのまま差し替えられる。

使い方:
  blender --background --python tools/blender/mech_hero.py -- --out <画像の出力先>
"""
import argparse
import sys
from math import cos, radians, sin, tau
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


def finish(name, color, metallic, roughness, glow=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Emission Color"].default_value = (*color, 1)
    shader.inputs["Emission Strength"].default_value = glow
    return mat


ARMOR, PALE, DARK, STEEL, ORANGE, GLASS = range(6)
MATERIALS = []


def make_materials():
    # 明るい灰青の半つや消し。関節と内部は濃い青灰。整備表示だけオレンジ。
    MATERIALS[:] = [
        finish("Armor", (.300, .345, .395), .05, .76),
        finish("Edge", (.455, .510, .560), .05, .70),
        finish("Graphite", (.042, .055, .070), .46, .44),
        finish("Steel", (.26, .30, .33), .78, .34),
        finish("Orange", (.80, .17, .032), .10, .60),
        finish("Optics", (.050, .55, .76), .12, .25, 1.25),
    ]


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
                faces.append((lower + i, lower + j, lower + j + count, lower + i + count))
        top = start + (len(rings) - 1) * count
        faces.append(tuple(range(top, top + count)))
        self.faces.extend(faces)
        self.slots.extend([slot] * len(faces))

    def shell(self, slot, *sections):
        # 各段の中心・幅・奥行きをずらし、胸や脛の外板に折れ面を作る。
        rings = []
        for z, x, y, w, d in sections:
            a, b = w / 2, d / 2
            rings.append([(x + i * a, y + j * b, z) for i, j in
                          [(-.59, -1), (.59, -1), (1, -.57), (1, .40),
                           (.50, 1), (-.50, 1), (-1, .40), (-1, -.57)]])
        self.loft(rings, slot)

    def ridged_plate(self, slot, *sections):
        # 前面の左右を峰で折り、横一枚だった装甲に別々の向きの反射面を作る。
        rings = []
        for z, x, y, width, depth, ridge in sections:
            w, d = width / 2, depth / 2
            rings.append([(x + u * w, y + v * d, z) for u, v in
                          [(-.65, -1), (.65, -1), (1, -.4), (1, .42), (.66, .88),
                           (0, 1 + ridge / d), (-.66, .88), (-1, .42), (-1, -.4)]])
        self.loft(rings, slot)

    def axle(self, slot, x, y, z, radius, length, axis="x"):
        rings = []
        for end in [-length / 2, length / 2]:
            ring = []
            for i in range(16):
                a, b = radius * cos(tau * i / 16), radius * sin(tau * i / 16)
                offset = {"x": (end, a, b), "y": (b, end, a), "z": (a, b, end)}[axis]
                ring.append(tuple(p + v for p, v in zip((x, y, z), offset)))
            rings.append(ring)
        self.loft(rings, slot)

    def build(self, bevel=.032):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.location = self.origin
        for mat in MATERIALS:
            mesh.materials.append(mat)
        for face, slot in zip(mesh.polygons, self.slots):
            face.material_index = slot
            face.use_smooth = True
        edge = obj.modifiers.new("面取り", "BEVEL")
        edge.width = bevel
        edge.segments = 3
        edge.harden_normals = True
        normals = obj.modifiers.new("面積で重みづけした法線", "WEIGHTED_NORMAL")
        normals.keep_sharp = True
        return obj


# ======================================================================
# 頭部（2026-11-23 に決定稿から起こしたもの。寸法は頭部単体の縮尺で書いてある）
# ======================================================================

class Assembly:
    """頭部専用。任意の断面をつないでから面取りする。"""

    def __init__(self, name):
        self.name = name
        self.verts = []
        self.faces = []
        self.slots = []

    def loft(self, slot, rings):
        start = len(self.verts)
        n = len(rings[0])
        for ring in rings:
            self.verts.extend(ring)
        faces = [list(range(start, start + n))]
        for level in range(len(rings) - 1):
            base = start + level * n
            for i in range(n):
                j = (i + 1) % n
                faces.append((base + i, base + j, base + j + n, base + i + n))
        top = start + (len(rings) - 1) * n
        faces.append(list(range(top, top + n)))
        self.faces.extend(faces)
        self.slots.extend([slot] * len(faces))

    def hull(self, slot, *sections):
        profile = [(-.58, -1), (.58, -1), (1, -.5), (1, .34), (.63, .78),
                   (0, 1), (-.63, .78), (-1, .34), (-1, -.5)]
        self.loft(slot, [[(x + a * w, y + b * d, z) for a, b in profile]
                         for z, x, y, w, d in sections])

    def pin(self, slot, x, y, z, radius, length, axis="z"):
        rings = []
        for end in (-length / 2, length / 2):
            ring = []
            for i in range(16):
                a, b = radius * cos(tau * i / 16), radius * sin(tau * i / 16)
                u, v, w = {"x": (end, a, b), "y": (a, end, b), "z": (a, b, end)}[axis]
                ring.append((x + u, y + v, z + w))
            rings.append(ring)
        self.loft(slot, rings)

    def build(self):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.verts, [], self.faces)
        for mat in MATERIALS:
            mesh.materials.append(mat)
        for polygon, slot in zip(mesh.polygons, self.slots):
            polygon.material_index = slot
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        bevel = obj.modifiers.new("面取り", "BEVEL")
        bevel.width = .013
        bevel.segments = 2
        normals = obj.modifiers.new("面積で重みづけした法線", "WEIGHTED_NORMAL")
        normals.keep_sharp = True
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        return obj


# 庇の平面輪郭。(x, y, 上面の高さ, 下面の高さ)。前が尖った六角形で、横から見ると前下がり。
CANOPY = [
    (.000, .560, .098, .038),
    (.165, .420, .162, .098),
    (.318, .150, .214, .132),
    (.368, -.180, .300, .186),
    (.300, -.420, .370, .240),
    (.000, -.520, .408, .272),
]


def shell_patch(part, slot, border, peak, thickness=.04):
    start = len(part.verts)
    n = len(border)
    part.verts.extend((x, y - thickness, z) for x, y, z in border)
    part.verts.extend(border)
    part.verts.append(peak)
    part.faces.append(tuple(range(start, start + n)))
    part.slots.append(slot)
    for i in range(n):
        j = (i + 1) % n
        part.faces.extend([(start + i, start + j, start + n + j, start + n + i),
                           (start + n + i, start + n + j, start + 2 * n)])
        part.slots.extend([slot, slot])


def strut(part, slot, start, end, radius):
    axis = (Vector(end) - Vector(start)).normalized()
    u = axis.cross(Vector((1, 0, 0)))
    if u.length < 1e-4:
        u = axis.cross(Vector((0, 0, 1)))
    u = u.normalized() * radius
    v = axis.cross(u)
    part.loft(slot, [[Vector(center) + u * cos(tau * i / 12) + v * sin(tau * i / 12)
                      for i in range(12)] for center in (start, end)])


def blade(part, slot, side, root, tip, chord_root, chord_tip, thick):
    a = Vector((side * root[0], root[1], root[2]))
    b = Vector((side * tip[0], tip[1], tip[2]))
    axis = (b - a).normalized()
    u = axis.cross(Vector((1, 0, 0))).normalized()
    rings = []
    for center, chord in ((a, chord_root), (b, chord_tip)):
        half_u = u * (chord / 2)
        half_t = Vector((thick / 2, 0, 0))
        rings.append([center + half_u + half_t, center + half_u - half_t,
                      center - half_u - half_t, center - half_u + half_t])
    part.loft(slot, rings)


def ring_plate(part, slot, outline, back, front):
    part.loft(slot, [[(x, y, z) for x, z in outline] for y in (back, front)])


def build_head():
    canopy, skull, mask, neck = [Assembly(n) for n in
                                 ("Canopy", "Housing", "Faceplate", "NeckGear")]
    parts = [canopy, skull, mask, neck]

    # --- 庇 ---
    outline = CANOPY + [(-x, y, zt, zb) for x, y, zt, zb in reversed(CANOPY[1:-1])]
    skin = .022
    canopy.loft(PALE, [[(x, y, zt - skin) for x, y, zt, _ in outline],
                       [(x, y, zt) for x, y, zt, _ in outline]])
    canopy.loft(DARK, [[(x, y, zb) for x, y, _, zb in outline],
                       [(x, y, zt - skin) for x, y, zt, _ in outline]])
    crest = [(.000, .260, .206), (.218, .060, .252), (.258, -.200, .312),
             (.210, -.400, .374), (.000, -.470, .400)]
    crest = crest + [(-x, y, z) for x, y, z in reversed(crest[1:-1])]
    canopy.loft(ARMOR, [[(x, y, z) for x, y, z in crest],
                        [(x * .86, y + .016, z + .038) for x, y, z in crest]])

    def shrink(x, y):
        length = (x * x + (y + .1) * (y + .1)) ** .5 or 1
        return x - x / length * .034, y - (y + .1) / length * .034
    lip = []
    for x, y, _zt, zb in outline:
        sx, sy = shrink(x, y)
        lip.append((sx, sy, zb, zb - (.026 + max(0.0, (.20 - y)) * .092)))
    canopy.loft(PALE, [[(x, y, zb) for x, y, zb, _ in lip],
                       [(x, y, zd) for x, y, _, zd in lip]])
    for side in (-1, 1):
        canopy.pin(STEEL, side * .250, -.390, .320, .052, .140, "y")

    # --- 頭部本体 ---
    skull.hull(DARK, (.175, 0, .030, .300, .215), (.040, 0, .045, .330, .250),
               (-.140, 0, .030, .310, .238), (-.330, 0, -.010, .240, .192),
               (-.470, 0, -.060, .152, .128), (-.580, 0, -.090, .090, .078))
    skull.hull(ARMOR, (.270, 0, -.150, .282, .150), (.100, 0, -.170, .330, .180),
               (-.090, 0, -.180, .340, .190), (-.270, 0, -.180, .292, .172),
               (-.420, 0, -.170, .196, .124))
    skull.hull(ARMOR, (.120, 0, -.270, .288, .160), (.230, 0, -.290, .300, .168),
               (.330, 0, -.300, .276, .150))

    # --- 顔の装甲と二つのセンサー ---
    mask.hull(ARMOR, (.040, 0, .044, .292, .206), (-.110, 0, .056, .302, .216),
              (-.270, 0, .056, .290, .200), (-.400, 0, .050, .268, .172),
              (-.520, 0, .042, .248, .148), (-.592, 0, .030, .214, .120))
    mask.hull(PALE, (-.450, 0, .044, .246, .150), (-.545, 0, .038, .228, .132),
              (-.615, 0, .026, .196, .108))
    for side in (-1, 1):
        def panel(part, slot, border, peak, thickness=.04):
            shell_patch(part, slot, [(side * x, y, z) for x, y, z in border],
                        (side * peak[0], peak[1], peak[2]), thickness)

        panel(mask, DARK, [(.030, .272, -.042), (.062, .286, .044),
                           (.258, .246, .082), (.322, .206, .054),
                           (.300, .214, -.046), (.070, .268, -.088)],
              (.180, .278, .002), .055)
        panel(mask, GLASS, [(.052, .286, -.022), (.080, .296, .018),
                            (.248, .254, .054), (.292, .230, .034),
                            (.252, .242, -.012), (.084, .288, -.048)],
              (.170, .292, .006), .030)
        for z in (-.150, -.218):
            ring_plate(mask, STEEL, [(side * .130, z), (side * .268, z - .022),
                                     (side * .266, z - .058), (side * .128, z - .040)],
                       .232, .250)
        skull.hull(PALE, (-.020, side * .360, .128, .078, .100),
                   (-.150, side * .372, .104, .074, .096),
                   (-.272, side * .350, .068, .054, .070))
        skull.hull(DARK, (-.050, side * .296, .228, .050, .060),
                   (-.164, side * .302, .212, .046, .056))
        panel(skull, ARMOR, [(.300, .180, .110), (.372, .040, .090),
                             (.368, -.180, .050), (.300, -.300, -.030),
                             (.286, -.090, -.110), (.296, .130, -.060)],
              (.392, -.060, .010), .070)
        blade(skull, PALE, side, (.330, -.020, .020), (.404, -.560, .300), .200, .060, .040)
        blade(skull, PALE, side, (.330, -.090, -.110), (.380, -.470, .030), .150, .050, .034)
        blade(skull, ARMOR, side, (.316, .090, -.210), (.404, -.330, -.230), .130, .048, .030)
        ring_plate(mask, ORANGE, [(side * .238, -.212), (side * .286, -.206),
                                  (side * .284, -.252), (side * .236, -.258)],
                   .196, .206)
        strut(neck, STEEL, (side * .150, .080, -.560), (side * .090, -.080, -.720), .030)
        strut(neck, DARK, (side * .196, -.130, -.470), (side * .126, -.170, -.750), .026)

    neck.pin(DARK, 0, -.090, -.710, .122, .280)
    for z in (-.800, -.720, -.640):
        neck.pin(STEEL, 0, -.090, z, .138, .030)
    neck.pin(STEEL, 0, -.090, -.560, .104, .070)

    objects = [part.build() for part in parts]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = objects[0]
    obj.name = "Head_hero"
    obj.data.name = "Head_hero"
    for vert in obj.data.vertices:
        vert.co *= .505
        vert.co.z += .140
    obj.location = (0, .10, 4.02)
    return obj


# ======================================================================
# 全身
# ======================================================================

def build_body():
    # --- 胴体：前へ大きく張り出した胸、中央に縦の稜線、細い腹 ---
    torso = Part("Torso", (0, 0, 3.09))
    torso.shell(DARK, (-.70, 0, 0, .66, .56), (-.34, 0, 0, .92, .74),
                (.30, 0, -.03, 1.42, 1.02), (.62, 0, -.06, 1.06, .70))
    # 鎖骨の横帯。胸甲の上端をここで切り、首まわりを締める。
    torso.shell(DARK, (.50, 0, .20, 1.20, .50), (.64, 0, .18, 1.04, .42))
    for s in (-1, 1):
        # 左右に割れた胸甲。中央へせり出し、脇へ鋭く絞る。
        torso.shell(ARMOR, (-.30, .24 * s, .34, .40, .50), (.16, .42 * s, .40, .82, .86),
                    (.52, .40 * s, .16, .78, .88), (.64, .36 * s, .04, .52, .54))
        torso.ridged_plate(PALE, (.20, .40 * s, .60, .62, .34, .085),
                           (.32, .42 * s, .57, .70, .38, .105),
                           (.46, .42 * s, .49, .58, .30, .055))
        # 肩の付け根。
        torso.axle(STEEL, .82 * s, 0, .26, .18, .62)
        torso.shell(DARK, (.10, .74 * s, .06, .38, .52), (.40, .78 * s, .08, .44, .60))
    # 胸の中央を縦に通る稜線。左右の胸甲の間に一本だけ立てる。
    torso.ridged_plate(PALE, (-.22, 0, .44, .26, .34, .07), (.22, 0, .52, .34, .42, .12),
                       (.52, 0, .44, .30, .36, .09), (.64, 0, .36, .22, .26, .05))
    # 腹の放熱口。
    for i in range(3):
        torso.shell(STEEL, (-.60 + i * .12, 0, .30, .46, .16), (-.55 + i * .12, 0, .34, .48, .18))
    torso.build(.045)

    # --- 腰：細く絞り、前と横に大きなスカート装甲 ---
    hip = Part("Hip", (0, 0, 2.11))
    hip.shell(DARK, (-.22, 0, 0, .86, .60), (.20, 0, 0, .74, .54))
    for s in (-1, 1):
        # 前面のスカート。立ち姿に「構え」を作る一番大きな板。
        hip.ridged_plate(ARMOR, (-.78, s * .26, .46, .44, .28, .07),
                         (-.30, s * .30, .50, .64, .36, .12),
                         (.14, s * .28, .40, .56, .32, .08))
        # 横のスカート。
        hip.shell(ARMOR, (-.50, s * .54, .02, .32, .60), (-.12, s * .56, .00, .40, .74),
                  (.16, s * .48, -.02, .34, .60))
        hip.axle(STEEL, s * .40, 0, -.30, .16, .34)
        hip.shell(ORANGE, (-.30, s * .60, .26, .10, .12), (-.24, s * .60, .26, .10, .12))
    hip.build()

    for s, suffix in [(-1, "L"), (1, "R")]:
        # --- 肩：量産機より一回り大きく、上へ跳ね上がる ---
        shoulder = Part("Shoulder" + suffix, (s * 1.6, 0, 3.42))
        shoulder.axle(DARK, -s * .23, 0, 0, .30, .86)
        shoulder.axle(STEEL, s * .20, 0, 0, .22, .11)
        shoulder.shell(ARMOR, (-.34, s * .18, 0, .60, .92), (.06, s * .20, .04, .96, 1.46),
                       (.44, s * .06, -.02, .78, 1.16), (.66, -s * .10, -.14, .44, .64))
        # 上面の段差。跳ね上がりの稜線をここで出す。
        shoulder.ridged_plate(PALE, (.12, s * .24, .16, .72, .86, .12),
                              (.40, s * .18, .10, .62, .74, .10),
                              (.60, s * .06, -.02, .42, .50, .05))
        # 肩の内側から上腕の中心まで下ろした軸受け。
        shoulder.shell(DARK, (-.64, -s * .30, 0, .34, .39), (-.44, -s * .30, 0, .42, .49),
                       (-.14, -s * .22, -.02, .52, .57), (.02, -s * .18, -.03, .50, .54))
        shoulder.axle(STEEL, -s * .30, 0, -.44, .150, .44)
        shoulder.build(.04)

        # --- 腕：肘の円盤を見せ、前腕を角張らせる ---
        arm = Part("Arm" + suffix, (s * 1.3, 0, 2.35))
        arm.shell(DARK, (-.80, 0, .02, .24, .28), (-.44, 0, .02, .26, .30), (.63, 0, 0, .26, .26))
        arm.shell(ARMOR, (-.70, s * .03, .05, .30, .34), (-.30, s * .05, .08, .40, .46),
                  (-.06, s * .04, .05, .34, .38))
        arm.shell(ARMOR, (.10, 0, .01, .27, .32), (.46, s * .03, 0, .40, .44),
                  (.66, s * .03, -.04, .36, .34))
        # 肘の関節。装甲に隠さず外から見せる。
        arm.axle(STEEL, 0, .02, .02, .19, .50)
        arm.axle(DARK, 0, .02, .02, .13, .56)
        arm.shell(STEEL, (-.86, 0, .05, .27, .28), (-.66, 0, .07, .32, .32))
        # 手。指は 3 本にまとめ、開いた状態で止める。
        arm.shell(DARK, (-1.02, 0, .04, .30, .34), (-1.18, 0, .04, .26, .30))
        for i in (-1, 0, 1):
            arm.shell(PALE, (-1.26, i * .10, .06, .07, .09), (-1.46, i * .11, .10, .06, .08))
        arm.build()

        # --- 脚：長く太く、膝の駆動部を見せる ---
        leg = Part("Leg" + suffix, (s * .55, 0, 1.05))
        leg.shell(DARK, (-.96, 0, -.03, .28, .37), (-.30, 0, -.02, .40, .50),
                  (.12, 0, 0, .32, .46), (.96, 0, 0, .44, .56))
        # 太もも。縦に長い一枚の折れ面。段差は外側に寄せる。
        leg.ridged_plate(ARMOR, (.10, 0, .07, .40, .52, .04), (.56, s * .05, .04, .62, .74, .09),
                         (.94, s * .03, -.04, .50, .60, .05))
        leg.shell(ARMOR, (.36, s * .30, -.01, .10, .29), (.62, s * .34, -.045, .14, .40),
                  (.80, s * .31, -.07, .13, .34))
        # 膝の関節。
        leg.axle(DARK, 0, .025, 0, .23, .68)
        leg.axle(STEEL, s * .34, .025, 0, .155, .08)
        # 膝当て。
        leg.ridged_plate(PALE, (-.20, 0, .24, .30, .38, .05), (.02, 0, .30, .52, .54, .10),
                         (.16, 0, .20, .40, .40, .05))
        # すね。足首から膝下まで峰を通す。
        leg.ridged_plate(ARMOR, (-.94, 0, .045, .32, .45, .05), (-.52, s * .04, .075, .50, .62, .12),
                         (-.24, s * .04, .075, .52, .68, .12),
                         (-.125, s * .04, -.015, .42, .44, .04))
        leg.axle(STEEL, s * .20, -.26, -.55, .070, .80, "z")
        leg.build(.036)

        # --- 足：つま先を前に長く伸ばす ---
        foot = Part("Foot" + suffix, (s * .55, .15, .15))
        foot.shell(DARK, (-.15, 0, .07, .78, 1.50), (-.06, 0, .08, .82, 1.50))
        foot.shell(ARMOR, (-.05, 0, .14, .78, 1.44), (.07, 0, .16, .70, 1.30),
                   (.18, 0, -.08, .48, .66))
        foot.shell(PALE, (-.03, 0, .68, .58, .32), (.06, 0, .62, .48, .30))
        foot.build(.024)

    # --- 背面の推進ユニットと、後方へ伸びる大きなブレード ---
    pack = Part("BackPack", (0, -.90, 3.14))
    pack.shell(DARK, (-.62, 0, 0, .72, .56), (.58, 0, 0, 1.02, .74))
    for s in (-1, 1):
        pack.shell(ARMOR, (-.80, s * .60, -.05, .44, .62), (-.42, s * .62, -.11, .64, .86),
                   (.44, s * .56, .02, .62, .80), (.84, s * .54, -.12, .44, .60))
        pack.axle(STEEL, s * .60, -.42, -.44, .23, .34, "y")
        pack.axle(DARK, s * .60, -.60, -.44, .18, .05, "y")
        for i in range(4):
            pack.shell(STEEL, (-.04 + i * .12, s * .54, -.36, .40, .13),
                       (.02 + i * .12, s * .54, -.39, .42, .17))
        # 肩越しに見える大きなブレード 2 枚。輪郭を後ろ側で大きく見せる。
        pack.shell(PALE, (.26, s * .66, -.18, .44, .14), (.80, s * .90, -1.10, .32, .11),
                   (1.26, s * 1.06, -2.00, .15, .07))
        pack.shell(ARMOR, (.04, s * .48, -.30, .34, .12), (.52, s * .70, -1.16, .24, .09),
                   (.88, s * .82, -1.90, .12, .06))
    pack.build()

    # --- 武器（Godot 側が参照するので量産機と同じ作りで用意する）---
    barrel = Part("Barrel", (1.3, .60, 1.75))
    barrel.axle(DARK, 0, 0, 0, .12, 1.60, "z")
    barrel.shell(ARMOR, (-.29, 0, 0, .25, .29), (.37, 0, 0, .36, .40), (.78, 0, 0, .33, .37))
    barrel.axle(STEEL, 0, 0, -.62, .146, .25, "z")
    barrel.axle(DARK, 0, 0, -.76, .137, .10, "z")
    barrel.build(.02).rotation_euler.x = radians(90)


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def studio():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 16
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 460
    scene.render.resolution_y = 640
    world = bpy.data.worlds.new("Studio")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes.get("Background").inputs[0].default_value = (.16, .19, .22, 1)
    for loc, power, size in [((7, 9, 12), 3000, 8), ((-9, 4, 4), 1700, 8), ((0, -9, 9), 3000, 6)]:
        bpy.ops.object.light_add(type="AREA", location=loc)
        light = bpy.context.object
        light.data.energy = power
        light.data.shape = "DISK"
        light.data.size = size
        aim(light, (0, 0, 2))
    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 5.6
    scene.camera = camera
    return scene, camera


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    make_materials()
    scene, camera = studio()
    build_head()
    build_body()

    destination = Path(__file__).resolve().parents[2] / "assets/models/mech_hero.glb"
    destination.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(destination), export_format="GLB",
                              export_apply=True, use_selection=True)

    for label, angle in [("front", 0), ("quarter", 38), ("side", 90)]:
        camera.location = (9 * sin(radians(angle)), 9 * cos(radians(angle)), 2.3)
        aim(camera, (0, 0, 2.1))
        scene.render.filepath = str(args.out / f"body_{label}.png")
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
