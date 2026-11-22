"""主役機の頭部を単体で造形し、同一照明・同一倍率で選定用に撮影する。"""
import argparse
from math import cos, radians, sin, tau
from pathlib import Path
from typing import NamedTuple
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
        # 輪郭断面を閉じてつなぐ。左右鏡像を含むので法線は最後に外向きにそろえる。
        start = len(self.verts)
        n = len(rings[0])
        for ring in rings:
            self.verts.extend(ring)
        faces = [list(range(start, start+n))]
        for level in range(len(rings)-1):
            base = start + level*n
            for i in range(n):
                j = (i+1) % n
                faces.append((base+i, base+j, base+j+n, base+i+n))
        top = start+(len(rings)-1)*n
        faces.append(list(range(top, top+n)))
        self.faces.extend(faces)
        self.slots.extend([slot]*len(faces))

    def hull(self, slot, *sections):
        # 前端に峰を持つ九角断面。上下の断面をずらして折れ面を作る。
        profile = [(-.58,-1),(.58,-1),(1,-.5),(1,.34),(.63,.78),
                   (0,1),(-.63,.78),(-1,.34),(-1,-.5)]
        self.loft(slot, [[(x+a*w, y+b*d, z) for a,b in profile]
                         for z,x,y,w,d in sections])

    def plate(self, slot, outline, back, front, ridge=0):
        # 正面の輪郭に厚みを与え、中央の小さな平面に向けて各面を傾ける。
        cx = sum(x for x,z in outline)/len(outline)
        cz = sum(z for x,z in outline)/len(outline)
        rings = [[(x,y,z) for x,z in outline] for y in (back,front)]
        if ridge:
            rings.append([(cx+(x-cx)*.52, front+ridge, cz+(z-cz)*.60) for x,z in outline])
        self.loft(slot, rings)

    def pin(self, slot, x,y,z, radius,length,axis="z"):
        rings = []
        for end in (-length/2,length/2):
            ring = []
            for i in range(16):
                a,b = radius*cos(tau*i/16),radius*sin(tau*i/16)
                u,v,w = {"x":(end,a,b),"z":(a,b,end)}[axis]
                ring.append((x+u,y+v,z+w))
            rings.append(ring)
        self.loft(slot,rings)

    def build(self, palette):
        mesh=bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.verts,[],self.faces)
        for mat in palette:
            mesh.materials.append(mat)
        for polygon,slot in zip(mesh.polygons,self.slots):
            polygon.material_index=slot
        bm=bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()
        obj=bpy.data.objects.new(self.name,mesh)
        bpy.context.collection.objects.link(obj)
        bpy.context.view_layer.objects.active=obj
        bevel=obj.modifiers.new("面取り","BEVEL")
        bevel.width=.015
        bevel.segments=2
        normals=obj.modifiers.new("面積で重みづけした法線","WEIGHTED_NORMAL")
        normals.keep_sharp=True
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        return obj


# 共通の首取付位置に対して、下顔面の装甲、庇の奥行き、側頭部の構成を変える。
class Face(NamedTuple):
    half_width: float
    chin_width: float
    chin_z: float
    rear: float
    visor_y: float


PROFILES = {
    "I": Face(.410, .116, -.334, -.40, .385),
    "J": Face(.355, .084, -.320, -.55, .445),
    "K": Face(.480, .180, -.310, -.43, .360),
    "L": Face(.405, .135, -.356, -.46, .405),
}
ARMOR, PALE, DARK, STEEL, ORANGE, GLASS = range(6)


def shell_patch(part, slot, border, peak, thickness=.04):
    """顔の折れ面。各頂点を別々の奥行きに置いて継ぎ目や装甲の峰に実際の奥行きを与える。"""
    start = len(part.verts)
    n = len(border)
    part.verts.extend((x, y-thickness, z) for x, y, z in border)
    part.verts.extend(border)
    part.verts.append(peak)
    part.faces.append(tuple(range(start, start+n)))
    part.slots.append(slot)
    for i in range(n):
        j = (i+1) % n
        part.faces.extend([(start+i, start+j, start+n+j, start+n+i),
                           (start+n+i, start+n+j, start+2*n)])
        part.slots.extend([slot, slot])


