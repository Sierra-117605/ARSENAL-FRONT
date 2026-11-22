"""主役機の頭部を決定稿の絵から起こし、同一照明・同一倍率で撮影する。

典拠：docs/visual_log/11_hero_face/reference/ref_03_final.jpg（本命）
      docs/visual_log/11_hero_face/reference/ref_01_plain.jpg（装飾を抑えた版）
要件：SPEC.md §0.18「主役機の頭部：決定稿」（第 44 版）

輪郭に効く順に
  1. 大きな一枚の庇。上から見ると前が尖った六角形。後ろは厚く前縁は薄い。下面は暗い
  2. 庇の下は面長の箱。頭頂を盛らず、センサーから下端までに長さを持たせる
  4. 側頭部から後方へブレードが数枚、斜め上後ろへ伸びる
座標系：+Y が正面、+Z が上。最後に全体を 0.505 倍して量産機の頭と高さをそろえる。
"""
import argparse
from math import cos, radians, sin, tau
from pathlib import Path
import sys

import bmesh
import bpy
from mathutils import Vector


def material(name, color, metal=0.05, roughness=0.74, emission=0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metal
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Emission Color"].default_value = (*color, 1)
    shader.inputs["Emission Strength"].default_value = emission
    return mat


class Assembly:
    """一つの機能部品に属する外板と機構をまとめて面取りする。"""

    def __init__(self, name):
        self.name = name
        self.verts = []
        self.faces = []
        self.slots = []

    def loft(self, slot, rings):
        # 輪郭断面を閉じてつなぐ。法線は最後に外向きにそろえる。
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
        # 前端に峰を持つ九角断面。上下の断面をずらして折れ面を作る。
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

    def build(self, palette):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.verts, [], self.faces)
        for mat in palette:
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


ARMOR, PALE, DARK, STEEL, ORANGE, GLASS = range(6)

# 庇の平面輪郭。(x, y, 上面の高さ, 下面の高さ)。
# 上から見ると前が尖った六角形。横から見ると前下がり。前縁は薄く、後ろの付け根は厚い。
CANOPY = [
    (.000, .700, .072, .024),
    (.170, .480, .140, .080),
    (.320, .160, .216, .134),
    (.368, -.180, .300, .186),
    (.300, -.420, .370, .240),
    (.000, -.520, .408, .272),
]


def shell_patch(part, slot, border, peak, thickness=.04):
    """折れ面の板。外周に板厚を与え、中央の峰へ向けて各面を傾ける。"""
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
    # 配管・リンク。首まわりの機構を外から見せるために使う。
    axis = (Vector(end) - Vector(start)).normalized()
    u = axis.cross(Vector((1, 0, 0)))
    if u.length < 1e-4:
        u = axis.cross(Vector((0, 0, 1)))
    u = u.normalized() * radius
    v = axis.cross(u)
    part.loft(slot, [[Vector(center) + u * cos(tau * i / 12) + v * sin(tau * i / 12)
                      for i in range(12)] for center in (start, end)])


def blade(part, slot, side, root, tip, chord_root, chord_tip, thick):
    """側頭部から後方へ伸びる薄い板。斜めから見たときの速度感をこれで作る。"""
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
    """前後に厚みを持つ平板。整備表示や薄い当て板に使う。"""
    part.loft(slot, [[(x, y, z) for x, z in outline] for y in (back, front)])


