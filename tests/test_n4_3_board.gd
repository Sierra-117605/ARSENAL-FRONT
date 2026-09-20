extends SceneTree
## 乗り換えの試作の確認（差別化の柱・案2）。
##
## 確かめること：
##  1. 起動時はプレイヤー機（多用途歩行機）を操縦している
##  2. 乗ったまま別の機体へ飛び移ることはできない（必ず一度降りる）
##  3. 降りた兵士が近づいて F を押すと、味方機に乗り込める
##  4. 乗り換えると、操作・カメラ・耐久バーの相手がすべて新しい機体になる
##  5. 元の機体は AI が引き継ぐ（置き去りにならない）
##  6. もう一度 F を押すと元の機体に戻れる
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n4_3_board.gd

var field: Node
var robot: Robot
var spare: Robot
var input: PlayerInput
var rig: CameraRig
var bar: Control
var pilot: Occupant
var frame := 0
var failed := false
var spare_pos_at_board := Vector3.ZERO
var robot_pos_at_board := Vector3.ZERO


func _initialize() -> void:
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	robot = field.get_node("Robot")
	robot.use_saved_loadout = false
	spare = field.get_node("SpareRobot")
	input = field.get_node("PlayerInput")
	rig = field.get_node("CameraRig")
	bar = field.get_node("HUD/HealthBar")
	pilot = field.get_node("Pilot")


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			_report(pilot.get_vehicle() == robot, "最初はプレイヤー機を操縦している")
			_report(rig.target == robot and bar.target == robot, "カメラと耐久バーもプレイヤー機を見ている")
			# 2：乗ったままでは飛び移れない（F は「降りる」になる）
			spare.global_position = robot.global_position + Vector3(12, 0, 0)
			_report(input.toggle_board(), "乗っている時の F は降りる動作になる")
			_report(pilot.get_vehicle() == null, "機体から降りた（飛び移っていない）")
		15:
			# 3：兵士を予備機の近くへ歩かせた想定で位置を合わせる
			field.get_node("Soldier").global_position = spare.global_position + Vector3(6, 0, 0)
		20:
			_report(input.toggle_board(), "兵士が近づいて F を押すと乗り込める")
			_report(pilot.get_vehicle() == spare, "操縦の相手が予備機に変わる")
			_report(rig.target == spare, "カメラが予備機を追う")
			_report(bar.target == spare, "耐久バーが予備機の耐久を出す")
			var left_seat: Seat = robot.get_node("DriverSeat")
			_report(left_seat.occupant is AIPilot, "降りた機体は AI が操縦を引き継ぐ")
			# 5：乗り換えた先が動き、降りた機体は止まる
			spare_pos_at_board = spare.global_position
			robot_pos_at_board = robot.global_position
			Input.action_press("move_forward")
		40:
			Input.action_release("move_forward")
			var spare_moved := spare.global_position.distance_to(spare_pos_at_board)
			var robot_moved := robot.global_position.distance_to(robot_pos_at_board)
			_report(spare_moved > 2.0, "乗り換えた先の機体が動く (%.1fm)" % spare_moved)
			var robot_seat: Seat = robot.get_node("DriverSeat")
			_report(robot_seat.occupant is AIPilot,
				"降りた機体は AI が引き継いでいる（置き去りにならない。移動 %.1fm）" % robot_moved)
		45:
			# 6：降りて元の機体へ戻る
			_report(input.toggle_board(), "もう一度 F で降りる")
		50:
			# 兵士を元の機体のすぐ横に置く（歩いて戻った想定）。予備機は離しておく
			spare.global_position = robot.global_position + Vector3(120, 0, 0)
			field.get_node("Soldier").global_position = robot.global_position + Vector3(5, 0, 0)
			_report(input.toggle_board(), "元の機体に乗り込める")
			var boarded := pilot.get_vehicle()
			_report(boarded == robot, "操縦の相手がプレイヤー機に戻る（実際は %s。兵士→機体 %.1fm、兵士→予備機 %.1fm）" % [
				boarded.name if boarded != null else "なし",
				field.get_node("Soldier").global_position.distance_to(robot.global_position),
				field.get_node("Soldier").global_position.distance_to(spare.global_position)])
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
