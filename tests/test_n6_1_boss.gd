extends SceneTree
## ボス戦（レールガン要塞）の確認（SPEC §0.8）。
##
## 確かめること：
##  1. ボス任務を選ぶと要塞が戦場に出る（迎撃砲台・発電施設・砲身・中枢）
##  2. 最初は段階1。段階2・3の部位は攻撃を受け付けない（順番に壊させる）
##  3. 迎撃砲台を全部壊すと段階2へ進み、発電施設が攻撃できるようになる
##  4. 発電施設を全部壊すと段階3へ進み、砲身と中枢が攻撃できるようになる
##  5. 砲身と中枢を壊すと勝利になる
##  6. レールガンは予兆のあと発射され、遮蔽物が無いと大ダメージを受ける
##  7. 段階が進むとレールガンの間隔が短くなる
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n6_1_boss.gd

var field: Node
var battle: Node
var boss: BossFortress
var frame := 0
var failed := false
var mission_before := ""
var progress_before := ""
var stage_events: Array[int] = []


func _initialize() -> void:
	mission_before = _read(MissionData.CHOICE_PATH)
	progress_before = _read(ProgressStore.PATH)
	MissionData.save_choice("railgun_fortress", "normal")
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	battle = field
	(field.get_node("Robot") as Robot).use_saved_loadout = false



func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame > 900:
		_report(false, "進まなくなった（打ち切り）")
		_restore()
		print("RESULT: FAIL")
		return true
	match frame:
		10:
			# 戦場の初期化が終わってから参照を取る
			boss = battle.boss
			if boss != null:
				boss.stage_changed.connect(func(s: int): stage_events.append(s))
			_report(boss != null, "ボス任務で要塞が出る")
			if boss == null:
				_restore()
				print("RESULT: FAIL")
				return true
			_report(boss.parts_of_stage(1).size() == 4, "迎撃砲台が 4 基ある (%d)" % boss.parts_of_stage(1).size())
			_report(boss.parts_of_stage(2).size() == 2, "発電施設が 2 基ある (%d)" % boss.parts_of_stage(2).size())
			_report(boss.parts_of_stage(3).size() == 2, "砲身と中枢がある (%d)" % boss.parts_of_stage(3).size())
			_report(boss.stage == 1, "最初は段階 1")
			# 2：段階2の部位はまだ攻撃を受け付けない
			var generator := boss.parts_of_stage(2)[0]
			var before := generator.hp
			generator.take_hit(1000)
			_report(generator.hp == before, "段階が来ていない部位は攻撃を受け付けない（耐久 %d のまま）" % generator.hp)
		20:
			# 3：迎撃砲台を全部壊す
			for part in boss.parts_of_stage(1):
				part.take_hit(100000)
		25:
			_report(boss.stage == 2, "迎撃砲台を全滅させると段階 2 へ (%d)" % boss.stage)
			var generator := boss.parts_of_stage(2)[0]
			var before := generator.hp
			generator.take_hit(50)
			_report(generator.hp < before, "段階 2 の発電施設が攻撃できるようになる (%d → %d)" % [before, generator.hp])
			set_meta("interval_stage2", boss.railgun_interval)
			for part in boss.parts_of_stage(2):
				part.take_hit(100000)
		30:
			_report(boss.stage == 3, "発電施設を全滅させると段階 3 へ (%d)" % boss.stage)
			_report(boss.railgun_interval < 22.0, "段階が進むとレールガンの間隔が短くなる (%.0f 秒)" % boss.railgun_interval)
			var core := boss.parts_of_stage(3)[1]
			var before := core.hp
			core.take_hit(50)
			_report(core.hp < before, "段階 3 の中枢が攻撃できるようになる (%d → %d)" % [before, core.hp])
			# 6：レールガンの直撃を確かめる（遮蔽なし）
			var robot: Robot = field.get_node("Robot")
			# 物陰の無い開けた場所に立たせる（遮蔽の有無を確かめるため）
			robot.global_position = boss.global_position + Vector3(90, 0, 200)
			set_meta("hp_before", robot.hp)
			boss.railgun_timer = 0.05
		40:
			var robot: Robot = field.get_node("Robot")
			_report(robot.hp < int(get_meta("hp_before")),
				"遮蔽が無いとレールガンが直撃する (%d → %d)" % [get_meta("hp_before"), robot.hp])
			# 遮蔽物（壁）の裏に入れば当たらない
			var wall := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(60, 40, 6)
			shape.shape = box
			wall.add_child(shape)
			field.add_child(wall)
			wall.position = robot.global_position + Vector3(0, 20, -20)
			set_meta("hp_before2", robot.hp)
			boss.railgun_timer = 0.05
		50:
			var robot: Robot = field.get_node("Robot")
			_report(robot.hp == int(get_meta("hp_before2")),
				"物陰に隠れていればレールガンは当たらない (%d のまま)" % robot.hp)
			# 5：砲身と中枢を壊して勝利
			for part in boss.parts_of_stage(3):
				part.take_hit(100000)
		55:
			_report(battle.outcome == "win", "砲身と中枢を壊すと勝利 (%s)" % battle.outcome)
			# 段階1の通知は戦場の初期化時（テストが見る前）に出るので、記録は 2→3 になる
			_report(stage_events == [2, 3], "段階が 2 → 3 と進んだ (%s)" % [stage_events])
			_report(battle.earned_materials >= 1000, "ボスの報酬が入る（資材 %d／希少素材 %d）" % [
				battle.earned_materials, battle.earned_rare])
			_restore()
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


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
