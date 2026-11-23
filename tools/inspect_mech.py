"""機体モデルの監督役。ひとつの指標だけを追って他を壊していないかを毎回まとめて見る。

開発者の指示（2026-11-23）
  「はみ出しをなくすのもいいけど、それに意識を取られすぎて隠れた部分を見逃さないように」

使い方（プロジェクト直下で）:
  python tools/inspect_mech.py
  python tools/inspect_mech.py --no-render    # 画像を撮らず、数値の検査だけ

出すもの
  docs/visual_log/inspection/report.md     検査結果（OK / 注意 / NG）
  docs/visual_log/inspection/hero/         主役機の 8 方向（背面・真上・真下を含む）
  docs/visual_log/inspection/mass/         量産機の 8 方向
  docs/visual_log/inspection/sheet.jpg     8 方向を 1 枚に並べたもの

検査する項目
  A 見た目  1 下絵とのシルエット一致（はみ出し率・不足率）
            2 普段見ない角度の絵を残す（人が見落とさないため）
            3 左右対称性
  B 構造    4 Godot が必要とする部位名がそろっているか
            5 面数とファイルサイズ
            6 部位同士のめり込み
  C 整合    7 SPEC §0.18 の表と robot.gd / robot.tscn の実値が一致しているか
            8 当たり判定の位置が見た目の部位とずれていないか
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BLENDER = Path(r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe")
OUT = ROOT / "docs/visual_log/inspection"
REFERENCE_GLB = ROOT / "docs/visual_log/14_image_to_3d/models/hero_ref.glb"

# Godot 側が読む部位名（scripts/action/mech_detail.gd の MODEL_PARTS と合わせる）
REQUIRED_MASS = ["Torso", "Hip", "Head", "ShoulderL", "ShoulderR", "ArmL", "ArmR",
                 "Barrel", "LegL", "LegR", "FootL", "FootR", "BackPack", "Visor"]
REQUIRED_HERO = ["Torso", "Hip", "Head_hero", "ShoulderL", "ShoulderR", "ArmL", "ArmR",
                 "Barrel", "LegL", "LegR", "FootL", "FootR", "BackPack"]

MAX_FACES = 120000      # 1 機の面数の上限（目安）
MAX_BYTES = 2_000_000   # 1 機のファイルサイズの上限（SPEC は 1MB 目安、警告は 2MB で）
MIN_SYMMETRY = 0.80     # 左右対称性の下限
# 設計上かならず重なる組（Visor は顔の上に載る板、Barrel は腕に差し込む）
OVERLAP_OK = {("Head", "Visor"), ("Head_hero", "Visor"), ("ArmR", "Barrel"), ("ArmL", "Barrel")}

findings = []


def note(level, title, detail):
    findings.append((level, title, detail))


# ---------------------------------------------------------------- C 整合
def check_numbers():
    """SPEC の表と、robot.gd / robot.tscn の実値を突き合わせる。"""
    spec = (ROOT / "SPEC.md").read_text(encoding="utf-8")
    gd = (ROOT / "scripts/action/robot.gd").read_text(encoding="utf-8")
    tscn = (ROOT / "scenes/robot.tscn").read_text(encoding="utf-8")

    # robot.gd の当たり判定の実値
    actual = {}
    for name in ("HitHead", "HitArmL", "HitArmR", "HitLegs"):
        m = re.search(r'"%s":\s*Vector3\(([^)]*)\)' % name, gd)
        if m:
            actual[name] = [float(v) for v in m.group(1).split(",")]
    if len(actual) < 4:
        note("NG", "当たり判定が読めない", "robot.gd の BASE_PART_POS を見つけられなかった")
        return

    # SPEC の表に書いてある値
    def spec_value(pattern):
        m = re.search(pattern, spec)
        return m.group(1) if m else None

    head = spec_value(r"\|\s*`HitHead`\s*\|[^|]*\|\s*\*\*\(([^)]*)\)\*\*")
    arm = spec_value(r"\|\s*`HitArmL/R`\s*\|[^|]*\|\s*\*\*\(([^)]*)\)\*\*")
    legs = spec_value(r"\|\s*`HitLegs`\s*\|[^|]*\|\s*\*\*\(([^)]*)\)\*\*")

    def same(a, b_text, label):
        if b_text is None:
            note("注意", f"SPEC に {label} の行がない", "表を書き足すこと")
            return
        nums = [float(v.replace("±", "")) for v in re.findall(r"[-+]?\d*\.?\d+", b_text)]
        if len(nums) != 3:
            note("注意", f"SPEC の {label} が読めない", b_text)
            return
        if any(abs(abs(a[i]) - abs(nums[i])) > 0.011 for i in range(3)):
            note("NG", f"SPEC の表と実物が違う（{label}）",
                 f"SPEC {nums} ／ robot.gd {a}。表を実物に合わせること")

    same(actual["HitHead"], head, "HitHead")
    same(actual["HitArmL"], arm, "HitArmL/R")
    same(actual["HitLegs"], legs, "HitLegs")

    # 見た目（robot.tscn）の部位位置と、当たり判定の位置が大きくずれていないか
    def node_pos(name, parent="Visual"):
        pat = r'\[node name="%s"[^\]]*parent="%s"\]\ntransform = Transform3D\(([^)]*)\)' % (name, parent)
        m = re.search(pat, tscn)
        if not m:
            return None
        nums = [float(v) for v in m.group(1).split(",")]
        return nums[9:12]

    pairs = [("Head", actual["HitHead"], "頭"), ("ArmL", actual["HitArmL"], "左腕")]
    for node, hit, label in pairs:
        pos = node_pos(node)
        if pos is None:
            note("注意", f"{label} のノードが読めない", f"robot.tscn の {node}")
            continue
        gap = max(abs(pos[i] - hit[i]) for i in range(3))
        if gap > 0.25:
            note("NG", f"{label}：見た目と当たり判定がずれている",
                 f"見た目 {pos} ／ 当たり判定 {hit}（差 {gap:.2f}）")


# ---------------------------------------------------------------- B 構造
def check_structure(tag, glb, required, data):
    size = glb.stat().st_size
    if size > MAX_BYTES:
        note("注意", f"{tag}：ファイルが大きい", f"{size/1_000_000:.2f} MB（目安 1MB）")
    if data["faces_total"] > MAX_FACES:
        note("注意", f"{tag}：面数が多い", f"{data['faces_total']} 面（目安 {MAX_FACES}）")

    names = set(data["parts"])
    missing = [n for n in required if n not in names]
    if missing:
        note("NG", f"{tag}：部位が足りない", "／".join(missing))
    extra = [n for n in names if n not in required]
    if extra:
        note("注意", f"{tag}：余計な部位がある", "／".join(extra))

    sym = data.get("symmetry", 0)
    if sym < MIN_SYMMETRY:
        note("注意", f"{tag}：左右が非対称", f"対称度 {sym:.2f}（下限 {MIN_SYMMETRY}）")

    # 部位同士のめり込み（箱の重なりが片方の体積の 6 割を超えたら知らせる）
    items = [(n, p) for n, p in data["parts"].items()]
    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            na, a = items[i]
            nb, b = items[j]
            over = 1.0
            for k in range(3):
                lo = max(a["min"][k], b["min"][k])
                hi = min(a["max"][k], b["max"][k])
                over *= max(0.0, hi - lo)
            if over <= 0:
                continue
            va = max(a["size"][0] * a["size"][1] * a["size"][2], 1e-6)
            vb = max(b["size"][0] * b["size"][1] * b["size"][2], 1e-6)
            ratio = over / min(va, vb)
            if (na, nb) in OVERLAP_OK or (nb, na) in OVERLAP_OK:
                continue
            if ratio > 0.60:
                note("注意", f"{tag}：{na} と {nb} が深くめり込んでいる",
                     f"小さいほうの {ratio*100:.0f}% が埋まっている")

    # 全高が 4 から大きく外れていないか
    height = data.get("bounds", {}).get("size", [0, 0, 0])[2]
    if height and abs(height - 4.0) > 0.6:
        note("注意", f"{tag}：全高が基準から外れている", f"{height:.2f}（基準 4.0）")


# ---------------------------------------------------------------- A 見た目
def silhouette(path, threshold=26):
    img = Image.open(path).convert("RGB")
    w, h = img.size
    px = img.load()
    base = px[2, 2]
    mask = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if abs(r - base[0]) + abs(g - base[1]) + abs(b - base[2]) > threshold:
                mask[y * w + x] = 1
    return mask, w, h


def check_silhouette(mine, reference):
    """下絵と自分の影を比べ、はみ出し率と不足率を出す。"""
    if not mine.exists() or not reference.exists():
        note("注意", "シルエットを比べられない", f"{mine.name} か {reference.name} が無い")
        return
    a, wa, ha = silhouette(mine)
    b, wb, hb = silhouette(reference)
    if (wa, ha) != (wb, hb):
        note("注意", "シルエットの大きさが違う", f"{wa}x{ha} と {wb}x{hb}")
        return
    only_ref = sum(1 for i in range(len(a)) if b[i] and not a[i])
    only_mine = sum(1 for i in range(len(a)) if a[i] and not b[i])
    area_ref = max(sum(b), 1)
    lack = only_ref / area_ref * 100
    over = only_mine / area_ref * 100
    level = "注意" if (lack > 25 or over > 60) else "情報"
    note(level, f"下絵との差（{mine.stem.replace('view_', '')}）",
         f"足りない {lack:.1f}% ／ はみ出し {over:.1f}%（下絵の面積に対する割合）")


# ---------------------------------------------------------------- 画像をまとめる
def make_sheet(folder, out_path):
    names = ["view_front.png", "view_quarter.png", "view_side.png", "view_rear_quarter.png",
             "view_rear.png", "view_high.png", "view_top.png", "view_bottom.png"]
    shots = [(n, folder / n) for n in names if (folder / n).exists()]
    if not shots:
        return
    images = [Image.open(p).convert("RGB") for _, p in shots]
    w, h = images[0].size
    cols = 4
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGB", (w * cols, h * rows), (26, 31, 37))
    for i, im in enumerate(images):
        sheet.paste(im, ((i % cols) * w, (i // cols) * h))
    sheet.save(out_path, quality=90)


def run_blender(glb, out_dir, render, normalize=False):
    out_dir.mkdir(parents=True, exist_ok=True)
    cmd = [str(BLENDER), "--background", "--python",
           str(ROOT / "tools/blender/inspect_glb.py"), "--",
           "--glb", str(glb), "--out", str(out_dir), "--shots", "1" if render else "0",
           "--normalize", "1" if normalize else "0"]
    subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    path = out_dir / "inspect.json"
    if not path.exists():
        note("NG", f"{glb.name} を検査できなかった", "Blender の実行に失敗した")
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-render", action="store_true")
    args = parser.parse_args()
    render = not args.no_render
    OUT.mkdir(parents=True, exist_ok=True)

    check_numbers()

    targets = [("主役機", ROOT / "assets/models/mech_hero.glb", REQUIRED_HERO, OUT / "hero"),
               ("量産機", ROOT / "assets/models/mech_b.glb", REQUIRED_MASS, OUT / "mass")]
    for tag, glb, required, folder in targets:
        if not glb.exists():
            note("NG", f"{tag}：モデルが無い", str(glb))
            continue
        data = run_blender(glb, folder, render)
        if data:
            check_structure(tag, glb, required, data)
        if render:
            make_sheet(folder, OUT / f"sheet_{folder.name}.jpg")

    if render and REFERENCE_GLB.exists():
        ref_dir = OUT / "reference"
        run_blender(REFERENCE_GLB, ref_dir, True, normalize=True)
        check_silhouette(OUT / "hero/view_front.png", ref_dir / "view_front.png")
        check_silhouette(OUT / "hero/view_side.png", ref_dir / "view_side.png")

    order = {"NG": 0, "注意": 1, "情報": 2}
    findings.sort(key=lambda f: order.get(f[0], 3))
    lines = ["# 機体モデルの検査結果", "",
             "`python tools/inspect_mech.py` が自動で出す。項目は NG → 注意 → 情報 の順。", ""]
    ng = sum(1 for f in findings if f[0] == "NG")
    warn = sum(1 for f in findings if f[0] == "注意")
    lines.append(f"**NG {ng} 件 ／ 注意 {warn} 件**")
    lines.append("")
    if not findings:
        lines.append("指摘なし。")
    for level, title, detail in findings:
        lines.append(f"- **[{level}] {title}** — {detail}")
    lines += ["", "## 画像", "",
              "- `sheet_hero.jpg` / `sheet_mass.jpg`：正面・斜め・真横・斜め後ろ・背面・見下ろし・真上・真下",
              "- **はみ出しだけを見ないこと。背面・真上・真下に穴や貫通が無いかを必ず見る**"]
    (OUT / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    for level, title, detail in findings:
        print(f"[{level}] {title}: {detail}".encode("utf-8", "replace").decode("utf-8"))
    print(f"\nNG {ng} / 注意 {warn}  → {OUT / 'report.md'}")
    return 1 if ng else 0


if __name__ == "__main__":
    sys.exit(main())
