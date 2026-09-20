extends SceneTree
## AI の賢さの確認。
##
## 確かめること：
##  1. 物陰にさえぎられている間は撃たない（壁越しに撃ち抜かない）
##  2. さえぎられている間は横に回り込もうとする
##  3. 射線が通れば撃つ
##  4. 動いている相手には「先」を狙う（見越し射撃）
##  5. まっすぐ近づくだけでなく、横にも動く
##  6. 耐久が減ると、いつもより離れて戦う
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n4_4_ai_smart.gd

var field: Node
var robot: Robot
var enemy: Robot
var enemy_ai: AIPilot
var wall: StaticBody3D
var frame := 0
var failed := false
var strafe_values: Array[float] = []
var mission_before := ""


func _initialize() -> void:
	# 任務の設定に左右されないよう、基本の任務（殲滅・中）に固定する
	if FileAccess.file_exists(MissionData.CHOICE_PATH):
		mission_before = FileAccess.get_file_as_string(MissionData.CHOICE_PATH)
	MissionData.save_choice("sweep_plain", "normal")
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	robot = field.get_node("Robot")
	robot.use_saved_loadout = false
	enemy = field.get_node("Enemies/Enemy1")
	enemy_ai = field.get_node("Enemies/Enemy1/AIPilot")
	# 味方 AI 機は今回の確認に関係ないので遠ざける
	field.get_node("SpareRobot").position = Vector3(600, 0, 600)
	# 味方の戦車も確認に関係ないので遠ざける
	var tank := field.get_node_or_null("Tank")
	if tank != null:
		tank.position = Vector3(900, 0, 900)


## 敵とプレイヤーの間に厚い壁を置く
func _add_wall() -> void:
	wall = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 40, 6)
	shape.shape = box
	wall.add_child(shape)
	field.add_child(wall)
	var middle: Vector3 = (robot.global_position + enemy.global_position) * 0.5
	wall.global_position = Vector3(middle.x, 20, middle.z)


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame > 20 and frame < 200:
		strafe_values.append(float(enemy.control["move_x"]))
	match frame:
		5:
			# 敵をプレイヤーのすぐ近く（射程内）に置く
			enemy.global_position = robot.global_position + Vector3(0, 0, -60)
		20:
			_report(bool(enemy.control["fire"]), "射線が通っていれば撃つ")
			_add_wall()
		30:
			_report(not bool(enemy.control["fire"]), "物陰にさえぎられている間は撃たない")
			_report(absf(float(enemy.control["move_x"])) > 0.9, "さえぎられている間は横に回り込む (%.1f)" % enemy.control["move_x"])
			wall.queue_free()
		40:
			_report(bool(enemy.control["fire"]), "さえぎりが無くなればまた撃つ")
			# 4：プレイヤーを横向きに動かして、見越し射撃を確かめる
			robot.velocity = Vector3(30, 0, 0)
		45:
			var aim := Pilotable.aim_point(enemy.control)
			var offset := aim.x - robot.global_position.x
			_report(offset > 1.0, "動いている相手の進む先を狙う (%.1fm 先)" % offset)
			robot.velocity = Vector3.ZERO
		200:
			var has_plus := strafe_values.any(func(v): return v > 0.3)
			var has_minus := strafe_values.any(func(v): return v < -0.3)
			_report(has_plus and has_minus, "左右どちらにも横移動する（棒立ちで近づかない）")
			# 6：耐久を減らして、離れて戦うか見る
			# 戦闘中に受けた傷の影響を除くため、いったん耐久を満タンに戻して比べる
			enemy.hp = enemy.max_hp
			var before_keep := _current_keep()
			enemy.hp = int(enemy.max_hp * 0.2)
			_report(_current_keep() > before_keep,
				"耐久が減ると距離を取る (%.0fm → %.0fm)" % [before_keep, _current_keep()])
			_restore_mission()
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


## 任務の設定を元に戻す
func _restore_mission() -> void:
	if mission_before != "":
		var f := FileAccess.open(MissionData.CHOICE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(mission_before)
	elif FileAccess.file_exists(MissionData.CHOICE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MissionData.CHOICE_PATH))


## 今その AI が保とうとしている距離
func _current_keep() -> float:
	var keep := enemy_ai.preferred_distance
	if float(enemy.hp) / float(maxi(enemy.max_hp, 1)) < enemy_ai.retreat_hp_ratio:
		keep += enemy_ai.retreat_distance
	return keep


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
