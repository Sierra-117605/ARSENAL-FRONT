extends SceneTree
## N1-7 の自動確認：歩いている間だけ脚が前後に振れ、止まると元に戻るか調べる。
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n1_7_step_motion.gd
## 画像も撮る場合（--headless を外す）：... -- --shot=<保存先.png>

var field: Node
var robot: Robot
var leg_l: Node3D
var leg_r: Node3D
var frame := 0
var failed := false
var shot_path := ""
var max_swing := 0.0
var saw_forward := false
var saw_backward := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_path = arg.substr(7)
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	robot = field.get_node("Robot")
	leg_l = field.get_node("Robot/Visual/LegPivotL")
	leg_r = field.get_node("Robot/Visual/LegPivotR")


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame > 30 and frame < 180:
		# 歩いている間の脚の角度を記録
		max_swing = maxf(max_swing, absf(leg_l.rotation.x))
		if leg_l.rotation.x > 0.05:
			saw_forward = true
		if leg_l.rotation.x < -0.05:
			saw_backward = true
	match frame:
		30:
			_report(is_zero_approx(leg_l.rotation.x), "止まっている時、脚はまっすぐ")
			Input.action_press("move_forward")
		120:
			if shot_path != "":
				_save_shot()
		180:
			Input.action_release("move_forward")
			_report(max_swing > deg_to_rad(10.0), "歩くと脚が振れる (最大 %.1f°)" % rad_to_deg(max_swing))
			_report(saw_forward and saw_backward, "脚が前にも後ろにも振れる（交互に動く）")
			_report(absf(leg_l.rotation.x + leg_r.rotation.x) < 0.001, "左右の脚が逆向きに動く")
		240:
			_report(absf(leg_l.rotation.x) < deg_to_rad(1.0), "止まると脚がまっすぐに戻る (%.1f°)" % rad_to_deg(leg_l.rotation.x))
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _save_shot() -> void:
	await process_frame
	root.get_texture().get_image().save_png(shot_path)
	print("画像を保存: ", shot_path)


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
