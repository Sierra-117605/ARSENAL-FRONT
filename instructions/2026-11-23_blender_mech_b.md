# 指示書：Blender で自機の機体モデルを作る（案 B）

対象：Codex CLI（実装担当）／作成：Claude Code 2026-11-23
この指示書は会話の文脈なしで読めるように書いてある。迷ったら自己判断せず `HANDOFF.md` に書いて止まること。

## 1. 目的
自機のロボットの見た目を、市販のメカアクションと並べても見劣りしない水準に近づける。
形は計算（箱の組み合わせ）で作ってきたが、角が立ちすぎて「箱の寄せ集め」に見えるところで頭打ちになった。
**Blender で面取り（ベベル）の入った本番用モデルを作り、Godot に差し替える。**

## 2. 先に読むもの
- `SPEC.md` §0.18（機体デザインの方向性）／§0.15（配布・見た目の進め方）
- `TODO.md` の「現在地」と N8
- `KNOWLEDGE.md` の 2026-11-23 の項（効いた変更・効かなかった変更、計測の注意）
- `docs/visual_log/06_style_b/README.md`（案 A/B/C の比較と、開発者が案 B を選んだ経緯）

## 3. 今の状態
- 機体の形は `scripts/action/mech_detail.gd` の `STYLES` に数値で入っている。既定は案 B（軽量高機動）
  - 形を作る土台は `scripts/action/mesh_shapes.gd`（角を落とした八角柱・くさび形）
  - 既存のノード（`Torso` `Hip` `Head` `ShoulderL/R` `ArmL` `ArmPivotR/ArmR` `ArmPivotR/Barrel`
    `LegPivotL/LegL` `LegPivotR/LegR` `LegPivotL/FootL` `LegPivotR/FootR` `BackPack` `Visor`）の
    **mesh だけ**を差し替え、名前・位置・当たり判定には触れていない
- Blender 5.1 は導入済み：`C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`
  - `blender.exe --background --python-expr "..."` で Python が動くことを確認済み
- 自動テスト 31 本すべて成功。フレームレート 平均 114／最低 145（1920×1080）

## 4. やること（順番に）

### 4-1. 生成スクリプトを作る
`tools/blender/mech_b.py` を新規作成する。要件：
- Blender の Python（bpy）で、**部位ごとに 1 つのオブジェクト**を作る。
  オブジェクト名は Godot のノード名と**完全に一致**させること：
  `Torso` `Hip` `Head` `ShoulderL` `ShoulderR` `ArmL` `ArmR` `Barrel` `LegL` `LegR`
  `FootL` `FootR` `BackPack` `Visor`
- 各部位は、箱やくさびを複数組んでから結合し、**ベベル（面取り）**と
  **ウェイテッドノーマル**をかける。面取り幅は 0.02〜0.05 くらいから調整する
  （エッジに光の線が出ることが今回の狙い。これが無いと今までと変わらない）
- 寸法は `scripts/action/mech_detail.gd` の `STYLES["b"]` の数値を出発点にする
  （単位は Godot 側の「基準寸法」と同じ。全高 4 の機体として作る。Godot 側で 3 倍に拡大される）
- 各部位の原点は、**今の Godot ノードの原点と同じ位置**にすること
  （例：`Torso` は胴体の中心が原点。`LegL` は脚の中心が原点で、上下 0.9 ずつ）
- 形の方針は `SPEC.md` §0.18：角張った多層の装甲／細い腰と長い脚／大きな背面推進ユニット／
  関節と駆動部が外から見える／肩が大きく張り出す／つや消しの軍用色
- 既存作品のデザイン・名前・ロゴは使わない（完全オリジナル）

### 4-2. 書き出し
- 同じスクリプトの最後で `assets/models/mech_b.glb` に glTF で書き出す
- 実行コマンド（記録に残すこと）：
  `"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python tools/blender/mech_b.py`

### 4-3. Godot 側で差し替える
- `scripts/action/mech_detail.gd` に読み込み処理を足す：
  `assets/models/mech_b.glb` があれば、その中の同名メッシュを既存ノードの `mesh` に入れる。
  無ければ今までどおり計算で作った形を使う（**glb が無くても動くこと**）
- 差し替えた部位については、計算で足していた装甲板の重複を外す（二重に生えないようにする）
- **触ってはいけないもの**：ノード名、当たり判定（`Collision` `HitHead` `HitArmL` `HitArmR` `HitLegs`）、
  `MuzzlePoint` の位置、`BROKEN_VISUAL` / `VISUAL_PARTS` の対応表、操作・性能の数値

### 4-4. 確認
1. 自動テスト 31 本を全部流して**全部成功**すること
   `<Godot> --headless --path . --script res://tests/test_xxx.gd`（Godot は `CLAUDE.md` §4 のパス）
2. スクショを撮る：`<Godot> --path . --script res://tools/shot_set.gd -- --tag=mech_front --out=docs/visual_log/tmp`
   （`--headless` は付けない。tag は `mech` `mech_front` `battle` `boss`）
3. フレームレート：`<Godot> --path . --script res://tools/fps_check.gd -- --frames=400`
   **1 回目の値だけ**を使う（2 回目以降は当てにならない。KNOWLEDGE 2026-11-23）。60 を下回らないこと
4. 変更前（`docs/visual_log/06_style_b/mech_front_b.png`）と並べて、別セッションの Codex に
   10 点満点で採点させる。採点の指示文は `docs/visual_log/` の運用に従い、先入観を与えない

## 5. 完了条件
- 開発者が画面を見て「良い」と言う（最終判断は開発者）
- かつ、批評役の採点が **6 点以上**
- かつ、自動テスト 31 本成功・フレームレート 60 以上
- 上 3 つが揃うまでは「完成」と書かない

## 6. 止まって相談すること（自己判断しない）
- 当たり判定・部位ダメージの対応表を変えないと形が成立しない場合
- `.glb` が大きくなりすぎる場合（目安：1 機で 10MB を超えるなら相談）
- 面取りを入れてもフレームレートが 60 を下回る場合
- 既存作品のデザインに寄せる必要があると感じた場合（禁止事項なので必ず止まる）

## 7. 記録
- commit メッセージにこの指示書名を含める
  例：`[Codex] 機体モデルを Blender で作成 (ref: instructions/2026-11-23_blender_mech_b.md)`
- 進み具合は `TODO.md` の N8、学びは `KNOWLEDGE.md`、止まったことは `HANDOFF.md`
- 終わったらこの指示書を `instructions/done/` に移動する
- push は開発者の承認を得てから
