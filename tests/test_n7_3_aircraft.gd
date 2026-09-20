extends SceneTree
## 航空機（攻撃機）の確認。実際にキーを押したことにして飛ばす。
##
## 確かめること：
##  1. 戦場に攻撃機が駐機していて、兵士が歩いて行けば乗り込める
##  2. Space で上がり、キーを離すとその高さで止まる（ホバリング）
##  3. W で前に飛ぶとロボットの歩きよりずっと速い
##  4. 物陰（遮蔽ブロック）の上を飛び越えられる
##  5. 機首が狙った方向を向き、弾は機首の銃口の先から出る
##  6. 空中では降りられない。Shift で降りて着陸すれば降りられる
##  7. 誰も乗っていない攻撃機は勝手に飛んで行かず、空にいても自分で降りてくる
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
var hover_height := 0.0


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
	# 敵の弾で落とされないよう、今回は敵を取り除く（飛び方の確認に集中する）
	for enemy in field.get_node("Enemies").get_children():
		enemy.queue_free()


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		30:
			_report(plane != null, "戦場に攻撃機が置かれている")
			_report(plane.is_landed() and plane.global_position.y < 1.0,
				"誰も乗っていない攻撃機は駐機している（高さ %.1fm）" % plane.global_position.y)
			input.toggle_board()  # 自機のロボットから降りる
		40:
			# 兵士を攻撃機の横まで運ぶ（歩く時間の代わり）
			var soldier: Node3D = pilot.body
			soldier.global_position = plane.global_position + Vector3(6, 0, 0)
			soldier.force_update_transform()
		50:
			_report(input.toggle_board(), "兵士が攻撃機に乗り込める")
			_report(pilot.get_vehicle() == plane, "操縦する機体が攻撃機になる")
			rig.yaw = 0.0  # 正面（-Z 方向）を向かせる
			Input.action_press("ascend")
		140:
			_report(plane.global_position.y > 15.0,
				"Space で空へ上がる（高さ %.0fm）" % plane.global_position.y)
			_report(not plane.is_landed(), "空中にいる間は着陸していない")
			_report(not input.try_exit(), "空中では降りられない")
			_report(pilot.get_vehicle() == plane, "降りられないので操縦は続いている")
			Input.action_release("ascend")
		160:
			# 勢いが止まってからの高さを基準にする（急には止まらない）
			hover_height = plane.global_position.y
		220:
			var drift: float = absf(plane.global_position.y - hover_height)
			_report(drift < 1.5, "キーを離すとその高さで浮いたまま止まる（ずれ %.1fm）" % drift)
			set_meta("pos_before", plane.global_position)
			Input.action_press("move_forward")
		400:
			var moved: float = plane.global_position.distance_to(Vector3(get_meta("pos_before")))
			_report(moved > 60.0, "3 秒で %.0fm 飛ぶ（ロボットの歩き %.0fm より速い）" % [
				moved, robot.walk_speed * 3.0])
			# 4：物陰の手前・高さ 30m から突っ込んで、上を越えられるか
			var cover: Node3D = field.get_node("Covers/Cover1")
			plane.global_position = Vector3(cover.global_position.x, 30.0, cover.global_position.z + 90.0)
			plane.velocity = Vector3.ZERO
			plane.force_update_transform()
		560:
			var cover: Node3D = field.get_node("Covers/Cover1")
			var passed: float = cover.global_position.z - plane.global_position.z
			_report(passed > 5.0, "物陰の上を飛び越えられる（通り過ぎた距離 %.0fm）" % passed)
			Input.action_release("move_forward")
		580:
			_check_muzzle(Vector3(plane.global_position.x + 200.0, 10.0, plane.global_position.z), "右")
		600:
			_check_muzzle(Vector3(plane.global_position.x, 2.0, plane.global_position.z + 200.0), "後ろ")
			Input.action_press("descend")
		900:
			Input.action_release("descend")
			_report(plane.is_landed(), "Shift で下がって着陸できる（高さ %.1fm）" % plane.global_position.y)
			_report(input.try_exit(), "着陸していれば降りられる")
			set_meta("parked_pos", plane.global_position)
		960:
			var slid: float = plane.global_position.distance_to(Vector3(get_meta("parked_pos")))
			_report(slid < 2.0, "降りたあとの攻撃機は勝手に飛んで行かない（動いた距離 %.1fm）" % slid)
			# 7：空中に置き去りにしても、自分で降りてくる
			plane.global_position = Vector3(plane.global_position.x, 50.0, plane.global_position.z)
			plane.force_update_transform()
		1080:
			_report(plane.global_position.y < 35.0,
				"空に残された攻撃機は自分で降りてくる（高さ %.0fm）" % plane.global_position.y)
			_restore_mission()
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


## 機首が狙った方向を向き、弾がその銃口から出るか確かめる
func _check_muzzle(aim: Vector3, label: String) -> void:
	plane.control["aim"] = {"x": aim.x, "y": aim.y, "z": aim.z}
	plane._aim_gun()
	var muzzle: Node3D = plane.get_node("Visual/GunPivot/MuzzlePoint")
	var weapon: Weapon = plane.get_node("Weapon")
	var gap := weapon.global_position.distance_to(muzzle.global_position)
	_report(gap < 0.5, "%s を狙うと銃口が機首の先にある（ずれ %.2fm）" % [label, gap])
	weapon.cooldown = 0.0
	if not weapon.try_fire(aim, plane):
		_report(false, "%s：弾が出なかった" % label)
		return
	var newest: Bullet = null
	for child in field.get_children():
		if child is Bullet and (child as Bullet).shooter_rid == plane.get_rid():
			newest = child
	if newest == null:
		_report(false, "%s：弾が見つからない" % label)
		return
	var distance := newest.global_position.distance_to(muzzle.global_position)
	_report(distance < 15.0, "%s：弾が銃口の位置から出る（%.1fm）" % [label, distance])


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
