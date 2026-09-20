extends SceneTree
## 任務中の不具合修正の確認（開発者の指摘から）。
##
## 確かめること：
##  1. 破壊任務では、目標施設が「敵陣営」として検索できる（AI が狙える状態）
##  2. 味方 AI が破壊目標を狙う
##  3. 味方の弾は味方（自軍機・守る拠点）を素通りして、ダメージを与えない
##  4. 敵の弾は守る拠点にダメージを与える
##  5. プレイヤーの弾は破壊目標にダメージを与える
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n5_2_friendly_fire.gd

var field: Node
var battle: Node
var frame := 0
var stage := 0
var failed := false
var mission_before := ""
var progress_before := ""


func _initialize() -> void:
	if FileAccess.file_exists(MissionData.CHOICE_PATH):
		mission_before = FileAccess.get_file_as_string(MissionData.CHOICE_PATH)
	if FileAccess.file_exists(ProgressStore.PATH):
		progress_before = FileAccess.get_file_as_string(ProgressStore.PATH)
	_start("strike_facility", "normal")


func _start(mission_id: String, difficulty: String) -> void:
	if field != null:
		field.queue_free()
	MissionData.save_choice(mission_id, difficulty)
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	battle = field
	(field.get_node("Robot") as Robot).use_saved_loadout = false
	frame = 0


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame > 600:
		_report(false, "段階 %d で進まなくなった（打ち切り）" % stage)
		_restore()
		print("RESULT: FAIL")
		return true
	match stage:
		0:  # 破壊任務：AI が目標を狙えるか
			if frame == 10:
				var objective: Pilotable = battle.objective
				_report(objective != null and objective.team == "enemy", "破壊目標は敵陣営になっている")
				_report(field.get_tree().get_nodes_in_group("team_enemy").has(objective),
					"敵陣営の一覧から目標を見つけられる（AI が狙える）")
				# 味方 AI を目標のそばに置いて、狙うか確かめる
				var ally: Robot = field.get_node("SpareRobot")
				ally.global_position = objective.global_position + Vector3(60, 0, 60)
				# 狙いの分散を切って「いちばん近い相手」を選ばせる
				(field.get_node("SpareRobot/AIPilot") as AIPilot).target_spread_count = 1
				# 敵は遠ざけて、目標だけが狙いの候補になるようにする
				for enemy in battle._enemies():
					(enemy as Node3D).global_position = Vector3(900, 0, 900)
			elif frame == 20:
				var ally_ai: AIPilot = field.get_node("SpareRobot/AIPilot")
				var target := ally_ai._current_target()
				_report(target == battle.objective,
					"味方 AI が破壊目標を狙う (%s)" % [target.name if target != null else "なし"])
				# 5：プレイヤーの弾は目標に当たる
				var objective: Pilotable = battle.objective
				var before := objective.hp
				var robot: Robot = field.get_node("Robot")
				var weapon: Weapon = robot.get_node("Weapon")
				robot.global_position = objective.global_position + Vector3(0, 0, 60)
				weapon.cooldown = 0.0
				weapon.try_fire(objective.global_position + Vector3(0, 9, 0), robot)
				set_meta("obj_before", before)
			elif frame == 40:
				var objective: Pilotable = battle.objective
				_report(objective.hp < int(get_meta("obj_before")),
					"プレイヤーの弾は破壊目標にダメージを与える (%d → %d)" % [get_meta("obj_before"), objective.hp])
				stage = 1
				_start("defend_depot", "normal")
		1:  # 防衛任務：味方の弾が拠点に当たらない／敵の弾は当たる
			if frame == 10:
				var objective: Pilotable = battle.objective
				_report(objective != null and objective.team == "player", "守る拠点は自軍陣営になっている")
				# 敵の攻撃が混ざらないよう、敵と飛行中の弾をすべて取り除く
				for enemy in battle._enemies():
					(enemy as Node).queue_free()
				for child in field.get_children():
					if child is Bullet:
						child.queue_free()
				var robot: Robot = field.get_node("Robot")
				robot.global_position = objective.global_position + Vector3(0, 0, 60)
				var weapon: Weapon = robot.get_node("Weapon")
				weapon.cooldown = 0.0
				weapon.try_fire(objective.global_position + Vector3(0, 9, 0), robot)
				set_meta("depot_before", objective.hp)
				set_meta("fired_frame", frame)
			elif frame == 40:
				var objective: Pilotable = battle.objective
				_report(objective.hp == int(get_meta("depot_before")),
					"味方（プレイヤー）の弾は拠点を素通りする (%d のまま)" % objective.hp)
				# 4：敵の弾は当たる（敵役として敵陣営の機体を 1 つ置く）
				var enemy: Node = load("res://scenes/robot.tscn").instantiate()
				field.add_child(enemy)
				var enemy_body := enemy as Pilotable
				enemy_body.team = "enemy"
				enemy_body.global_position = objective.global_position + Vector3(0, 0, 60)
				var enemy_weapon: Weapon = enemy.get_node("Weapon")
				enemy_weapon.cooldown = 0.0
				enemy_weapon.try_fire(objective.global_position + Vector3(0, 9, 0), enemy_body)
			elif frame == 70:
				var objective: Pilotable = battle.objective
				_report(objective.hp < int(get_meta("depot_before")),
					"敵の弾は拠点にダメージを与える (%d → %d)" % [get_meta("depot_before"), objective.hp])
				_restore()
				print("RESULT: ", "FAIL" if failed else "PASS")
				return true
	return false


func _restore() -> void:
	_write_or_delete(MissionData.CHOICE_PATH, mission_before)
	_write_or_delete(ProgressStore.PATH, progress_before)


func _write_or_delete(path: String, content: String) -> void:
	if content != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(content)
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