def build_head(palette):
    canopy = Assembly("Canopy")
    skull = Assembly("Housing")
    mask = Assembly("Faceplate")
    neck = Assembly("NeckGear")
    parts = [canopy, skull, mask, neck]

    # --- 1. 庇 ---------------------------------------------------------
    # 上の板（明るい灰青）と下の芯（濃い青灰）に分け、縁が薄く抜けて見えるようにする。
    outline = CANOPY + [(-x, y, zt, zb) for x, y, zt, zb in reversed(CANOPY[1:-1])]
    skin = .022
    canopy.loft(PALE, [[(x, y, zt - skin) for x, y, zt, _ in outline],
                       [(x, y, zt) for x, y, zt, _ in outline]])
    canopy.loft(DARK, [[(x, y, zb) for x, y, _, zb in outline],
                       [(x, y, zt - skin) for x, y, zt, _ in outline]])
    # 庇の後ろ半分にだけ段差を一枚足す。全面をパネル線で埋めない。
    crest = [(.000, .260, .206), (.218, .060, .252), (.258, -.200, .312),
             (.210, -.400, .374), (.000, -.470, .400)]
    crest = crest + [(-x, y, z) for x, y, z in reversed(crest[1:-1])]
    canopy.loft(ARMOR, [[(x, y, z) for x, y, z in crest],
                        [(x * .86, y + .016, z + .038) for x, y, z in crest]])
    # 庇の付け根の厚みを見せる支え。
    for side in (-1, 1):
        canopy.pin(STEEL, side * .250, -.390, .320, .052, .140, "y")

    # --- 2. 面長の頭部本体 ---------------------------------------------
    # 内部の機器。顔の造形（眉・鼻筋・唇）は作らない。
    skull.hull(DARK, (.175, 0, .030, .300, .215), (.040, 0, .045, .330, .250),
               (-.140, 0, .030, .310, .238), (-.330, 0, -.010, .240, .192),
               (-.470, 0, -.060, .152, .128), (-.580, 0, -.090, .090, .078))
    # 後頭部の外殻。庇の後端まで立ち上げ、皿が浮いて見えないようつなぐ。
    skull.hull(ARMOR, (.270, 0, -.150, .282, .150), (.100, 0, -.170, .330, .180),
               (-.090, 0, -.180, .340, .190), (-.270, 0, -.180, .292, .172),
               (-.420, 0, -.170, .196, .124))
    # 庇の付け根の塊。ここで庇と頭が一体につながる。
    skull.hull(ARMOR, (.120, 0, -.270, .288, .160), (.230, 0, -.290, .300, .168),
               (.330, 0, -.300, .276, .150))

    # --- 3. 顔の装甲と二つのセンサー -----------------------------------
    # 顔の前面は大きな一枚の装甲。断面を縦に送って作るので面が平滑に通り、
    # 中央に縦の稜線が一本だけ立つ（小さな板を放射状に貼ると岩の塊に見えるため使わない）。
    mask.hull(ARMOR, (.040, 0, .044, .292, .206), (-.110, 0, .056, .300, .214),
              (-.270, 0, .052, .276, .198), (-.400, 0, .038, .224, .164),
              (-.510, 0, .016, .150, .118), (-.560, 0, -.004, .096, .078))
    # 顎の下端に薄い当て板を一枚だけ重ねて二段に見せる。
    mask.hull(PALE, (-.430, 0, .028, .196, .146), (-.520, 0, .010, .146, .114),
              (-.572, 0, -.010, .092, .074))
    for side in (-1, 1):
        def panel(part, slot, border, peak, thickness=.04):
            shell_patch(part, slot, [(side * x, y, z) for x, y, z in border],
                        (side * peak[0], peak[1], peak[2]), thickness)

        # 目のまわりの暗い窓枠。庇の影の中に沈める。
        panel(mask, DARK, [(.030, .272, -.042), (.062, .286, .044),
                           (.258, .246, .082), (.322, .206, .054),
                           (.300, .214, -.046), (.070, .268, -.088)],
              (.180, .278, .002), .055)
        # レンズ本体。細く切れ長で、外側へ向かって跳ね上がる。
        panel(mask, GLASS, [(.052, .286, -.022), (.080, .296, .018),
                            (.248, .254, .054), (.292, .230, .034),
                            (.252, .242, -.012), (.084, .288, -.048)],
              (.170, .292, .006), .030)
        # 頬の排気スリットを二本だけ。密度は顔まわりに集中させる。
        for z in (-.150, -.218):
            ring_plate(mask, STEEL, [(side * .130, z), (side * .268, z - .022),
                                     (side * .266, z - .058), (side * .128, z - .040)],
                       .232, .250)
        # 側頭部のカバー。庇の下に潜り込み、ブレードの付け根になる。
        panel(skull, ARMOR, [(.300, .180, .110), (.372, .040, .090),
                             (.368, -.180, .050), (.300, -.300, -.030),
                             (.286, -.090, -.110), (.296, .130, -.060)],
              (.392, -.060, .010), .070)

        # --- 4. 後方へ伸びるブレード -----------------------------------
        blade(skull, PALE, side, (.330, -.020, .020), (.412, -.700, .250), .220, .066, .040)
        blade(skull, PALE, side, (.330, -.090, -.110), (.386, -.580, -.010), .170, .054, .034)
        blade(skull, ARMOR, side, (.316, .080, -.210), (.404, -.330, -.230), .130, .048, .030)

        # 小さな整備表示。発光するのはレンズだけ。
        ring_plate(mask, ORANGE, [(side * .238, -.212), (side * .286, -.206),
                                  (side * .284, -.252), (side * .236, -.258)],
                   .196, .206)
        # 首のリンクと配管を外から見えるように渡す。
        strut(neck, STEEL, (side * .148, .070, -.500), (side * .090, -.080, -.660), .030)
        strut(neck, DARK, (side * .192, -.130, -.430), (side * .126, -.170, -.690), .026)

    # --- 5. 首 ---------------------------------------------------------
    neck.pin(DARK, 0, -.090, -.650, .122, .280)
    for z in (-.740, -.660, -.580):
        neck.pin(STEEL, 0, -.090, z, .138, .030)
    neck.pin(STEEL, 0, -.090, -.500, .104, .070)

    # 部品を 1 個の交換メッシュにまとめ、量産機の頭と高さをそろえる。
    objects = [part.build(palette) for part in parts]
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
    return obj


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def studio():
    # 全角度で同じ正投影カメラ、背景、三点照明を使う（これまでの比較画像と同条件）。
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 12
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 520
    scene.render.resolution_y = 460
    scene.render.resolution_percentage = 100
    world = bpy.data.worlds.new("Studio")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes.get("Background").inputs[0].default_value = (.16, .19, .22, 1)
    for loc, power, size in [((2, 3, 4), 270, 3), ((-3, 1, 1), 160, 3), ((0, -3, 3), 320, 2)]:
        bpy.ops.object.light_add(type="AREA", location=loc)
        light = bpy.context.object
        light.data.energy = power
        light.data.shape = "DISK"
        light.data.size = size
        aim(light, (0, 0, 0))
    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.05
    scene.camera = camera
    return scene, camera


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    # Blender は相対パスを blend ファイル基準に解釈するので、必ず絶対パスにしてから使う。
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # 明るい灰青の半つや消し。内部と庇の下面は濃い青灰。整備表示だけオレンジ。
    palette = [material("Armor", (.255, .305, .352)),
               material("Edge", (.400, .460, .510)),
               material("Graphite", (.042, .058, .074), .46, .44),
               material("Steel", (.26, .31, .33), .78, .34),
               material("Orange", (.80, .17, .032)),
               material("Optics", (.050, .55, .76), .12, .25, 1.25)]
    scene, camera = studio()
    head = build_head(palette)
    bpy.ops.object.select_all(action="DESELECT")
    head.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(args.out / "head_hero.glb"),
                              export_format="GLB", use_selection=True)
    for label, angle in [("front", 0), ("quarter", 42), ("side", 90)]:
        camera.location = (2 * sin(radians(angle)), 2 * cos(radians(angle)), .18)
        aim(camera, (0, 0, -.005))
        scene.render.filepath = str(args.out / f"head_{label}.png")
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
