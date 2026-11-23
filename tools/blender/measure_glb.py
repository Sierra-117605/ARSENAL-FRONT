"""glb を高さ 4 に正規化して、高さごとの幅と前後の厚みを measure する。

使い方:
  blender --background --python tools/blender/measure_glb.py -- --glb <file.glb>

画像→3D で起こした立体を「下絵」として使うための道具。
絵からは読み取れない **前後の厚み** まで数値で取れるのが狙い。
出てきた表を SPEC.md §0.18 に写し、tools/blender/mech_hero.py の数値を合わせる。
"""
import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector

# 全高 4 の機体での、各部位のだいたいの高さ（SPEC §0.18 第 46 版の表）
LANDMARKS = [
    (3.90, "頭頂"),
    (3.76, "頭"),
    (3.44, "肩"),
    (3.04, "胸"),
    (2.70, "みぞおち"),
    (2.48, "腰"),
    (2.28, "股関節"),
    (1.90, "腿の上"),
    (1.50, "腿の下"),
    (1.32, "膝"),
    (1.00, "すねの上"),
    (0.60, "すねの下"),
    (0.30, "足首"),
    (0.10, "足"),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--glb", type=Path, required=True)
    parser.add_argument("--spin", type=float, default=0.0)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.glb.resolve()))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        print("メッシュが入っていない")
        return

    points = []
    for obj in meshes:
        mw = obj.matrix_world
        for v in obj.data.vertices:
            points.append(mw @ v.co)

    lo = Vector((min(p[i] for p in points) for i in range(3)))
    hi = Vector((max(p[i] for p in points) for i in range(3)))
    scale = 4.0 / max(hi.z - lo.z, 1e-6)
    cx = (lo.x + hi.x) * .5
    cy = (lo.y + hi.y) * .5
    pts = [((p.x - cx) * scale, (p.y - cy) * scale, (p.z - lo.z) * scale) for p in points]

    # 生成した立体は絵と同じ斜め向きのまま。測る前に正面へ回す。
    # 点群の広がり（共分散）から水平の主軸を求め、それを左右方向にそろえる。
    from math import atan2, cos, sin
    sxx = sum(p[0] * p[0] for p in pts) / len(pts)
    syy = sum(p[1] * p[1] for p in pts) / len(pts)
    sxy = sum(p[0] * p[1] for p in pts) / len(pts)
    theta = 0.5 * atan2(2 * sxy, sxx - syy)
    spin = theta + args.spin * 3.14159265 / 180.0

    def rotate(points, a):
        c, s_ = cos(-a), sin(-a)
        return [(p[0] * c - p[1] * s_, p[0] * s_ + p[1] * c, p[2]) for p in points]

    turned = rotate(pts, spin)
    wide = max(p[0] for p in turned) - min(p[0] for p in turned)
    deep = max(p[1] for p in turned) - min(p[1] for p in turned)
    if wide < deep:
        # 主軸が前後に出た場合は 90 度回して、広いほうを左右にする
        spin += 3.14159265 / 2
        turned = rotate(pts, spin)
    pts = turned

    print(f"頂点 {len(pts)}  元の大きさ {hi - lo}  倍率 {scale:.4f}  "
          f"正面へ回した角度 {spin * 180 / 3.14159265:.1f} 度")
    print("\n高さ      部位        幅      前後の厚み   中心のずれ(前後)")
    band = 0.06
    for z, name in LANDMARKS:
        near = [p for p in pts if abs(p[2] - z) < band]
        if len(near) < 8:
            print(f" {z:4.2f}   {name:<8}   —")
            continue
        xs = [p[0] for p in near]
        ys = [p[1] for p in near]
        width = max(xs) - min(xs)
        depth = max(ys) - min(ys)
        offset = (max(ys) + min(ys)) * .5
        print(f" {z:4.2f}   {name:<8}  {width:5.2f}     {depth:5.2f}      {offset:+5.2f}")

    # 左右に分かれている高さでは、片側だけの幅も見たい（脚・腕の太さ）
    print("\n片側だけ（x>0 側）の幅と、その中心の左右位置")
    for z, name in LANDMARKS:
        near = [p for p in pts if abs(p[2] - z) < band and p[0] > 0.04]
        if len(near) < 8:
            print(f" {z:4.2f}   {name:<8}   —")
            continue
        xs = [p[0] for p in near]
        print(f" {z:4.2f}   {name:<8}  幅 {max(xs) - min(xs):5.2f}   中心 {(max(xs) + min(xs)) * .5:5.2f}")


if __name__ == "__main__":
    main()
