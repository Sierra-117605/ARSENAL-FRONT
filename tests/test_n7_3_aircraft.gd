extends SceneTree
## 航空機（攻撃機）の確認。エースコンバット風の「常に飛び続ける」操作（SPEC §0.15）。
## 実際にキーを押した・マウスを動かしたことにして飛ばす。
##
## 確かめること：
##  1. 戦場に攻撃機が駐機していて、兵士が歩いて行けば乗り込める
##  2. Space（加速）で滑走して離陸する
##  3. 空中では止まれない。Shift で減速しても最低速度より遅くならない
##  4. マウスを上に動かすと機首が上がり、高度が上がる
##  5. マウスを右に動かすと機体が右に傾き、その方向へ旋回する（傾けて曲がる）
##  6. 弾は機首の銃口の先から出る
##  7. カメラが航空機用の後方視点に切り替わる
##  8. 地面に突っ込むと墜落する（撃墜と同じ扱い）
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n7_3_aircraft.gd

var field: Node
var plane: Aircraft
var robot: Robot
var rig: CameraRig
var input: PlayerInput
var pilot: Occupant
var frame := 0
var failed := false
var mission_before := ""
var yaw_before := 0.0
var crashed := false


func _initialize() -> void:
	# 任務の設定に左右されないよう、基本の任務（殲滅・中）に固定する
	if FileAccess.file_exists(MissionData.CHOICE_PATH):
		mission_before = FileAccess.get_file_as_string(MissionData.CHOICE_PATH)
	MissionData.save_choice("sweep_plain", "normal")
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	plane = field.get_node("Aircraft")
	robot = field.get_node("Robot")
	robot.use_saved_loadout = false
	rig = field.get_node("CameraRig")
	input = field.get_node("PlayerInput")
	pilot = field.get_node("Pilot")
	plane.crashed.connect(func(): crashed = true)
	# 敵の弾で落とされないよう、今回は敵を取り除く（飛び方の確認に集中する）
	for enemy in field.get_node("Enemies").get_children():
		enemy.queue_free()


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		30:
			_report(plane.is_landed(), "攻撃機は地上に駐機している（速度 %.0fm/秒）" % plane.speed)
			input.toggle_board()  # 自機のロボットから降りる
		40:
			var soldier: Node3D = pilot.body
			soldier.global_position = plane.global_position + Vector3(6, 0, 0)
			soldier.force_update_transform()
		50:
			_report(input.toggle_board(), "兵士が攻撃機に乗り込める")
			_report(rig.get_current_view() is ChaseView, "カメラが航空機用の後方視点になる")
			Input.action_press("throttle_up")  # Space を押しっぱなしにする
		170:
			_report(not plane.is_landed(), "加速すると離陸する（高度 %.0fm・速度 %.0fm/秒）" % [
				plane.global_position.y, plane.speed])
			_report(plane.speed >= plane.min_speed, "空中では最低速度を下回らない (%.0f)" % plane.speed)
			Input.action_release("throttle_up")
			# 4：マウスを上に動かして機首を上げる（画面上向き＝ y が負の動き）
			_move_mouse(0.0, -120.0)
			set_meta("height_before", plane.global_position.y)
		290:
			_report(plane.rotation.x > deg_to_rad(10.0),
				"マウスを上に動かすと機首が上がる（%.0f 度）" % rad_to_deg(plane.rotation.x))
			_report(plane.global_position.y > float(get_meta("height_before")) + 20.0,
				"機首を上げると高度が上がる（%.0fm → %.0fm）" % [
					get_meta("height_before"), plane.global_position.y])
			# 操縦桿を中央に戻して水平飛行へ
			_move_mouse(0.0, 120.0)
		350:
			# 5：マウスを右に動かして旋回
			yaw_before = plane.rotation.y
			_move_mouse(150.0, 0.0)
		410:
			_report(plane.rotation.z < deg_to_rad(-10.0),
				"マウスを右に動かすと機体が右に傾く（%.0f 度）" % rad_to_deg(-plane.rotation.z))
			var turned: float = absf(wrapf(plane.rotation.y - yaw_before, -PI, PI))
			_report(turned > deg_to_rad(15.0),
				"傾けた方向へ旋回する（%.0f 度まわった）" % rad_to_deg(turned))
			_move_mouse(-150.0, 0.0)  # 操縦桿を中央へ戻す
		440:
			_check_muzzle()
			# 3：減速しても止まれない
			Input.action_press("throttle_down")
		560:
			Input.action_release("throttle_down")
			_report(absf(plane.speed - plane.min_speed) < 1.0,
				"Shift で減速しても最低速度で飛び続ける (%.0fm/秒)" % plane.speed)
			_report(not plane.is_landed(), "空中で止まることはできない")
			# 8：地面へ突っ込ませる
			plane.global_position = Vector3(plane.global_position.x, 40.0, plane.global_position.z)
			plane.rotation.x = deg_to_rad(-60.0)
			plane.force_update_transform()
		620:
			_report(crashed, "地面に突っ込むと墜落する")
			_report(not plane.is_alive(), "墜落した機体は撃墜と同じ扱いになる（耐久 %d）" % plane.hp)
			_restore_mission()
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


## マウスを動かしたことにする（操縦桿を倒す）
func _move_mouse(dx: float, dy: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.screen_relative = Vector2(dx, dy)
	ev.relative = Vector2(dx, dy)
	input._unhandled_input(ev)


## 弾が機首の銃口の先から出るか確かめる
func _check_muzzle() -> void:
	var aim: Vector3 = plane.global_position - plane.global_transform.basis.z * 300.0
	plane.control["aim"] = {"x": aim.x, "y": aim.y, "z": aim.z}
	plane._aim_gun()
	var muzzle: Node3D = plane.get_node("Visual/GunPivot/MuzzlePoint")
	var weapon: Weapon = plane.get_node("Weapon")
	var gap := weapon.global_position.distance_to(muzzle.global_position)
	_report(gap < 0.5, "銃口が機首の先にある（ずれ %.2fm）" % gap)
	weapon.cooldown = 0.0
	if not weapon.try_fire(aim, plane):
		_report(false, "弾が出なかった")
		return
	var newest: Bullet = null
	for child in field.get_children():
		if child is Bullet and (child as Bullet).shooter_rid == plane.get_rid():
			newest = child
	if newest == null:
		_report(false, "弾が見つからない")
		return
	var distance := newest.global_position.distance_to(muzzle.global_position)
	_report(distance < 20.0, "弾が銃口の位置から出る（%.1fm）" % distance)


## 任務の設定を元に戻す
func _restore_mission() -> void:
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
