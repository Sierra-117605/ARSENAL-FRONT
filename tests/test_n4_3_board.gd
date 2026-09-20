extends SceneTree
## 乗り換えの試作の確認（差別化の柱・案2）。
##
## 確かめること：
##  1. 起動時はプレイヤー機（多用途歩行機）を操縦している
##  2. 遠い機体には乗り換えられない
##  3. 近づいて F を押すと、無人の予備機（偵察歩行機）に乗り移れる
##  4. 乗り換えると、操作・カメラ・耐久バーの相手がすべて新しい機体になる
##  5. 元の機体は無人になり、その場で止まる
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
			# 2：遠ざけてから乗り換えを試す
			spare.global_position = Vector3(300, 0, 0)
			_report(not input.try_board_nearby(), "遠い機体には乗り換えられない")
		15:
			# 3：近くに置いてから乗り換え
			spare.global_position = robot.global_position + Vector3(20, 0, 0)
		20:
			_report(input.try_board_nearby(), "近くの無人機に乗り換えられる")
			_report(pilot.get_vehicle() == spare, "操縦の相手が予備機に変わる")
			_report(rig.target == spare, "カメラが予備機を追う")
			_report(bar.target == spare, "耐久バーが予備機の耐久を出す")
			_report(robot.control["move_z"] == 0.0, "降りた機体は操作を受け取らない")
			# 5：乗り換えた先が動き、降りた機体は止まる
			spare_pos_at_board = spare.global_position
			robot_pos_at_board = robot.global_position
			Input.action_press("move_forward")
		40:
			Input.action_release("move_forward")
			var spare_moved := spare.global_position.distance_to(spare_pos_at_board)
			var robot_moved := robot.global_position.distance_to(robot_pos_at_board)
			_report(spare_moved > 2.0, "乗り換えた先の機体が動く (%.1fm)" % spare_moved)
			_report(robot_moved < 1.0, "降りた機体はその場に残る (%.1fm)" % robot_moved)
		45:
			# 6：戻れる
			spare.global_position = robot.global_position + Vector3(15, 0, 0)
		50:
			_report(input.try_board_nearby(), "もう一度 F で元の機体に戻れる")
			_report(pilot.get_vehicle() == robot, "操縦の相手がプレイヤー機に戻る")
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
