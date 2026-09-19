# ARSENAL FRONT

> **【2026-09-20 大方針変更】** 3D のメカ操縦アクションに方針転換（SPEC.md §0）。
> 新 Phase 1 は「ロボット 1 機を 3D 空間で操縦できる」。下記の 2D 運営シムの説明は旧方針（保留）の内容。

多兵科ミリタリー運営シム × アセンブル系メカアクション。
歩兵・装甲戦闘車両・ロボット・航空機・艦船の5兵科を運営する司令官になり、
HoI4 のタンクデザイナー風にユニットをアセンブルして出撃させる、PvE 専用のハイブリッドゲーム。

世界観は **現代軍事 + SF メカ混在**（MGS / エースコンバット・ストレンジリアル系）。

## ドキュメント

| ファイル | 役割 |
|---|---|
| [PLAN.md](PLAN.md) | やりたいことの全体像 |
| [SPEC.md](SPEC.md) | 仕様の確定事項と [TBD] |
| [TODO.md](TODO.md) | タスク管理（リセットしても再開可能） |
| [KNOWLEDGE.md](KNOWLEDGE.md) | 学び・ハマりどころ |
| [docs/DATA_STRUCTURE.md](docs/DATA_STRUCTURE.md) | データ構造の大原則（シリアライズ可能・イベント駆動） |
| [docs/REVIEW_FLOW.md](docs/REVIEW_FLOW.md) | Claude Code ⇄ Codex 相互レビュー運用 |

## 技術スタック

- **エンジン**: Godot 4.6.3 stable（2026-09-20〜 3D。変更前は 2D モード）
- **言語**: GDScript
- **対象プラットフォーム**: PC（Windows 優先）
- **マルチプレイ**: PvE × P2P（将来実装。設計初期から考慮）

## フォルダ構成

```
ARSENAL-FRONT/
├─ project.godot           Godot のプロジェクト設定
├─ icon.svg                プロジェクトアイコン（仮）
├─ scenes/                 .tscn シーンファイル
├─ scripts/                .gd スクリプト
├─ data/                   静的データ（JSON）
│  └─ parts/               パーツカタログ
├─ saves/                  プレイヤーのセーブデータ（gitignore）
├─ assets/                 画像・音などのアセット
└─ docs/                   設計ドキュメント
```

## 現在のフェーズ

**新 Phase 1（ロボット 1 機の 3D 操縦）準備中**。以下は旧方針の記録。

**旧 Phase 1 形式上クリア**：装甲戦闘車両のみ・司令官モード + 自動戦闘 + 任務。

実装されているもの:
- 6 固定スロットでの戦車アセンブル UI (リアルタイムステータス更新)
- 5 項目ステータス計算 + 31 パーツの JSON カタログ
- 設計の保存・複製・削除・一覧管理 (`user://designs.json`)
- 司令官モード: 日進行 / 資金・素材 / 製造 / 任務派遣
- 任務システム: 殲滅 × 3 難易度 / 自動戦闘解決 / 報酬
- 戦闘デモ: 保存設計の総当たり 1v1 ログ
- ゲーム状態の永続化 (`user://gamestate.json`)

残課題: 数値バランス調整、出撃モード (手動操作・Phase 2)、他兵科 (Phase 3+)。
詳細は [TODO.md](TODO.md) と [KNOWLEDGE.md](KNOWLEDGE.md)。

## 開発体制

- **仕様策定**: claude.ai（ブラウザのチャット）
- **実装**: Claude Code + Codex（相互レビュー運用。詳細は [docs/REVIEW_FLOW.md](docs/REVIEW_FLOW.md)）
- **動作検証**: 開発者本人（コードは書かない／読まない）

## ローカル起動

Godot エディタでこのフォルダを開き、F5 キーを押すと `scenes/main.tscn` が起動する。
ヘッドレスでの起動確認（環境チェック）:

```
godot --headless --path . --quit-after 60
```

期待する出力: `[ARSENAL FRONT] boot ok`
