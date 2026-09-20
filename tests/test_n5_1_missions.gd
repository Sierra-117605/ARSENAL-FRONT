extends SceneTree
## N5-1 の確認：任務データと勝敗条件（SPEC §0.14）。
##
## 確かめること：
##  1. 任務が 3 種類あり、それぞれ易・中・難の設定を持つ
##  2. 難易度を上げると敵が増え、強くなり、報酬も増える
##  3. 殲滅：敵を全滅させたら勝ち
##  4. 防衛：拠点が壊れたら負け／守り切れば（時間切れ）勝ち
##  5. 破壊：目標を壊したら勝ち／時間切れは負け
##  6. 選んだ任務は保存され、戦場がその設定（敵の数・耐久）で始まる
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n5_1_missions.gd

var field: Node
var battle: Node
var frame := 0
var failed := false
var stage := 0
var choice_before := ""
var progress_before := ""


func _initialize() -> void:
	if FileAccess.file_exists(MissionData.CHOICE_PATH):
		choice_before = FileAccess.get_file_as_string(MissionData.CHOICE_PATH)
	if FileAccess.file_exists(ProgressStore.PATH):
		progress_before = FileAccess.get_file_as_string(ProgressStore.PATH)
	_check_data()
	_start_mission("sweep_plain", "hard")


## 1・2：データの確認
func _check_data() -> void:
	_report(MissionData.all().size() == 3, "任務が 3 種類ある (%d)" % MissionData.all().size())
	var easy := MissionData.setup("sweep_plain", "easy")
	var hard := MissionData.setup("sweep_plain", "hard")
	_report(int(hard["enemy_count"]) > int(easy["enemy_count"])
			and int(hard["enemy_hp"]) > int(easy["enemy_hp"])
			and int(hard["materials"]) > int(easy["materials"]),
		"難易度を上げると敵が増えて強くなり、報酬も増える（易 敵%d体/耐久%d/報酬%d → 難 敵%d体/耐久%d/報酬%d）" % [
			easy["enemy_count"], easy["enemy_hp"], easy["materials"],
			hard["enemy_count"], hard["enemy_hp"], hard["materials"]])
	var defend := MissionData.setup("defend_depot", "normal")
	_report(float(defend["time_limit"]) > 0.0 and int(defend["objective_hp"]) > 0,
		"防衛には制限時間と拠点の耐久がある（%.0f 秒／耐久 %d）" % [defend["time_limit"], defend["objective_hp"]])


## 任務を選び直して戦場を作り直す
func _start_mission(mission_id: String, difficulty: String) -> void:
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
	# 進まなくなった時のための打ち切り（無限に待たない）
	if frame > 600:
		_report(false, "段階 %d で進まなくなった（打ち切り）" % stage)
		_restore()
		print("RESULT: FAIL")
		return true
	match stage:
		0:  # 殲滅（難）
			if frame == 10:
				_report(battle._enemies().size() == 5, "難易度の敵数が反映される（%d 体）" % battle._enemies().size())
				_report(battle._enemies()[0].max_hp == 220, "敵の耐久も反映される（%d）" % battle._enemies()[0].max_hp)
				_report(battle.objective == null, "殲滅では拠点も目標も出ない")
				for enemy in battle._enemies():
					enemy.take_hit(100000)
			elif frame == 15:
				_report(battle.outcome == "win", "殲滅：敵を全滅させたら勝ち (%s)" % battle.outcome)
				_report(battle.earned_materials >= 520, "難の報酬が入る（資材 %d）" % battle.earned_materials)
				stage = 1
				_start_mission("defend_depot", "normal")
		1:  # 防衛（拠点が壊れたら負け）
			if frame == 10:
				_report(battle.objective != null and battle.objective.team == "player",
					"防衛では守る拠点が出る（耐久 %d）" % (battle.objective.max_hp if battle.objective != null else 0))
				_report(battle.time_left > 0.0, "制限時間がある（残り %.0f 秒）" % battle.time_left)
				var robot_z: float = (field.get_node("Robot") as Node3D).global_position.z
				var enemy_z: float = (battle._enemies()[0] as Node3D).global_position.z
				var obj_z: float = battle.objective.global_position.z
				_report(absf(obj_z - robot_z) < absf(obj_z - enemy_z),
					"守る拠点は自陣側にある（拠点 z=%.0f／自機 z=%.0f／敵 z=%.0f）" % [obj_z, robot_z, enemy_z])
				battle.objective.take_hit(100000)
			elif frame == 15:
				_report(battle.outcome == "lose", "防衛：拠点が壊れたら負け (%s)" % battle.outcome)
				stage = 2
				_start_mission("defend_depot", "easy")
		2:  # 防衛（守り切れば勝ち）
			if frame == 10:
				# 敵を全滅させたら、時間を待たずに勝ちになるか
				for enemy in battle._enemies():
					enemy.take_hit(100000)
			elif frame == 15:
				_report(battle.outcome == "win", "防衛：敵を全滅させたら勝ち (%s)" % battle.outcome)
				stage = 21
				_start_mission("defend_depot", "easy")
		21:  # 防衛（時間切れまで守り切る）
			if frame == 10:
				battle.time_left = 0.2  # すぐ時間切れにする
			elif frame == 30:
				_report(battle.outcome == "win", "防衛：守り切れば（時間切れで）勝ち (%s)" % battle.outcome)
				stage = 3
				_start_mission("strike_facility", "normal")
		3:  # 破壊（目標を壊したら勝ち）
			if frame == 10:
				_report(battle.objective != null and battle.objective.team == "enemy",
					"破壊では目標施設が出る（耐久 %d）" % (battle.objective.max_hp if battle.objective != null else 0))
				var robot_z2: float = (field.get_node("Robot") as Node3D).global_position.z
				_report(battle.objective.global_position.z < robot_z2 - 100.0,
					"破壊目標は敵陣の奥にある（目標 z=%.0f／自機 z=%.0f）" % [
						battle.objective.global_position.z, robot_z2])
				battle.objective.take_hit(100000)
			elif frame == 15:
				_report(battle.outcome == "win", "破壊：目標を壊したら勝ち (%s)" % battle.outcome)
				stage = 4
				_start_mission("strike_facility", "hard")
		4:  # 破壊（時間切れは負け）
			if frame == 10:
				battle.time_left = 0.2
			elif frame == 30:
				_report(battle.outcome == "lose", "破壊：時間切れは負け (%s)" % battle.outcome)
				_restore()
				print("RESULT: ", "FAIL" if failed else "PASS")
				return true
	return false


func _restore() -> void:
	_write_or_delete(MissionData.CHOICE_PATH, choice_before)
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
