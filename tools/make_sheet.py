"""頭部の三面と参考画を 1 枚の比較画像にまとめる。

使い方（プロジェクト直下で）:
  python tools/make_sheet.py <出力フォルダ>

<出力フォルダ> にある head_front.png / head_quarter.png / head_side.png を横に並べ、
その上に決定稿の絵（docs/visual_log/11_hero_face/reference/ref_03_final.jpg）を載せた
compare.jpg と、ゲーム内の大きさに縮めた small.jpg を作る。
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
REFERENCE = ROOT / "docs/visual_log/11_hero_face/reference/ref_03_final.jpg"
BACKGROUND = (26, 31, 37)
LABELS = [("head_front.png", "正面"), ("head_quarter.png", "斜め 42 度"), ("head_side.png", "真横")]


def main():
    # 第2引数に接頭辞（head / body）、第3引数に並べる参考画を渡せる。
    out = Path(sys.argv[1])
    prefix = sys.argv[2] if len(sys.argv) > 2 else "head"
    reference_path = Path(sys.argv[3]) if len(sys.argv) > 3 else REFERENCE
    labels = [(name.replace("head_", prefix + "_"), label) for name, label in LABELS]
    globals()["LABELS"] = labels
    globals()["REFERENCE"] = reference_path
    shots = [Image.open(out / name).convert("RGB") for name, _ in labels]
    w, h = shots[0].size
    row = Image.new("RGB", (w * len(shots), h), BACKGROUND)
    for i, shot in enumerate(shots):
        row.paste(shot, (i * w, 0))

    reference = Image.open(reference_path).convert("RGB")
    ref_h = round(reference.height * row.width / reference.width)
    reference = reference.resize((row.width, ref_h), Image.LANCZOS)

    band = 34
    sheet = Image.new("RGB", (row.width, ref_h + band * 2 + h), BACKGROUND)
    sheet.paste(reference, (0, band))
    sheet.paste(row, (0, ref_h + band * 2))
    draw = ImageDraw.Draw(sheet)
    draw.text((10, 10), "決定稿の絵（ref_03_final.jpg）", fill=(225, 230, 235))
    draw.text((10, ref_h + band + 10), "  /  ".join(label for _, label in LABELS),
              fill=(225, 230, 235))
    sheet.save(out / "compare.jpg", quality=92)

    # ゲーム内で頭が見える程度の大きさ（横 96px 相当）に縮めて、輪郭が読めるか確かめる。
    small_w = 96
    tiles = []
    for shot in shots:
        tiles.append(shot.resize((small_w, round(h * small_w / w)), Image.LANCZOS))
    small = Image.new("RGB", (small_w * len(tiles), tiles[0].height), BACKGROUND)
    for i, tile in enumerate(tiles):
        small.paste(tile, (i * small_w, 0))
    small.resize((small.width * 3, small.height * 3), Image.NEAREST).save(
        out / "small.jpg", quality=92)
    print("ok", out / "compare.jpg", out / "small.jpg")


if __name__ == "__main__":
    main()