def strut(part, slot, start, end, radius):
    # 頬の回転軸から顎を引く斜めのリンク。左右で同じ支点を使う。
    axis = (Vector(end)-Vector(start)).normalized()
    u = axis.cross(Vector((1, 0, 0))).normalized() * radius
    v = axis.cross(u)
    part.loft(slot, [[Vector(center)+u*cos(tau*i/12)+v*sin(tau*i/12)
                      for i in range(12)] for center in (start, end)])


def side_rail(part, slot, side, sections):
    """後方から前方へ断面を送り、装甲の外面と折り返しを一体で造形する。"""
    rings = []
    for y, center, radius, bottom, top in sections:
        h = top-bottom
        rings.append([(side*(center+radius*x), y, bottom+h*z)
                      for x,z in [(-1,.16),(-.77,.88),(-.25,1),(.65,.92),
                                  (1,.58),(.90,.18),(.35,0),(-.60,.02)]])
    part.loft(slot, rings)


def build_face(key, palette):
    f = PROFILES[key]
    w, front = f.half_width, f.visor_y
    neck, skull, mask, brow = [Assembly(n) for n in ("Neck", "Housing", "Faceplate", "VisorGuard")]
    neck.pin(DARK, 0, -.085, -.37, .144, .33)
    for z in [-.48, -.385, -.29]:
        neck.pin(STEEL, 0, -.085, z, .158, .033)
    # ヘルメットの下に暗いセンサーユニットを収める。鼻穴・口唇・眼球の形は作らない。
    skull.hull(DARK,(-.246,0,-.018,.196,.20),(-.055,0,-.02,w*.78,.29),
              (.16,0,-.02,w*.93,.33),(.32,0,-.06,w*.92,.31),
              (.47,0,-.092,w*.65,.23))
    skull.hull(ARMOR,(.245,0,-.07,w*.94,.28),(.38,0,-.105,w*.93,.30),
              (.525,0,-.14,w*.65,.23),(.56,0,-.15,w*.39,.13))
    # 一本の額の照準フィンを縦の背骨に埋め込む。
    lean = {"I":-.10,"J":-.25,"K":-.045,"L":-.13}[key]
    skull.hull(PALE,(.37,0,.11,.057,.118),(.525,0,.072,.043,.096),
               (.686,0,.079+lean,.014,.031))
    # 下端の放熱口は顎の裏に斜めに引き込む。水平の唇に見えないよう段差を後退させる。
    mask.hull(DARK,(f.chin_z-.007,0,.105,f.chin_width,.14),
              (-.16,0,.155,w*.59,.16),(.11,0,.158,w*.76,.16))
    for z in [-.254,-.208]:
        mask.hull(STEEL,(z,0,.213,f.chin_width*.94,.072),
                  (z+.017,0,.207,f.chin_width*.98,.074))
    parts=[neck,skull,mask,brow]
    for side in [-1,1]:
        def panel(part, slot, border, peak):
            shell_patch(part,slot,[(side*x,y,z) for x,y,z in border],
                        (side*peak[0],peak[1],peak[2]))
        # 額から後頭部へ続く外殻。色の違う帯ではなく板厚と合わせ目を作る。
        side_rail(skull, ARMOR, side, [
            (f.rear, w*.43,.075,.24,.34),(f.rear+.11,w*.51,w*.33,.20,.49),
            (-.053,w*.49,w*.43,.23,.535),(.179,w*.47,w*.40,.231,.433),
            (.281,w*.40,w*.33,.218,.328)])
        # レンズの枠より少し前へ張り出す庇。先端は左右で途切れ、二眼が独立して見える。
        slope={"I":.039,"J":.055,"K":.004,"L":.029}[key]
        panel(brow,PALE,[(.018,front-.042,.207),(.084,front-.028,.306),
              (w*.77,.124,.366),(w*1.03,-.025,.255),(w*.90,.151,.207+slope),
              (w*.69,.275,.187+slope),(.096,front,.175)],(w*.46,front-.04,.275))
        eye=Assembly("RightOptics" if side>0 else "LeftOptics")
        # レンズは発光する薄い光学窓。目尻をこめかみへ折り返す。
        socket=[(.040,front-.039,.149),(.096,front-.026,.189),
                (w*.74,.246,.199+slope),(w*.90,.165,.184+slope),
                (w*.79,.208,.083+slope),(.112,front-.042,.053)]
        panel(eye,DARK,socket,(w*.43,front-.012,.129))
        lens=[(.079,front-.012,.132),(.12,front-.009,.157),
              (w*.67,.267,.173+slope),(w*.786,.218,.163+slope),
              (w*.665,.267,.114+slope),(.130,front-.014,.096)]
        panel(eye,GLASS,lens,(w*.46,front-.014,.142))
        cheek=Assembly("SideR" if side>0 else "SideL")
        # 面頬は鼻先で途切れず、眼の下から顎まで一続きの稜線を持つ。
        width = {"I":.76,"J":.60,"K":.86,"L":.66}[key]*w
        ridge_y = {"I":.389,"J":.440,"K":.359,"L":.389}[key]
        tone = ARMOR if key=="K" else PALE
        # 目の下から顎へ折った装甲を実際に上下二枚に分ける。
        # 継ぎ目は中央で途切れ、横へ抜ける排気路の底だけが見える。
        slot_z = {"I":-.17,"J":-.13,"K":-.15,"L":-.19}[key]
        panel(mask,tone,[(.012,.317,.146),(.067,.315,.057),(width*.86,.252,.041),
              (width,.185,-.018),(width*.88,.211,slot_z+.060),
              (width*.30,ridge_y-.008,slot_z+.016),(.012,.318,slot_z+.041)],
              (width*.30,ridge_y,-.053))
        panel(mask,DARK,[(.014,.311,slot_z+.047),(width*.88,.204,slot_z+.067),
              (width*.81,.196,slot_z-.008),(.011,.298,slot_z-.063)],
              (width*.32,ridge_y-.042,slot_z+.010))
        panel(mask,tone,[(.012,.314,slot_z+.028),(width*.31,ridge_y-.011,slot_z-.016),
              (width*.86,.208,slot_z+.018),(width*.72,.201,-.235),
              (f.chin_width,.210,f.chin_z),(.012,.262,f.chin_z+.022)],
              (width*.34,ridge_y-.028,slot_z-.056))
        if key=="I":
            side_rail(cheek,ARMOR,side,[(f.rear-.035,.31,.044,-.055,.18),
                      (-.14,.374,.086,-.102,.22),(.08,.365,.070,-.163,.125),
                      (.207,.225,.047,-.250,-.078),(.224,.151,.032,-.305,-.212)])
        elif key=="J":
            # 後方へ長いレールと、下側の二本の支持材の間に実際の空間を残す。
            side_rail(cheek,PALE,side,[(f.rear-.165,.29,.030,.154,.210),
                      (-.30,.339,.067,.105,.249),(.007,.355,.064,.083,.225),
                      (.224,.293,.038,.068,.148)])
            for z in [-.035,-.112]:
                strut(cheek,STEEL,(side*.322,-.21,z+.08),
                      (side*.158,.200,z-.134),.022)
            side_rail(cheek,ARMOR,side,[(-.35,.302,.042,-.069,.039),
                      (-.08,.312,.064,-.131,.051),(.185,.202,.037,-.230,-.112)])
        elif key=="K":
            # 二重の側面装甲で縦長の排気溝をはさむ箱形の頬モジュール。
            side_rail(cheek,ARMOR,side,[(f.rear,.35,.061,-.10,.215),
                      (-.20,.413,.094,-.157,.247),(.065,.414,.103,-.157,.209),
                      (.225,.339,.076,-.194,.095)])
            for z in [-.098,-.032,.033]:
                side_rail(cheek,STEEL,side,[(-.32,.485,.022,z,z+.027),
                          (-.14,.509,.024,z-.016,z+.019),(.055,.513,.018,z-.028,z+.006)])
        else:
            # 外側の板と内側の板を独立させ、側面に長い抜けと重なる先端を作る。
            side_rail(cheek,DARK,side,[(-.40,.336,.054,-.09,.17),
                      (-.18,.37,.085,-.17,.19),(.175,.285,.055,-.23,.002)])
            side_rail(cheek,PALE,side,[(f.rear,.299,.033,.118,.234),
                      (-.215,.395,.054,.033,.235),(.048,.375,.053,-.11,.128),
                      (.265,.189,.036,-.315,-.140)])
            panel(mask,ARMOR,[(.025,.339,.044),(.129,.312,-.022),
                  (.132,.290,-.166),(.048,.267,-.290)],(.077,.409,-.10))
        # アクセスカバーのピンと小さな整備標識。発光するのは光学窓だけ。
        pin_x={"I":.426,"J":.393,"K":.509,"L":.434}[key]
        cheek.pin(DARK,side*pin_x,-.170,.102,.071,.032,"x")
        cheek.pin(STEEL,side*(pin_x+.018),-.170,.102,.046,.018,"x")
        side_rail(cheek,ORANGE,side,[(-.132,pin_x,.010,.13,.15),
                  (-.051,pin_x+.008,.010,.12,.146)])
        parts.extend([eye,cheek])
    # 8組の部品を1個の交換メッシュにまとめ、首の下端と額先を量産機の高さに合わせる。
    objects=[part.build(palette) for part in parts]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join()
    obj=objects[0]
    obj.name="Head_hero"
    obj.data.name="Head_hero"
    for vert in obj.data.vertices:
        vert.co *= .505
        vert.co.z -= .048
    return obj


