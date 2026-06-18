extends Node2D

# Phase 1 の起点シーン。
# まずは「Godot が起動して画面に文字が出る」ことだけを確認する最小サンプル。
# 後で T2 系のデータ構造実装に合わせて、ここから司令官モードのシーンへ遷移する。

func _ready() -> void:
	print("[ARSENAL FRONT] boot ok")
