extends SceneTree
## N1-5 の自動確認：標的 5 個を順に狙って撃ち、当たるたびに色が変わり 3 発で壊れるか調べる。
## カメラの向きは「照準が標的の中心に重なる」ようにテストが直接合わせる（マウス操作の代わり）。
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n1_5_targets.gd
## 画像も撮る場合（--headless を外す）：... -- --shot=<保存先.png>

const TIMEOUT_FRAMES := 600  # 1 個あたり最大 10 秒

var field: Node
var rig: CameraRig
var camera: Camera3D
var targets: Array = []
var current: Target
var index := -1
var frame := 0
var frame_in_target := 0
var failed := false
var shot_path := ""
var shot_taken := false
var colors_seen: Array = []
var hp_seen: Array = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_path = arg.substr(7)
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	rig = field.get_node("CameraRig")
	camera = field.get_node("CameraRig/Camera3D")
	targets = field.get_node("Targets").get_children()


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame < 30:
		return false
	if frame == 30:
		_report(targets.size() == 5, "標的が 5 個置かれている (%d 個)" % targets.size())
		_next_target()
		return false
	if index >= targets.size():
		return _finish()

	frame_in_target += 1
	if not is_instance_valid(current):
		# 壊れて消えた
		_check_destroyed()
		_next_target()
		return false
	_aim_at(current)
	# 当たって耐久が変わったら、その時の色を記録
	if hp_seen.is_empty() or hp_seen[-1] != current.hp:
		hp_seen.append(current.hp)
		colors_seen.append(current.material.albedo_color)
		if current.hp == 1 and shot_path != "" and not shot_taken:
			shot_taken = true
			_save_shot()
	if frame_in_target > TIMEOUT_FRAMES:
		_report(false, "%s を時間内に壊せなかった (残り耐久 %d)" % [current.name, current.hp])
		current.queue_free()
		_next_target()
	return false


func _next_target() -> void:
	index += 1
	frame_in_target = 0
	hp_seen = []
	colors_seen = []
	if index >= targets.size():
		current = null
		Input.action_release("fire")
		return
	current = targets[index]
	Input.action_press("fire")


func _check_destroyed() -> void:
	var name_s: String = "標的%d" % (index + 1)
	# 3 → 2 → 1 と減り、毎回違う色になっていれば OK
	var ok: bool = hp_seen == [3, 2, 1] and colors_seen[0] != colors_seen[1] and colors_seen[1] != colors_seen[2]
	_report(ok, "%s：当たるたびに色が変わり (耐久 %s)、3 発目で壊れて消えた" % [name_s, hp_seen])


func _finish() -> bool:
	var left := 0
	for t in targets:
		if is_instance_valid(t):
			left += 1
	_report(left == 0, "5 個すべて壊せた (残り %d 個)" % left)
	print("RESULT: ", "FAIL" if failed else "PASS")
	return true


## 照準（画面中央）が標的の中心に重なるようにカメラの向きを合わせる
func _aim_at(t: Target) -> void:
	var center := t.global_position + Vector3(0, 1.5, 0)
	var dir := center - camera.global_position
	rig.yaw = atan2(-dir.x, -dir.z)
	rig.pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())


func _save_shot() -> void:
	await process_frame
	root.get_texture().get_image().save_png(shot_path)
	print("画像を保存: ", shot_path)


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