def aim(obj,target):
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat("-Z","Y").to_euler()


def studio():
    # 全案・全角度で同じ正投影カメラ、背景、三点照明を使う。
    scene=bpy.context.scene
    scene.render.engine="CYCLES"
    scene.cycles.samples=12
    scene.cycles.use_denoising=True
    scene.render.resolution_x=520
    scene.render.resolution_y=460
    scene.render.resolution_percentage=100
    world=bpy.data.worlds.new("Studio")
    scene.world=world
    world.use_nodes=True
    world.node_tree.nodes.get("Background").inputs[0].default_value=(.16,.19,.22,1)
    for loc,power,size in [((2,3,4),270,3),((-3,1,1),160,3),((0,-3,3),320,2)]:
        bpy.ops.object.light_add(type="AREA",location=loc)
        light=bpy.context.object
        light.data.energy=power
        light.data.shape="DISK"
        light.data.size=size
        aim(light,(0,0,0))
    bpy.ops.object.camera_add()
    camera=bpy.context.object
    camera.data.type="ORTHO"
    camera.data.ortho_scale=1.05
    scene.camera=camera
    return scene,camera


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--out",type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    args.out.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    palette=[material("Armor",(.155,.215,.29)),material("Edge",(.46,.54,.59)),
             material("Graphite",(.035,.049,.061),.48,.44),
             material("Steel",(.26,.31,.33),.78,.34),material("Orange",(.80,.17,.032)),
             material("Optics",(.040,.60,.83),.12,.25,1.65)]
    scene,camera=studio()
    for key in PROFILES:
        head=build_face(key,palette)
        bpy.ops.object.select_all(action="DESELECT")
        head.select_set(True)
        bpy.ops.export_scene.gltf(filepath=str(args.out/f"{key}.glb"),export_format="GLB",
                                  use_selection=True)
        for label,angle in [("front",0),("quarter",42),("side",90)]:
            camera.location=(2*sin(radians(angle)),2*cos(radians(angle)),.18)
            aim(camera,(0,0,-.005))
            scene.render.filepath=str(args.out/f"{key}_{label}.png")
            bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(head,do_unlink=True)


if __name__=="__main__":
    main()
