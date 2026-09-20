extends SceneTree
## 兵士の徒歩操作と乗り降りの確認（差別化の柱・案2の完成部分。SPEC §0.13）。
##
## 確かめること：
##  1. 最初は機体に乗っていて、兵士の体は機体の中（見えない・当たらない）
##  2. F で降りると、兵士が機体の横に現れて見えるようになる
##  3. 降りた機体は AI が引き継ぐ
##  4. 徒歩の兵士を WASD で歩かせられる（機体より遅い）
##  5. 兵士でも撃てる（威力は機体より小さい）
##  6. カメラと耐久バーが兵士を見る（兵士の耐久は 100）
##  7. 機体に近づいて F を押すと乗り込める。兵士はまた機体の中に入る
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n4_8_soldier.gd

var field: Node
var robot: Robot
var soldier: Soldier
var input: PlayerInput
var pilot: Occupant
var rig: CameraRig
var bar: Control
var frame := 0
var failed := false
var soldier_pos := Vector3.ZERO


func _initialize() -> void:
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	robot = field.get_node("Robot")
	robot.use_saved_loadout = false
	soldier = field.get_node("Soldier")
	input = field.get_node("PlayerInput")
	pilot = field.get_node("Pilot")
	rig = field.get_node("CameraRig")
	bar = field.get_node("HUD/HealthBar")


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			_report(pilot.get_vehicle() == robot, "最初は機体に乗っている")
			_report(not soldier.visible, "兵士の体は機体の中（見えない）")
			_report(pilot.get_controlled() == robot, "操作している相手は機体")
		15:
			# 2：降りる
			_report(input.try_exit(), "F で機体から降りられる")
			_report(soldier.visible, "兵士が現れる")
			_report(pilot.get_vehicle() == null, "もう機体には乗っていない")
			_report(pilot.get_controlled() == soldier, "操作している相手は兵士")
			_report(rig.target == soldier and bar.target == soldier, "カメラと耐久バーが兵士を見る")
			_report(soldier.max_hp == 100, "兵士の耐久は 100（機体より脆い）")
			var seat: Seat = robot.get_node("DriverSeat")
			_report(seat.occupant is AIPilot, "降りた機体は AI が引き継ぐ")
			soldier_pos = soldier.global_position
			Input.action_press("move_forward")
		45:
			Input.action_release("move_forward")
			var moved := soldier.global_position.distance_to(soldier_pos)
			_report(moved > 1.0, "兵士が歩ける (%.1fm)" % moved)
			_report(soldier.walk_speed < robot.walk_speed,
				"兵士は機体より遅い (%.1f < %.1f m/秒)" % [soldier.walk_speed, robot.walk_speed])
			# 5：撃てる
			var weapon: Weapon = soldier.get_node("Weapon")
			_report(weapon.try_fire(soldier.global_position + Vector3(0, 2, -50), soldier),
				"兵士でも撃てる")
			_report(weapon.damage < 10, "兵士の武器は機体より弱い (威力 %d)" % weapon.damage)
		50:
			# 7：機体に戻る
			soldier.global_position = robot.global_position + Vector3(5, 0, 0)
		55:
			_report(input.try_board_from_foot(), "機体に近づいて乗り込める")
			_report(pilot.get_vehicle() == robot, "また機体を操縦している")
			_report(not soldier.visible, "兵士は機体の中に戻る")
			_report(rig.target == robot and bar.target == robot, "カメラと耐久バーが機体に戻る")
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
