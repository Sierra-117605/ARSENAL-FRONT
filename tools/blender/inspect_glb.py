"""機体モデルの検査（Blender 側）。監督役 tools/inspect_mech.py から呼ばれる。

やること
  1. 部位の名前・面数・寸法を調べて JSON で出す
  2. 左右対称性を測る
  3. 普段見ない角度を含む 8 方向を撮る（背面・真上・真下を必ず含める）

使い方:
  blender --background --python tools/blender/inspect_glb.py -- --glb <file.glb> --out <出力先>
"""
import argparse
import json
import sys
from math import radians, sin, cos
from pathlib import Path

import bpy
from mathutils import Vector

# 普段見ない角度を必ず入れる（はみ出しばかり見て裏側を見落とさないため）
VIEWS = [
    ("front", 0, 2.3), ("quarter", 38, 2.3), ("side", 90, 2.3),
    ("rear_quarter", 142, 2.3), ("rear", 180, 2.3),
    ("high", 38, 7.5), ("top", 0, 13.0), ("bottom", 0, -7.0),
]


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def studio():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 12
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 360
    scene.render.resolution_y = 500
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


def symmetry_score(points):
    """左右対称性。x を反転した点が元の点群にどれだけ近いかを粗く測る（0〜1、1 が対称）。"""
    if not points:
        return 0.0
    cells = set()
    step = 0.08
    for x, y, z in points:
        cells.add((round(x / step), round(y / step), round(z / step)))
    hit = sum(1 for cx, cy, cz in cells if (-cx, cy, cz) in cells)
    return hit / max(len(cells), 1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--glb", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--shots", type=int, default=1)
    # 下絵（画像から起こした立体）は大きさがばらばらなので、比べる前にそろえる
    parser.add_argument("--normalize", type=int, default=0)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.glb.resolve()))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]

    report = {"glb": str(args.glb), "parts": {}, "faces_total": 0}
    all_points = []
    for obj in meshes:
        mw = obj.matrix_world
        pts = [mw @ v.co for v in obj.data.vertices]
        all_points.extend((p.x, p.y, p.z) for p in pts)
        lo = Vector((min(p[i] for p in pts) for i in range(3)))
        hi = Vector((max(p[i] for p in pts) for i in range(3)))
        report["parts"][obj.name] = {
            "faces": len(obj.data.polygons),
            "min": [round(v, 3) for v in lo],
            "max": [round(v, 3) for v in hi],
            "size": [round(hi[i] - lo[i], 3) for i in range(3)],
            "center": [round((hi[i] + lo[i]) * .5, 3) for i in range(3)],
        }
        report["faces_total"] += len(obj.data.polygons)

    if all_points:
        lo = [min(p[i] for p in all_points) for i in range(3)]
        hi = [max(p[i] for p in all_points) for i in range(3)]
        report["bounds"] = {"min": [round(v, 3) for v in lo], "max": [round(v, 3) for v in hi],
                            "size": [round(hi[i] - lo[i], 3) for i in range(3)]}
        report["symmetry"] = round(symmetry_score(all_points), 3)

    (args.out / "inspect.json").write_text(json.dumps(report, ensure_ascii=False, indent=1),
                                           encoding="utf-8")

    if args.normalize and meshes:
        lo = [min(p[i] for p in all_points) for i in range(3)]
        hi = [max(p[i] for p in all_points) for i in range(3)]
        scale = 4.0 / max(hi[2] - lo[2], 1e-6)
        bpy.ops.object.select_all(action="DESELECT")
        for obj in meshes:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        bpy.ops.object.join()
        body = bpy.context.view_layer.objects.active
        body.location -= Vector(((lo[0] + hi[0]) * .5, (lo[1] + hi[1]) * .5, lo[2]))
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
        body.scale = (scale, scale, scale)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    if args.shots:
        scene, camera = studio()
        for label, angle, height in VIEWS:
            if label == "top":
                camera.location = (0, .001, height)
            elif label == "bottom":
                camera.location = (0, .001, height)
            else:
                camera.location = (9 * sin(radians(angle)), 9 * cos(radians(angle)), height)
            aim(camera, (0, 0, 2.0))
            scene.render.filepath = str(args.out / f"view_{label}.png")
            bpy.ops.render.render(write_still=True)
    print("inspect done", report["faces_total"], "faces")


if __name__ == "__main__":
    main()
