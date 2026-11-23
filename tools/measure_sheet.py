"""三面図から機体の比率を実測する（目分量をなくすため）。

使い方:
  python tools/measure_sheet.py docs/visual_log/13_hero_body/reference/view_sheet.jpg

背景のグラデーションと機体の色差で輪郭を取り、
「全高を 1 としたときの、各高さでの横幅」を出す。Pillow だけで動く。
"""
import sys
from pathlib import Path

from PIL import Image

THRESHOLD = 26
EDGE = 8


def build_mask(path):
    img = Image.open(path).convert("RGB")
    w, h = img.size
    px = img.load()
    mask = []
    for y in range(h):
        # 行の左右の端を背景とみなし、横方向に補間した色との差で機体を拾う。
        lr = lg = lb = rr = rg = rb = 0
        for x in range(EDGE):
            r, g, b = px[x, y]
            lr, lg, lb = lr + r, lg + g, lb + b
            r, g, b = px[w - 1 - x, y]
            rr, rg, rb = rr + r, rg + g, rb + b
        lr, lg, lb = lr / EDGE, lg / EDGE, lb / EDGE
        rr, rg, rb = rr / EDGE, rg / EDGE, rb / EDGE
        row = bytearray(w)
        for x in range(w):
            t = x / (w - 1)
            br = lr + (rr - lr) * t
            bg = lg + (rg - lg) * t
            bb = lb + (rb - lb) * t
            r, g, b = px[x, y]
            if abs(r - br) + abs(g - bg) + abs(b - bb) > THRESHOLD:
                row[x] = 1
        mask.append(row)
    return mask, w, h


def split_columns(mask, w, h):
    counts = [sum(mask[y][x] for y in range(h)) for x in range(w)]
    limit = max(3, max(counts) * 0.02)
    groups, start = [], None
    for x, c in enumerate(counts):
        if c > limit and start is None:
            start = x
        elif c <= limit and start is not None:
            if x - start > w * 0.05:
                groups.append((start, x))
            start = None
    if start is not None:
        groups.append((start, w))
    return groups


def report(mask, h, x0, x1, title):
    rows = [y for y in range(h) if any(mask[y][x0:x1])]
    top, bottom = rows[0], rows[-1]
    height = bottom - top
    print(f"\n[{title}]  横 {x0}-{x1}  全高 {height}px")
    print("  高さ（頭頂 0.00 / 足裏 1.00） : 横幅（全高を 1 としたときの比）")
    for ratio in [0.04, 0.10, 0.16, 0.22, 0.28, 0.34, 0.40, 0.46,
                  0.52, 0.58, 0.64, 0.72, 0.80, 0.88, 0.96]:
        y = int(top + height * ratio)
        xs = [x for x in range(x0, x1) if mask[y][x]]
        if not xs:
            print(f"   {ratio:.2f} : —")
            continue
        print(f"   {ratio:.2f} : {(xs[-1] - xs[0]) / height:.3f}")


def main():
    path = Path(sys.argv[1])
    mask, w, h = build_mask(path)
    groups = split_columns(mask, w, h)
    print(f"画像 {w}x{h}  見つかった機体 {len(groups)} 体")
    names = ["左（斜め）", "中央（正面）", "右（背面）"]
    for i, (x0, x1) in enumerate(groups):
        report(mask, h, x0, x1, names[i] if i < len(names) else f"#{i}")


if __name__ == "__main__":
    main()
