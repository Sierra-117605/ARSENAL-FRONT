class_name Battle
extends Node3D
## 戦闘の進行役。自機が壊れたら「撃破」、敵を全部壊したら「勝利」を表示し、R キーでやり直す。

## プレイヤーの機体
@export var player: Pilotable
## 敵をまとめている入れ物
@export var enemies_root: Node3D

## 戦闘の結果（"" = まだ決着していない / "win" / "lose"）
var outcome: String = ""

## 決着した時に知らせる（"win" か "lose"）
signal finished(result: String)
## やり直しが指示された時に知らせる
signal restart_requested
## ガレージへ戻ると指示された時に知らせる
signal garage_requested


func _ready() -> void:
	InputActions.ensure_registered()
	if player != null:
		player.destroyed.connect(_on_player_destroyed)
	for enemy in _enemies():
		enemy.destroyed.connect(_on_enemy_destroyed.bind(enemy))


func _unhandled_input(event: InputEvent) -> void:
	# R キーでやり直し（決着後のみ）、G キーでガレージへ戻る（いつでも）
	if not (event is InputEventKey and event.pressed):
		return
	var key: int = (event as InputEventKey).physical_keycode
	if key == InputActions.KEYS[InputActions.GARAGE]:
		to_garage()
	elif key == InputActions.KEYS[InputActions.RESTART] and outcome != "":
		restart()


## ガレージ画面へ戻る
func to_garage() -> void:
	garage_requested.emit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if get_tree() != null and get_tree().current_scene != null:
		get_tree().change_scene_to_file("res://scenes/garage.tscn")


## 最初からやり直す
func restart() -> void:
	restart_requested.emit()
	if get_tree() != null and get_tree().current_scene != null:
		get_tree().reload_current_scene()


## 生きている敵の数
func alive_enemy_count() -> int:
	var count := 0
	for enemy in _enemies():
		if enemy.is_alive():
			count += 1
	return count


func _enemies() -> Array[Pilotable]:
	var list: Array[Pilotable] = []
	if enemies_root == null:
		return list
	for child in enemies_root.get_children():
		if child is Pilotable:
			list.append(child)
	return list


func _on_player_destroyed() -> void:
	_finish("lose")


func _on_enemy_destroyed(enemy: Pilotable) -> void:
	# 壊れた敵は少し置いてから消す
	enemy.set_physics_process(false)
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(enemy.queue_free)
	if alive_enemy_count() == 0:
		_finish("win")


func _finish(result: String) -> void:
	if outcome != "":
		return
	outcome = result
	finished.emit(result)
