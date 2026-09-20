extends SceneTree
## 戦車の確認（乗り換えの幅を広げる。SPEC §0.13 柱1）。
##
## 確かめること：
##  1. 戦場に戦車があり、AI が操縦している（自軍機として戦う）
##  2. 兵士が降りて近づけば、戦車に乗り込める
##  3. 戦車は前進が速い（ロボットより速い）
##  4. 戦車は横歩きできない（左右入力では旋回し、真横には動かない）
##  5. 砲塔は狙った方向を向く
##  6. 戦車の武器は一撃が重い（ロボットの標準より高威力）
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n7_1_tank.gd

var field: Node
var tank: Tank
var robot: Robot
var soldier: Soldier
var input: PlayerInput
var pilot: Occupant
var frame := 0
var failed := false
var mission_before := ""
var start_pos := Vector3.ZERO
var start_yaw := 0.0


func _initialize() -> void:
	if FileAccess.file_exists(MissionData.CHOICE_PATH):
		mission_before = FileAccess.get_file_as_string(MissionData.CHOICE_PATH)
	MissionData.save_choice("sweep_plain", "normal")
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	tank = field.get_node("Tank")
	robot = field.get_node("Robot")
	robot.use_saved_loadout = false
	soldier = field.get_node("Soldier")
	input = field.get_node("PlayerInput")
	pilot = field.get_node("Pilot")


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			_report(tank != null and tank.team == "player", "戦場に自軍の戦車がある")
			var seat: Seat = tank.get_node("DriverSeat")
			_report(seat.occupant is AIPilot, "戦車は AI が操縦している")
			_report(tank.get_node("Weapon").damage > 10,
				"戦車の武器は一撃が重い（威力 %d）" % tank.get_node("Weapon").damage)
			# 2：降りて戦車へ
			_report(input.try_exit(), "機体から降りた")
		15:
			soldier.global_position = tank.global_position + Vector3(4, 0, 0)
		20:
			_report(input.try_board_from_foot(), "兵士が戦車に乗り込める")
			_report(pilot.get_vehicle() == tank, "戦車を操縦している")
			start_pos = tank.global_position
			start_yaw = tank.rotation.y
			Input.action_press("move_forward")
		50:
			Input.action_release("move_forward")
			var moved := tank.global_position.distance_to(start_pos)
			_report(moved > 6.0, "戦車が前進する (%.1fm)" % moved)
			_report(tank.drive_speed > robot.walk_speed,
				"戦車はロボットより速い (%.1f > %.1f m/秒)" % [tank.drive_speed, robot.walk_speed])
			# 4：左右入力で旋回する（横に動かない）
			# いったん止めてから旋回だけを見る（惰性で前に進むのは戦車として正しい動き）
			tank.velocity = Vector3.ZERO
			start_pos = tank.global_position
			start_yaw = tank.rotation.y
			Input.action_press("move_right")
		80:
			Input.action_release("move_right")
			var turned := absf(tank.rotation.y - start_yaw)
			# 真横（車体の右方向）へどれだけずれたかを見る
			var moved_vec: Vector3 = tank.global_position - start_pos
			var side_dir := Vector3(cos(start_yaw), 0.0, -sin(start_yaw))
			var sideways := absf(moved_vec.dot(side_dir))
			_report(turned > deg_to_rad(10.0), "左右入力で車体が旋回する (%.0f 度)" % rad_to_deg(turned))
			_report(sideways < 2.0, "真横には滑らない（横ずれ %.1fm）" % sideways)
			# 5：砲塔の向き
			var rig: CameraRig = field.get_node("CameraRig")
			rig.yaw = tank.rotation.y + deg_to_rad(60.0)
		90:
			var turret: Node3D = tank.get_node("Visual/Turret")
			var diff := absf(wrapf(turret.global_rotation.y - tank.rotation.y, -PI, PI))
			_report(diff > deg_to_rad(15.0),
				"砲塔が車体と別に狙った方向を向く（差 %.0f 度）" % rad_to_deg(diff))
			_restore()
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _restore() -> void:
	if mission_before != "":
		var f := FileAccess.open(MissionData.CHOICE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(mission_before)
	elif FileAccess.file_exists(MissionData.CHOICE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MissionData.CHOICE_PATH))


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
