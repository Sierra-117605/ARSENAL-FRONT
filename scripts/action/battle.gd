class_name Battle
extends Node3D
## 戦闘の進行役。自機が壊れたら「撃破」、敵を全部壊したら「勝利」を表示し、R キーでやり直す。

## プレイヤーの機体（開始時。乗り換えると自動で切り替わる）
@export var player: Pilotable
## プレイヤーの乗員。これが乗っている機体が壊れたら負け
@export var player_occupant: Occupant
## 敵をまとめている入れ物
@export var enemies_root: Node3D

## 敵 1 体を倒すごとに手に入る資材
@export var materials_per_kill: int = 60
## 勝った時に追加で手に入る資材
@export var materials_for_win: int = 120

## 戦闘の結果（"" = まだ決着していない / "win" / "lose"）
var outcome: String = ""
## この戦闘で手に入れた資材
var earned_materials: int = 0
## この戦闘で手に入れた設計図
var earned_blueprints: Array[String] = []

## 決着した時に知らせる（"win" か "lose"）
signal finished(result: String)
## やり直しが指示された時に知らせる
signal restart_requested
## ガレージへ戻ると指示された時に知らせる
signal garage_requested


func _ready() -> void:
	InputActions.ensure_registered()
	if player != null and player_occupant == null:
		# 乗員が指定されていない時だけ、開始時の機体で判定する
		player.destroyed.connect(_on_player_destroyed)
	for enemy in _enemies():
		enemy.destroyed.connect(_on_enemy_destroyed.bind(enemy))


func _physics_process(_delta: float) -> void:
	# 乗り換えに対応するため、今乗っている機体が壊れたかを毎回見る
	if outcome != "" or player_occupant == null:
		return
	var current := player_occupant.get_vehicle()
	if current != null and not current.is_alive():
		_finish("lose")


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


## 戦果（資材と設計図）を進行状況に足して保存する
func _grant_rewards() -> void:
	var progress := ProgressStore.load_progress()
	progress["materials"] = int(progress.get("materials", 0)) + earned_materials
	for part_id in earned_blueprints:
		ProgressStore.add_blueprint(progress, part_id)
	ProgressStore.save_progress(progress)


## まだ持っていない設計図を 1 つ選ぶ（無ければ空文字）
func _pick_blueprint() -> String:
	var progress := ProgressStore.load_progress()
	var candidates: Array[String] = []
	for part in RobotParts.data().get("parts", []):
		var part_id := str(part.get("id", ""))
		if bool(part.get("locked", false)) and not ProgressStore.is_unlocked(progress, part_id) 				and not (progress.get("blueprints", []) as Array).has(part_id) 				and not earned_blueprints.has(part_id):
			candidates.append(part_id)
	if candidates.is_empty():
		return ""
	return candidates[randi() % candidates.size()]


func _on_enemy_destroyed(enemy: Pilotable) -> void:
	# 撃破で資材が手に入る
	earned_materials += materials_per_kill
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
	if result == "win":
		earned_materials += materials_for_win
		var blueprint := _pick_blueprint()
		if blueprint != "":
			earned_blueprints.append(blueprint)
	_grant_rewards()
	Sounds.play_ui(self, Sounds.VICTORY if result == "win" else Sounds.DEFEAT)
	finished.emit(result)
