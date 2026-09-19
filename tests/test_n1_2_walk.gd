extends SceneTree
## N1-2 の自動確認：W/A/S/D を 1 秒ずつ押したことにして、ロボットが正しい方向に動くか調べる。
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n1_2_walk.gd

const STEPS := [
	# [押す操作, 期待する移動方向, 説明]
	["move_forward", Vector3(0, 0, -1), "W で前へ"],
	["move_back", Vector3(0, 0, 1), "S で後ろへ"],
	["move_left", Vector3(-1, 0, 0), "A で左へ"],
	["move_right", Vector3(1, 0, 0), "D で右へ"],
]
const FRAMES_PER_STEP := 60  # 1 秒（物理 60 回/秒）

var robot: Robot
var rig: Node3D
var step := -1
var frame := 0
var start_pos := Vector3.ZERO
var failed := false


func _initialize() -> void:
	var field: Node = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	robot = field.get_node("Robot")
	rig = field.get_node("CameraRig")


func _physics_process(_delta: float) -> bool:
	frame += 1
	if step == -1:
		# 最初の 30 フレームは着地待ち
		if frame < 30:
			return false
		_check_standing()
		_begin(0)
		return false
	if frame < FRAMES_PER_STEP:
		return false
	_finish_step()
	if step + 1 < STEPS.size():
		_begin(step + 1)
		return false
	_check_camera()
	_check_serialize()
	print("RESULT: ", "FAIL" if failed else "PASS")
	return true


func _check_standing() -> void:
	var ok := robot.is_on_floor() and absf(robot.global_position.y) < 0.1
	_report(ok, "着地して立っている (高さ %.2f)" % robot.global_position.y)


func _begin(i: int) -> void:
	step = i
	frame = 0
	start_pos = robot.global_position
	Input.action_press(STEPS[i][0])


func _finish_step() -> void:
	Input.action_release(STEPS[step][0])
	var moved: Vector3 = robot.global_position - start_pos
	moved.y = 0.0
	var dir: Vector3 = STEPS[step][1]
	var ok := moved.length() > 3.0 and moved.normalized().dot(dir) > 0.95
	_report(ok, "%s (移動量 %.2fm, 向き %s)" % [STEPS[step][2], moved.length(), moved.normalized()])


func _check_camera() -> void:
	var gap := rig.global_position.distance_to(robot.global_position)
	_report(gap < 0.5, "カメラがロボットについて来ている (ずれ %.2fm)" % gap)


func _check_serialize() -> void:
	var text := JSON.stringify(robot.to_dict())
	_report(JSON.parse_string(text) is Dictionary, "状態を JSON にできる: " + text)


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
