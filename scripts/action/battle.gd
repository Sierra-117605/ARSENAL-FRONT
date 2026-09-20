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
## 部位を壊してから倒すと手に入る希少素材（本命の入手方法）
@export var rare_per_captured_part: int = 2
## 勝利で手に入る希少素材（部位を壊せなかった時の保険）
@export var rare_for_win: int = 1

## この戦闘で手に入れた希少素材
var earned_rare: int = 0
## 壊した部位（鹵獲の対象。敵ごとに覚えておく）
var _broken_parts_by_enemy: Dictionary = {}

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
	GameLog.write("開始", "戦闘開始（敵 %d 体）" % _enemies().size())
	if player_occupant != null:
		_watch_player_machines()
	if player != null and player_occupant == null:
		# 乗員が指定されていない時だけ、開始時の機体で判定する
		player.destroyed.connect(_on_player_destroyed)
	for enemy in _enemies():
		enemy.destroyed.connect(_on_enemy_destroyed.bind(enemy))
		enemy.part_broken.connect(_on_enemy_part_broken.bind(enemy))


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


## 自軍機の被弾・部位破壊を記録する
func _watch_player_machines() -> void:
	for node in get_tree().get_nodes_in_group("team_player"):
		var machine := node as Pilotable
		if machine == null:
			continue
		machine.damaged.connect(_on_player_damaged.bind(machine))
		machine.part_broken.connect(_on_player_part_broken.bind(machine))
		machine.destroyed.connect(func(): GameLog.write("被害", "%s が撃破された" % machine.name))


func _on_player_damaged(hp: int, max_hp: int, machine: Pilotable) -> void:
	# 25% ごとの節目だけ記録する（毎回書くと多すぎるため）
	var ratio := float(hp) / float(maxi(max_hp, 1))
	var step := int(ratio * 4.0)
	if step != int(machine.get_meta("logged_step", 4)):
		machine.set_meta("logged_step", step)
		GameLog.write("被害", "%s の耐久 %d / %d" % [machine.name, hp, max_hp])


func _on_player_part_broken(part: String, machine: Pilotable) -> void:
	GameLog.write("被害", "%s の %s が破壊された" % [machine.name, part])


## ガレージ画面へ戻る
func to_garage() -> void:
	GameLog.write("移動", "ガレージへ戻る")
	garage_requested.emit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if get_tree() != null and get_tree().current_scene != null:
		get_tree().change_scene_to_file("res://scenes/garage.tscn")


## 最初からやり直す
func restart() -> void:
	GameLog.write("移動", "やり直し")
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


## 敵の部位が壊れた：鹵獲の候補として覚えておく
func _on_enemy_part_broken(part: String, enemy: Pilotable) -> void:
	GameLog.write("戦闘", "%s の %s を破壊" % [enemy.name, part])
	var list: Array = _broken_parts_by_enemy.get(enemy.get_instance_id(), [])
	list.append(part)
	_broken_parts_by_enemy[enemy.get_instance_id()] = list


## 壊した部位に対応するパーツの設計図を鹵獲する
func _capture_from(enemy: Pilotable) -> void:
	var parts: Array = _broken_parts_by_enemy.get(enemy.get_instance_id(), [])
	if parts.is_empty():
		return
	var progress := ProgressStore.load_progress()
	for part in parts:
		var slot := _slot_for_part(str(part))
		if slot == "":
			continue
		# その部位に対応する未入手のパーツを 1 つ鹵獲する
		for candidate in RobotParts.parts_for(slot):
			var part_id := str(candidate.get("id", ""))
			if bool(candidate.get("locked", false)) 					and not ProgressStore.is_unlocked(progress, part_id) 					and not (progress.get("blueprints", []) as Array).has(part_id) 					and not earned_blueprints.has(part_id):
				earned_blueprints.append(part_id)
				earned_rare += rare_per_captured_part
				break


## 壊した部位の名前から、対応するパーツの部位（スロット）を返す
func _slot_for_part(part: String) -> String:
	match part:
		"head": return "head"
		"arm_left", "arm_right": return "arms"
		"legs": return "legs"
	return ""


## 戦果（資材・希少素材・設計図）を進行状況に足して保存する
func _grant_rewards() -> void:
	var progress := ProgressStore.load_progress()
	progress["materials"] = int(progress.get("materials", 0)) + earned_materials
	progress["rare"] = int(progress.get("rare", 0)) + earned_rare
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
	# 撃破で資材が手に入る。部位を壊していれば、その部品を鹵獲できる
	earned_materials += materials_per_kill
	_capture_from(enemy)
	GameLog.write("戦闘", "%s を撃破（残り %d 体）" % [enemy.name, alive_enemy_count()])
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
		earned_rare += rare_for_win
		var blueprint := _pick_blueprint()
		if blueprint != "":
			earned_blueprints.append(blueprint)
	GameLog.write("結果", "%s ／ 資材 +%d ／ 希少素材 +%d ／ 設計図 %s" % [
		"勝利" if result == "win" else "撃破された",
		earned_materials, earned_rare,
		earned_blueprints if not earned_blueprints.is_empty() else "なし"])
	_grant_rewards()
	Sounds.play_ui(self, Sounds.VICTORY if result == "win" else Sounds.DEFEAT)
	finished.emit(result)
