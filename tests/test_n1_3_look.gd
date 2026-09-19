extends SceneTree
## N1-3 の自動確認：マウスでカメラを回し、ロボットがカメラの向きに追従するか調べる。
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n1_3_look.gd

var field: Node
var robot: Robot
var rig: CameraRig
var input: PlayerInput
var camera: Camera3D
var frame := 0
var failed := false
var start_pos := Vector3.ZERO
var yaw_before := 0.0


func _initialize() -> void:
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	robot = field.get_node("Robot")
	rig = field.get_node("CameraRig")
	input = field.get_node("PlayerInput")
	camera = field.get_node("CameraRig/Camera3D")


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		30:
			_mouse(Vector2(300, 0))  # マウスを右へ
		35:
			_check_turn_right()
			start_pos = robot.global_position
			Input.action_press("move_forward")
		95:
			Input.action_release("move_forward")
			_check_walk_forward()
			_mouse(Vector2(0, -3000))  # マウスを上へ大きく
		100:
			_check_pitch_up_limit()
			_mouse(Vector2(0, 6000))  # マウスを下へ大きく
		105:
			_check_pitch_down_limit()
			_key_esc()
		110:
			yaw_before = rig.yaw
			_mouse(Vector2(300, 0))
		115:
			_check_esc()
			_click()
		120:
			_report(input.look_enabled, "画面クリックでカメラ操作に戻る")
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _check_turn_right() -> void:
	# 右を向く = 上から見て時計回り = yaw がマイナス
	_report(rig.yaw < -0.5, "マウス右でカメラが右を向く (yaw %.2f)" % rig.yaw)
	_report(absf(robot.rotation.y - rig.yaw) < 0.01, "ロボットがカメラと同じ向き (機体 %.2f / カメラ %.2f)" % [robot.rotation.y, rig.yaw])
	var back := robot.global_transform.basis.z  # 機体の背中側
	var to_cam := camera.global_position - robot.global_position
	to_cam.y = 0.0
	_report(to_cam.normalized().dot(back) > 0.95, "カメラが機体の真後ろにいる")


func _check_walk_forward() -> void:
	var moved := robot.global_position - start_pos
	moved.y = 0.0
	var forward := -robot.global_transform.basis.z
	_report(moved.length() > 3.0 and moved.normalized().dot(forward) > 0.95,
		"向いた方向に W で歩く (移動量 %.2fm)" % moved.length())


func _check_pitch_up_limit() -> void:
	_report(is_equal_approx(rig.pitch, deg_to_rad(rig.pitch_max_deg)), "上向きは %.0f° で止まる (今 %.1f°)" % [rig.pitch_max_deg, rad_to_deg(rig.pitch)])
	_report(camera.global_position.y > robot.global_position.y, "上を向いてもカメラが地面に潜らない (高さ %.2f)" % camera.global_position.y)


func _check_pitch_down_limit() -> void:
	_report(is_equal_approx(rig.pitch, deg_to_rad(rig.pitch_min_deg)), "下向きは %.0f° で止まる (今 %.1f°)" % [rig.pitch_min_deg, rad_to_deg(rig.pitch)])


func _check_esc() -> void:
	_report(not input.look_enabled, "Esc でカメラ操作が止まる")
	_report(is_equal_approx(rig.yaw, yaw_before), "Esc 中はマウスを動かしてもカメラが回らない")


func _mouse(d: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = d
	ev.screen_relative = d
	Input.parse_input_event(ev)


func _key_esc() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)


func _click() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.parse_input_event(ev)


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
