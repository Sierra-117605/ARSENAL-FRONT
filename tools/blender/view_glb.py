"""glb を読み込んで、正面・斜め・真横の 3 枚を同じ条件で撮る確認用ツール。

使い方:
  blender --background --python tools/blender/view_glb.py -- --glb <file.glb> --out <出力先>

画像→3D で作ったメッシュを、これまでの比較画像と同じ撮り方で確認するために使う。
"""
import argparse
import sys
from math import radians, sin, cos
from pathlib import Path

import bpy
from mathutils import Vector


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--glb", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--spin", type=float, default=0.0, help="Z 軸まわりに回す角度")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.glb.resolve()))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        print("メッシュが入っていない")
        return

    # 全体を原点に置き、高さ 4 に正規化する（これまでの機体と同じ尺度にそろえる）
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in meshes:
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            lo = Vector((min(lo[i], p[i]) for i in range(3)))
            hi = Vector((max(hi[i], p[i]) for i in range(3)))
    size = hi - lo
    scale = 4.0 / max(size.z, 1e-6)
    center = (lo + hi) * 0.5

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.location -= center
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    body.scale = (scale, scale, scale)
    body.rotation_euler.z = radians(args.spin)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    body.location.z = 2.0

    # 素の形が見えるように、つや消しの単色だけを当てる
    mat = bpy.data.materials.new("Clay")
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (.30, .345, .395, 1)
    shader.inputs["Roughness"].default_value = .76
    body.data.materials.clear()
    body.data.materials.append(mat)

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
    for loc, power, size_ in [((7, 9, 12), 3000, 8), ((-9, 4, 4), 1700, 8), ((0, -9, 9), 3000, 6)]:
        bpy.ops.object.light_add(type="AREA", location=loc)
        light = bpy.context.object
        light.data.energy = power
        light.data.shape = "DISK"
        light.data.size = size_
        aim(light, (0, 0, 2))
    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 5.6
    scene.camera = camera

    for label, angle in [("front", 0), ("quarter", 38), ("side", 90)]:
        camera.location = (9 * sin(radians(angle)), 9 * cos(radians(angle)), 2.3)
        aim(camera, (0, 0, 2.1))
        scene.render.filepath = str(args.out / f"body_{label}.png")
        bpy.ops.render.render(write_still=True)
    print("面数", len(body.data.polygons))


if __name__ == "__main__":
    main()
