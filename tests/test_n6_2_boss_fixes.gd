extends SceneTree
## ボス戦の不具合修正の確認（開発者の指摘）。
##
## 確かめること：
##  1. 徒歩の兵士で倒れた場合も「撃破（失敗）」になる
##  2. 乗っている機体が壊れた場合も失敗になる（従来どおり）
##  3. レールガンの予兆が出ると、味方 AI が物陰へ向かって走る
##  4. 物陰に入った味方 AI にはレールガンが当たらない
##  5. ボス戦の道中に物陰が置かれている
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n6_2_boss_fixes.gd

var field: Node
var battle: Node
var boss: BossFortress
var frame := 0
var stage := 0
var failed := false
var mission_before := ""
var progress_before := ""
var ally_start := Vector3.ZERO


func _initialize() -> void:
	mission_before = _read(MissionData.CHOICE_PATH)
	progress_before = _read(ProgressStore.PATH)
	_start()


func _start() -> void:
	if field != null:
		field.queue_free()
	MissionData.save_choice("railgun_fortress", "normal")
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	battle = field
	(field.get_node("Robot") as Robot).use_saved_loadout = false
	frame = 0


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame > 900:
		_report(false, "段階 %d で進まなくなった（打ち切り）" % stage)
		_restore()
		print("RESULT: FAIL")
		return true
	match stage:
		0:
			if frame == 10:
				boss = battle.boss
				var covers := field.get_node("Covers").get_child_count()
				_report(covers >= 8, "ボス戦の道中に物陰がある（全 %d 個）" % covers)
				# 1：兵士で降りて、その兵士を倒す
				var input: PlayerInput = field.get_node("PlayerInput")
				_report(input.try_exit(), "機体から降りた")
			elif frame == 15:
				var soldier: Soldier = field.get_node("Soldier")
				soldier.take_hit(100000)
			elif frame == 20:
				_report(battle.outcome == "lose", "徒歩の兵士が倒れたら失敗 (%s)" % battle.outcome)
				stage = 1
				_start()
		1:
			if frame == 10:
				# 2：乗っている機体を壊す
				(field.get_node("Robot") as Pilotable).take_hit(100000)
			elif frame == 15:
				_report(battle.outcome == "lose", "乗っている機体が壊れたら失敗 (%s)" % battle.outcome)
				stage = 2
				_start()
		2:
			if frame == 10:
				boss = battle.boss
				# 3：味方 AI を開けた場所に置き、予兆を出す
				var ally: Robot = field.get_node("SpareRobot")
				ally.global_position = boss.global_position + Vector3(0, 0, 150)
				ally_start = ally.global_position
				boss.railgun_timer = boss.warning_time - 0.05
			elif frame == 30:
				var ally: Robot = field.get_node("SpareRobot")
				var ai: AIPilot = field.get_node("SpareRobot/AIPilot")
				_report(boss.warning, "レールガンの予兆が出ている")
				_report(ally.control["move_z"] < 0.0, "味方 AI が前進して物陰へ向かう (%.1f)" % ally.control["move_z"])
				var moved := ally.global_position.distance_to(ally_start)
				_report(moved > 1.0, "実際に移動している (%.1fm)" % moved)
				_report(ai._best_cover_spot(ally, boss.get_node("RailgunMuzzle").global_position) != Vector3.INF,
					"隠れられる物陰を見つけられる")
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
