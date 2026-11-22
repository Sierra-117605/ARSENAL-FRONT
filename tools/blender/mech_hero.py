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


# 顔幅、顎角の幅、顎先、後頭部の長さ、目尻の高さを独立に設計する。
class Face(NamedTuple):
    width: float
    jaw: float
    chin: float
    occiput: float
    eye_tilt: float


PROFILES = {
    "E": Face(.39, .275, -.335, .39, .018),
    "F": Face(.41, .335, -.310, .42, -.005),
    "G": Face(.335, .215, -.369, .37, .051),
    "H": Face(.46, .345, -.332, .51, .032),
}
ARMOR, PALE, DARK, STEEL, ORANGE, GLASS = range(6)


def shell_patch(part, slot, border, peak, thickness=.04):
    """顔の折れ面。各頂点を別々の奥行きに置いて鼻筋や頬骨を実際に張り出す。"""
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


def build_face(key, palette):
    f = PROFILES[key]
    w = f.width
    neck, skull, mask, brow = [Assembly(n) for n in ("Neck", "Cranium", "Maxilla", "Brow")]
    neck.pin(DARK, 0, -.085, -.37, .144, .33)
    for z in [-.48, -.385, -.29]:
        neck.pin(STEEL, 0, -.085, z, .158, .033)
    # 後頭部を丸く包む面の輪。眼窩の高さで前面を後退させ、鼻と唇に側面の段を作る。
    sections = [(-.26,.52,.13,.075),(-.10,.82,.28,.105),(.115,.97,.36,.105),
                (.29,1,.41,.170),(.43,.90,.36,.185),(.535,.66,.28,.13),(.57,.32,.14,.06)]
    rings = []
    for z, width, rear, front in sections:
        ring = []
        for i in range(16):
            a = tau*i/16
            depth = front if cos(a)>0 else rear*f.occiput/.39
            ring.append((w*width*sin(a), -.035+depth*cos(a), z))
        rings.append(ring)
    skull.loft(DARK if key=="F" else ARMOR, rings)
    if key=="H":
        # 幅広の工業型は額の左右を張る。中央を切り欠いて鼻筋を露出する。
        skull.hull(ARMOR,(.31,0,-.09,w,.27),(.43,0,-.10,w*1.08,.32),
                  (.50,0,-.18,w*.81,.30))
    # 控えめな一本の額突起を額の面から後ろへ流す。
    lean = {"E":-.04, "F":-.12, "G":.01, "H":-.19}[key]
    skull.hull(PALE,(.37,0,.11,.040,.085),(.53,0,.065,.035,.083),
               (.686,0,.035+lean,.013,.036))
    # 鼻根→鼻梁→鼻先→鼻下。平たい顔面板に鼻を描かず、横からも凹凸を出す。
    bridge = .411 if key=="F" else .465 if key=="H" else .446
    mask.hull(STEEL if key=="F" else PALE,(-.095,0,.296,.072,.052),(-.055,0,.356,.094,bridge-.356),
              (.002,0,.344,.056,.088),(.157,0,.285,.038,.057),
              (.215,0,.245,.061,.058))
    # 人の口に相当する高さに通気口を置き、上下の面構成は顔ごとに変える。
    if key in ("E", "G"):
        lip = .153 if key=="E" else .118
        z = -.172 if key=="E" else -.183
        for side in [-1,1]:
            upper_lip = [(0,.322,-.107),(side*.065,.334,-.101),
                         (side*lip,.287,z+.011),(side*lip,.287,z-.007),
                         (side*.055,.345,z+.008),(0,.347,z+.003)]
            shell_patch(mask,ARMOR,upper_lip,(side*.064,.351,z+.029))
        mask.hull(DARK,(z-.047,0,.268,lip*.91,.075),(z+.005,0,.265,lip,.071))
        mask.hull(PALE,(f.chin,0,.211,lip*.54,.061),(f.chin+.031,0,.247,lip*.86,.083),
                  (z-.060,0,.260,lip*.97,.085),(z-.026,0,.265,lip*.74,.058))
    elif key=="F":
        # 中央の細い桟を通した吸気口。下側のフレームから顎リンクへ力が伝わる形。
        mask.hull(DARK,(-.267,0,.224,.113,.076),(-.192,0,.267,.158,.079),
                  (-.092,0,.263,.125,.073))
        for x in [-.095,-.046,0,.046,.095]:
            strut(mask,STEEL,(x*.76,.321,-.228),(x,.336,-.122),.011)
        mask.hull(ARMOR,(f.chin,0,.205,.094,.060),(-.263,0,.243,.147,.083),
                  (-.241,0,.253,.136,.075))
    else:
        # 一体の防護マスクには、横スリットを挟んで前面が連続する顎板を設ける。
        mask.hull(ARMOR,(-.317,0,.229,.150,.107),(-.251,0,.258,.217,.126),
                  (-.175,0,.267,.213,.110))
        mask.hull(DARK,(-.177,0,.268,.182,.105),(-.143,0,.274,.176,.105))
        mask.hull(PALE,(-.145,0,.274,.187,.122),(-.105,0,.268,.174,.106),
                  (-.070,0,.263,.104,.065))
    parts=[neck,skull,mask,brow]
    for side in [-1,1]:
        def patch(part, slot, corners, center):
            shell_patch(part,slot,[(side*x,y,z) for x,y,z in corners],
                        (side*center[0],center[1],center[2]))
        # 左右の額は眉間に下る。眉は眼窩の直上、外側はこめかみに回り込む。
        temple=w*.98
        patch(brow, ARMOR, [(0,.236,.235),(.045,.251,.375),(.14,.144,.518),
                            (w*.75,.042,.454),(temple,-.007,.287),(w*.79,.169,.248),
                            (.125,.289,.235)], (w*.48,.231,.362))
        upper=.206+f.eye_tilt
        patch(brow, PALE, [(.039,.294,.182),(.128,.302,.255),(w*.73,.215,upper+.071),
                           (temple,.049,upper+.018),(w*.80,.182,upper),
                           (.117,.306,.181)], (w*.49,.288,upper+.032))
        eye=Assembly("RightOptics" if side>0 else "LeftOptics")
        # 杏仁形の眼窩に、わずかに奥まった二つの光学窓をはめる。
        socket=[(.057,.285,.119),(.112,.287,.183),(w*.72,.206,upper),
                (w*.84,.154,upper-.020),(w*.73,.206,.089+f.eye_tilt),
                (.143,.284,.061)]
        patch(eye,DARK,socket,(.168,.294,.132))
        lens=[(.091,.302,.127),(.143,.296,.163),(w*.69,.231,.173+f.eye_tilt),
              (w*.75,.211,.162+f.eye_tilt),(w*.59,.260,.102+f.eye_tilt),
              (.149,.298,.094)]
        if key=="F":
            # 眼窩の中に双眼カメラを取り付け、前側に金属の鏡筒を残す。
            for slot, radius, depth in [(STEEL,.071,.300),(DARK,.058,.313),(GLASS,.044,.325)]:
                eye.loft(slot, [[(side*.175+radius*cos(tau*i/16),y,
                                  .133+radius*sin(tau*i/16)) for i in range(16)]
                                for y in [depth-.023,depth+.006]])
        else:
            if key=="H":
                lens=[(x,y,.136+(z-.136)*.54) for x,y,z in lens]
            patch(eye,GLASS,lens,(w*.47,.305,.142))
        cheek=Assembly("RightMandible" if side>0 else "LeftMandible")
        # 頬骨は眼窩の下に張り、頬は口の横でくぼむ。後端は耳の軸につなぐ。
        patch(cheek,PALE if key!="F" else ARMOR,
              [(.094,.294,.062),(w*.64,.243,.087+f.eye_tilt),(w*.88,.135,.126),
               (w*1.01,.012,.058),(w*.79,.111,-.078),(.155,.259,-.134),
               (.104,.312,-.067)],(w*.63,.302,.005))
        jaw=f.jaw
        if key=="F":
            # 開放顎。鋳物の外側に二本のリンクが見える。
            for dy,dz in [(0,0),(-.037,-.065)]:
                strut(cheek,STEEL,(side*w*.93,-.046,.032+dz),
                      (side*.146,.242+dy,-.222+dz),.028)
            patch(cheek,ARMOR,[(w*.92,-.095,-.06),(jaw,.01,-.19),
                  (.117,.254,f.chin+.016),(.21,.172,-.29)],(jaw,.00,-.202))
        else:
            patch(cheek,ARMOR,
                  [(w*.96,-.075,.026),(w*.86,.09,-.095),(.155,.260,-.157),
                   (.113,.264,f.chin+.018),(jaw,.064,-.246),(w*.91,-.106,-.121)],
                  (jaw,.094,-.177))
        # 側頭部の工業的な構造は顔面より後方に置く。
        ear_x=w*.91
        cheek.pin(DARK,side*ear_x,-.10,.109,.121,.095,"x")
        cheek.pin(STEEL,side*(ear_x+.05),-.10,.109,.082,.023,"x")
        cheek.pin(ORANGE,side*(ear_x+.064),-.10,.109,.037,.012,"x")
        if key=="G":
            # 頬から顎先まで細長い一枚を通し、細面の横顔を作る。
            patch(cheek,PALE,[(w*.94,.086,.145),(w*.81,.180,.063),
                  (.131,.289,-.176),(.096,.267,-.322),(.204,.184,-.235),
                  (w*.96,.037,-.052)],(w*.74,.214,-.080))
        if key=="H":
            patch(cheek,ARMOR,[(w*1.06,-.18,.12),(w*1.13,.008,.053),
                  (w*.70,.240,-.122),(.173,.283,-.267),(w*.86,-.04,-.237)],
                  (w*.90,.102,-.111))
            for z in [.04,.13,.22]:
                cheek.hull(ARMOR,(z,side*w*.88,-.20,.081,.185),
                           (z+.046,side*w*.89,-.245,.094,.216))
        elif key=="G":
            cheek.hull(PALE,(.12,side*w*.91,-.12,.045,.115),
                       (.39,side*w*.92,-.16,.055,.17),(.51,side*w*.79,-.20,.026,.092))
        elif key=="E":
            strut(cheek,DARK,(side*.20,.032,-.238),(side*.14,-.07,-.411),.040)
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
    palette=[material("Armor",(.29,.36,.43)),material("Edge",(.46,.54,.59)),
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
