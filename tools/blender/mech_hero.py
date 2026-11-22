"""主役機の頭部を単体で造形し、同一照明・同一倍率で選定用に撮影する。"""
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


# 庇と側面を個別に設計する。輪郭は正面の片側だけを定義し、左右を鏡像にする。
PROFILES = {
    "A": dict(width=.54, depth=.43, brow=.54, jaw=.27, crown=.47,
              brow_edge=[(.012,.23),(.17,.40),(.48,.38),(.59,.24),(.30,.24),(.10,.17)],
              lens=[(.10,.14),(.37,.21),(.43,.19),(.35,.10),(.13,.075)],
              cheek=[(.21,-.14),(.48,.01),(.57,.24),(.49,.29),(.37,.10),(.23,.01)]),
    "B": dict(width=.68, depth=.37, brow=.47, jaw=.38, crown=.39,
              brow_edge=[(.025,.15),(.11,.29),(.56,.31),(.70,.20),(.62,.13),(.12,.10)],
              lens=[(.15,.085),(.49,.115),(.54,.077),(.50,.00),(.16,-.005)],
              cheek=[(.37,-.16),(.62,-.11),(.69,.05),(.67,.18),(.53,.12),(.42,.00)]),
    "C": dict(width=.425, depth=.39, brow=.48, jaw=.19, crown=.48,
              brow_edge=[(.025,.26),(.09,.45),(.32,.49),(.44,.34),(.35,.25),(.12,.20)],
              lens=[(.11,.17),(.21,.25),(.30,.22),(.265,.07),(.15,.025),(.105,.07)],
              cheek=[(.12,-.22),(.35,-.04),(.45,.23),(.38,.32),(.29,.08),(.17,-.025)]),
    "D": dict(width=.53, depth=.63, brow=.69, jaw=.25, crown=.34,
              brow_edge=[(.02,.20),(.24,.32),(.52,.26),(.57,.13),(.38,.11),(.12,.125)],
              lens=[(.12,.081),(.30,.13),(.40,.08),(.36,-.005),(.19,-.025)],
              cheek=[(.20,-.18),(.42,-.13),(.57,.025),(.52,.17),(.39,.075),(.24,-.02)]),
}
ARMOR, PALE, DARK, STEEL, ORANGE, GLASS = range(6)


def build_face(key,palette):
    p=PROFILES[key]
    w,d,h=p["width"],p["depth"],p["crown"]
    neck=Assembly("Neck")
    neck.pin(DARK,0,-.06,-.37,.185,.34)
    for z in [-.48,-.37,-.265]:
        neck.pin(STEEL,0,-.06,z,.205,.044)
    for sign in [-1,1]:
        neck.pin(STEEL,.15*sign,.07,-.34,.039,.22)
    mask=Assembly("Mask")
    mask.hull(DARK,(-.245,0,-.035,.24,.23),(-.06,0,0,.80*w,d*.82),
              (.24,0,-.015,w*.92,d),(.41,0,-.045,w*.75,d*.76))
    eye_y=p["brow"]-.095
    jaw=p["jaw"]
    # 中央の稜線と段差の奥の横スリットを、独立した上下の唇で縁取る。
    mask.plate(ARMOR,[(-jaw,.012),(-.10,.14),(0,.22),(.10,.14),(jaw,.012),
                     (.56*jaw,-.13),(0,-.18),(-.56*jaw,-.13)],.12,eye_y-.12,.09)
    mask.hull(PALE,(-.207,0,eye_y-.135,jaw*.53,.075),
              (-.151,0,eye_y-.118,jaw*.71,.09))
    mask.plate(DARK,[(-jaw*.55,-.145),(jaw*.55,-.145),(jaw*.56,-.114),(-jaw*.56,-.114)],
               eye_y-.043,eye_y+.005)
    # 細い縦の峰は左右で別の向きに光を返す。下端の通風口と連続させる。
    mask.hull(PALE, (-.112,0,eye_y-.015,.050,.076), (.028,0,eye_y-.018,jaw*.52,.142),
              (.172,0,eye_y-.057,.04,.090))
    crown=Assembly("Crown")
    crown.hull(ARMOR,(.16,0,-.07,w*.85,d*.88),(.31,0,-.09,w,d),
               (h+.095,0,-.16,w*.59,d*.70))
    # 1本の短い額突起。前後の傾斜を変えて側面からも識別できるようにする。
    lean={"A":-.09,"B":-.01,"C":.07,"D":-.32}[key]
    crown.hull(PALE,(.26,0,.13,.063,.145),(h+.07,0,.09,.048,.118),
               (.69,0,.09+lean,.018,.052))
    crown.hull(ORANGE,(.33,0,.239,.030,.045),(.385,0,.209,.029,.052))
    brow=Assembly("Brow")
    parts=[neck,mask,crown,brow]
    for sign in [-1,1]:
        def mirror(outline):
            return [(sign*x,z) for x,z in outline]
        brow.plate(PALE,mirror(p["brow_edge"]),-.19,p["brow"],.038)
        eye=Assembly("LensL" if sign<0 else "LensR")
        points=mirror(p["lens"])
        ex=sum(x for x,z in points)/len(points)
        ez=sum(z for x,z in points)/len(points)
        frame=[(ex+(x-ex)*1.19,ez+(z-ez)*1.42) for x,z in points]
        eye.plate(DARK,frame,.12,eye_y+.012,.020)
        eye.plate(GLASS,points,eye_y+.031,eye_y+.049,.012)
        cheek=Assembly("TempleL" if sign<0 else "TempleR")
        cheek.plate(ARMOR,mirror(p["cheek"]),-d*.85,eye_y-.06,.035)
        cheek.pin(DARK,sign*w*.92,-.13,.115,.136,.15,"x")
        cheek.pin(STEEL,sign*(w*.92+.078),-.13,.115,.081,.030,"x")
        # 回転軸のキャップに小さな整備用の差し色を入れる。
        cheek.pin(ORANGE,sign*(w*.92+.100),-.13,.115,.040,.016,"x")
        # 側頭部の後端処理で横顔にも差を付ける。
        if key=="B":
            for z in [-.035,.065,.165]:
                cheek.hull(PALE,(z,sign*w*.86,-.25,.12,.22),
                           (z+.045,sign*w*.87,-.285,.135,.24))
        elif key=="D":
            cheek.hull(PALE,(.01,sign*.42,-.33,.09,.23),(.16,sign*.45,-.42,.11,.37),
                       (.22,sign*.40,-.58,.065,.26))
        elif key=="C":
            cheek.hull(PALE,(.15,sign*.33,-.08,.075,.14),(.42,sign*.345,-.16,.085,.20),
                       (.58,sign*.30,-.25,.048,.115))
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
