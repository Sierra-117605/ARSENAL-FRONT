# データ構造の方針（Phase 1〜将来のマルチプレイ対応）

> このドキュメントは TODO T1-4 の成果物です。
> 根拠：SPEC §2.14（マルチプレイ仕様）、KNOWLEDGE §2-1（後付け対策）、SPEC §3（Phase 1 共通基盤）。

## 1. 大原則

ユニット・戦闘状態・任務進行・セーブデータなど、ゲームのあらゆる「状態」は次の2つを満たす形で持つ：

1. **シリアライズ可能**：`JSON.stringify` で文字列化できる形だけを使う
2. **イベント駆動で更新する**：状態を直接書き換えず、「何が起きたか」を表すイベント（Dictionary）を発行して、そのイベントに反応して状態を更新する

この方針は **Phase 1 の段階から守る**。後から P2P 同期を足すのは事実上の作り直しになるため。

## 2. 使ってよい型 / 使ってはいけない型

### 使ってよい（JSON 互換）
- `int`, `float`, `bool`, `String`
- `Array`（中身は使ってよい型のみ）
- `Dictionary`（キーは `String`、値は使ってよい型のみ）
- `null`

### 状態として使ってはいけない（JSON 化できないもの）
- `Node` への参照（`Node`, `Node2D`, `Control` 等のシーンノード）
- `Resource` への参照
- `Vector2`, `Color`, `Callable`, `Signal`
  - ※ 描画や入力では使ってよいが、**保存対象の状態には使わない**
  - 必要なら `{ "x": 100.0, "y": 50.0 }` のように分解して持つ

### 例：戦車の設計データ（ユニット定義）
```gdscript
# ✓ 良い例：そのまま JSON に書ける
var tank_design = {
    "id": "design_001",
    "name": "Type-1 MBT",
    "category": "mbt",                       # 区分（mbt / scout / atgm）
    "slots": {
        "hull": "hull_medium",
        "main_armament": "gun_120mm_smooth",
        "turret": "turret_rotary",
        "engine": "engine_standard",
        "armor": "armor_heavy",
        "suspension": "suspension_standard"
    },
    "modules": ["mod_radio", "mod_smoke_launcher"]
}

# ✗ 悪い例：Node 参照や Vector2 を直接持つ
var bad_tank = {
    "hull_node": $HullSprite,                # NG: Node 参照
    "position": Vector2(100, 50)             # NG: そのままでは JSON 化できない
}
```

## 3. イベント駆動の書き方

状態を直接書き換えない。「何が起きたか」を表すイベント（Dictionary）を作って、それを処理関数に渡す。

```gdscript
# ✓ 良い例：イベントを作って apply に渡す
var event = {
    "type": "tank_destroyed",
    "tank_id": "unit_007",
    "at_turn": 12
}
GameState.apply(event)
# → apply の中で state["units"][unit_007]["hp"] = 0 などを行う

# ✗ 悪い例：状態を直接いじる
GameState.units[7].hp = 0
```

なぜこうするか：
- イベントを **記録すれば「途中再生」「巻き戻し」「他PCへ送る」がほぼ自動でできる**
- マルチプレイは「同じイベント列を全員に流す → 全員で同じ状態にする」が基本
- セーブ／ロードも、状態のスナップショット ＋ それ以降のイベント列、で表現できる

## 4. ファイル配置との対応

| 種類 | 置き場所 | 形式 |
|---|---|---|
| パーツカタログ（マスターデータ） | `data/parts/*.json` | 静的 JSON |
| ユニット設計（プレイヤーが組んだ車両） | セーブデータ内 | Dictionary（JSON 化対象） |
| 戦闘ログ | 一時メモリ → 任意でセーブ | Array<Dictionary> |
| セーブデータ | `saves/slot_*.json` | JSON ファイル |

## 5. Phase 1 で守るべき具体ルール

1. **保存対象の状態は GDScript の `Dictionary` か `Array` だけで構成する**
2. **Node や Vector2 を直接保存しない**（必要なら分解して持つ）
3. **状態更新は必ず `apply(event)` のような関数を1個用意してそこで行う**
4. パーツの数値は **コード内にハードコードせず、`data/parts/*.json` から読む**

## 6. マルチプレイ実装時にやること（参考・将来）

Phase 1〜4 ではここまで踏み込まない。設計時に「やれるようにしておく」だけ。

- イベントに `turn` `sender_id` を付けて、ホストが整列・配信
- 状態スナップショットを定期的に送り、差分はイベント列で同期
- ランダム性は「シード固定 ＋ イベントに乱数結果を含める」で再現性を確保

---

**改訂履歴**
- 初版（T1-4 完了時）: 大原則・型のルール・イベント駆動方針を確定
