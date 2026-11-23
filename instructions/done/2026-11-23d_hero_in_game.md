# 指示書：主役機をゲーム画面に出す

対象：Codex CLI（実装担当）／作成：Claude Code 2026-11-23
会話の文脈なしで着手できるように書いてある。迷ったら自己判断せず `HANDOFF.md` に書いて止まること。

## 0. いまの状態（ここが問題）

主役機のモデル `assets/models/mech_hero.glb` は**できているのに、ゲームから読まれていない**。
`scripts/action/mech_detail.gd` は量産機の `mech_b.glb` の 14 部位しか読まないため、
ゲームを起動すると主役機も量産機の形で出る。

**この指示書のゴールは「起動すると、プレイヤーの機体だけ主役機の形で立っている」状態にすること。**

## 1. 先に読むもの
- `AGENTS.md` §6（分担。利用量は Claude と Codex で 50:50）
- `SPEC.md` §0.18 のうち次の 3 つ
  - 「主役機と量産機を作り分ける」
  - 「**全機体のプロポーション**（第 46 版）」… 部位の位置と当たり判定の数値表。**この値が正**
  - 「**幅は三面図から実測する**（第 47 版）」… 形を変えるときの測り方
- `HANDOFF.md` の上から 2 件
- `scripts/action/mech_detail.gd` の `MODEL_B` / `MODEL_PARTS` / `_apply_model_b`

## 2. やること

### 2-1. 「この機体は主役機か」の印を足す
- `scripts/action/robot.gd` に `@export var hero: bool = false` を足す
- `scenes/field_3d.tscn` の **`Robot` ノードだけ `hero = true`**。
  `SpareRobot` と `Enemies/*` は false のまま（＝量産機）
- プレイヤーが乗り換えても主役機はこの 1 機で固定（見た目が入れ替わらないようにするため）

### 2-2. 主役機のモデルを読む
`scripts/action/mech_detail.gd` に次を足す。
- `const MODEL_HERO := "res://assets/models/mech_hero.glb"`
- `hero` が true なら `mech_hero.glb`、false なら `mech_b.glb` を読む
- **頭だけ名前が違う**：主役機のモデルでは頭の名前が `Head_hero`。
  これを Godot 側のノード `Head` の mesh に入れる（他の 13 部位は同じ名前）
- 主役機のモデルに `Visor` は無い。**`Visor` ノードは非表示にする**
  （主役機は目が頭部モデルに作り込まれているため。量産機は今までどおり `Visor` を使う）
- **どちらのファイルも無ければ**、今までどおり計算で作った形にする（ファイルが無くても動くこと）

### 2-3. 色
主役機のモデルには明るい灰青の装甲・濃い青灰の内部・オレンジの整備表示・水色の発光が
材質として入っている。**量産機のような再塗装（灰緑）をかけないこと**。
`tint_part` が主役機にも効いてしまう場合は、主役機のときは塗り替えをやめる。

## 3. 触ってはいけないもの
- **当たり判定の数値**（`robot.gd` の `BASE_PART_POS`、`robot.tscn` の shape）。
  2026-11-23 に見た目と合わせて直したばかり。SPEC §0.18 第 46 版の表が正。**勝手に動かさない**
- ノード名、`MuzzlePoint` の位置、`BROKEN_VISUAL` と `VISUAL_PARTS` の対応表、操作方法、性能の数値

## 4. 確認
1. **自動テスト 33 本**を全部流す。
   `<Godot> --headless --path . --script res://tests/test_xxx.gd`（Godot のパスは `AGENTS.md` §4）
   - **重要**：2026-11-23 に全機体のプロポーションを変えたあと、テストをまだ一度も通し切れていない。
     落ちたテストがあれば、**当たり判定を元に戻すのではなく**、何が起きているかを調べて報告する
     （テスト側が旧寸法を前提にしている可能性がある）
2. スクショ：`<Godot> --path . --script res://tools/shot_set.gd -- --tag=mech_front --out=docs/visual_log/tmp`
   （`--headless` は付けない。tag は `mech` `mech_front` `battle` `boss`）
   → **主役機の形で写っていること**を目で確かめる
3. fps は参考値。数値を理由に止まらない

## 5. 止まって相談すること（自己判断しない）
- テストが落ち、直すには当たり判定か仕様を変える必要がある場合
- `Head_hero` を `Head` に入れると位置がずれる場合（頭の原点は Blender 側で合わせてある）

## 6. 完了条件
1. ゲームを起動すると、プレイヤーの機体だけ主役機の形で立っている
2. 味方の量産機・敵機は今までどおりの形
3. 自動テスト 33 本すべて成功
4. 開発者が画面を見て確認する（最終判断は開発者。あなたが「完成」と書かない）

## 7. 記録と引き継ぎ
- commit メッセージに `(ref: instructions/2026-11-23d_hero_in_game.md)` を含める
- 終わったら `HANDOFF.md` に書いて Claude Code へ渡す
- **push はしない**（開発者の承認後）
- 終わったらこの指示書を `instructions/done/` へ移す
