extends SceneTree
## N1-4 の自動確認（N1-5b で自機 15m に合わせて壁を拡大）：左クリックで弾が照準の方向へ飛び、物に当たると消えるか調べる。
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n1_4_fire.gd
## 画像も撮る場合（--headless を外す）：... --script res://tests/test_n1_4_fire.gd -- --shot=<保存先.png>

var field: Node
var robot: Robot
var input: PlayerInput
var wall: StaticBody3D
var frame := 0
var failed := false
var shot_path := ""
var max_bullets_seen := 0
var first_bullet: Bullet
var first_bullet_start := Vector3.ZERO


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_path = arg.substr(7)
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	robot = field.get_node("Robot")
	input = field.get_node("PlayerInput")
	_add_test_wall()


## 試験用の壁：正面 100m 先。当たった回数を数える
func _add_test_wall() -> void:
	var script := GDScript.new()
	script.source_code = "extends StaticBody3D\nvar hits := 0\nfunc take_hit(d: int) -> void:\n\thits += d\n"
	script.reload()
	wall = StaticBody3D.new()
	wall.set_script(script)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 40, 2)
	shape.shape = box
	wall.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	wall.add_child(mesh)
	field.add_child(wall)
	wall.position = Vector3(0, 20, -100)  # フィールドは原点にあるので位置＝世界座標


func _physics_process(_delta: float) -> bool:
	frame += 1
	var bullets := _bullets()
	max_bullets_seen = maxi(max_bullets_seen, bullets.size())
	if first_bullet == null and not bullets.is_empty():
		first_bullet = bullets[0]
		first_bullet_start = first_bullet.global_position
	match frame:
		30:
			Input.action_press("fire")
		40:
			if is_instance_valid(first_bullet):
				var moved := first_bullet.global_position - first_bullet_start
				_report(moved.dot(Vector3.FORWARD) > 1.0, "弾が前へ飛んでいる (%.1fm)" % moved.length())
			else:
				_report(false, "弾が出ていない")
			if shot_path != "":
				_save_shot()
		90:
			Input.action_release("fire")
		150:
			var hits: int = wall.get("hits")
			# 1 秒間 (60 フレーム) 押しっぱなし・0.25 秒間隔 → 4〜5 発
			_report(hits >= 4 and hits <= 5, "押している間、連射して壁に当たる (%d 発命中)" % hits)
			_report(_bullets().is_empty(), "当たった弾は消える")
			_check_no_fire_when_released()
		160:
			input._set_look_enabled(false)
			Input.action_press("fire")
		200:
			Input.action_release("fire")
			_report(_bullets().is_empty() and int(wall.get("hits")) == hits_at_release, "Esc 中はクリックしても撃たない")
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


var hits_at_release := 0


func _check_no_fire_when_released() -> void:
	hits_at_release = wall.get("hits")


func _bullets() -> Array:
	var list := []
	for child in field.get_children():
		if child is Bullet:
			list.append(child)
	return list


func _save_shot() -> void:
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(shot_path)
	print("画像を保存: ", shot_path)


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
