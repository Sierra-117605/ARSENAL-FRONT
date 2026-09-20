extends SceneTree
## 航空機（攻撃機）の確認。エースコンバット風の操作（SPEC §0.15）。
## 操作はキーボードだけ（マウスは使わない）。実際にキーを押したことにして飛ばす。
##
## 確かめること：
##  1. 戦場に攻撃機が駐機していて、兵士が歩いて行けば乗り込める。カメラが後方視点になる
##  2. Space（加速）で滑走して離陸する。空中では止まれず、最低速度を下回らない
##  3. S を押すと機首が上がり、高度が上がる
##  4. エキスパート操作：傾けただけでは曲がらず、傾けて機首を引くと旋回する
##  5. エキスパート操作：360 度ロールできる（背面飛行になる）
##  6. ノーヴィス操作：傾けるだけで曲がり、手を離すと自動で水平に戻る
##  7. 弾は機首の銃口の先から出る
##  8. 地面に突っ込むと墜落する（撃墜と同じ扱い）
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n7_3_aircraft.gd

var field: Node
var plane: Aircraft
var rig: CameraRig
var input: PlayerInput
var pilot: Occupant
var frame := 0
var failed := false
var mission_before := ""
var settings_before := ""
var yaw_before := 0.0
var crashed := false
## 飛行中にいちばん逆さまになった度合い（-1 = 完全な背面飛行）
var most_inverted := 1.0


func _initialize() -> void:
	# 任務・設定に左右されないよう、基本の任務とエキスパート操作に固定する
	if FileAccess.file_exists(MissionData.CHOICE_PATH):
		mission_before = FileAccess.get_file_as_string(MissionData.CHOICE_PATH)
	if FileAccess.file_exists(SettingsStore.PATH):
		settings_before = FileAccess.get_file_as_string(SettingsStore.PATH)
	MissionData.save_choice("sweep_plain", "normal")
	SettingsStore.save_flight_mode(SettingsStore.EXPERT)
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	plane = field.get_node("Aircraft")
	(field.get_node("Robot") as Robot).use_saved_loadout = false
	rig = field.get_node("CameraRig")
	input = field.get_node("PlayerInput")
	pilot = field.get_node("Pilot")
	plane.crashed.connect(func(): crashed = true)
	# 敵の弾で落とされないよう、今回は敵を取り除く（飛び方の確認に集中する）
	for enemy in field.get_node("Enemies").get_children():
		enemy.queue_free()


func _physics_process(_delta: float) -> bool:
	frame += 1
	# いちばん逆さまになった瞬間を覚えておく（1 = 水平、-1 = 背面）
	if plane != null and is_instance_valid(plane):
		most_inverted = minf(most_inverted, plane.global_transform.basis.y.y)
	match frame:
		30:
			_report(plane.is_landed(), "攻撃機は地上に駐機している（速度 %.0fm/秒）" % plane.speed)
			_report(plane.is_expert(), "設定どおりエキスパート操作になっている")
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
			# 3：S を押して機首を上げる
			_hold(["move_back"])
			set_meta("height_before", plane.global_position.y)
		290:
			_report(_nose_up() > 0.2, "S を押すと機首が上がる（%.0f 度）" % rad_to_deg(asin(_nose_up())))
			_report(plane.global_position.y > float(get_meta("height_before")) + 20.0,
				"機首を上げると高度が上がる（%.0fm → %.0fm）" % [
					get_meta("height_before"), plane.global_position.y])
			_hold([])  # キーを離す
		350:
			# 4：エキスパートは傾けただけでは曲がらない
			# 傾きだけを見たいので、いったん水平飛行の姿勢に整える
			plane.rotation = Vector3(0.0, plane.rotation.y, 0.0)
			plane.global_position.y = 200.0
			plane.force_update_transform()
			yaw_before = _heading()
			_hold(["move_right"])  # D で右に傾ける
		380:
			# キーは一気に舵がいっぱいまで入るので、短い時間で確かめる
			_report(_bank() > 0.2, "D を押すと機体が右に傾く（%.0f 度）" % rad_to_deg(asin(_bank())))
			_report(_turned_from(yaw_before) < deg_to_rad(20.0),
				"エキスパートは傾けただけでは曲がらない（%.0f 度）" % rad_to_deg(_turned_from(yaw_before)))
			# 傾けたまま機首を引く＝旋回（D + S）
			yaw_before = _heading()
			_hold(["move_right", "move_back"])
		440:
			_report(_turned_from(yaw_before) > deg_to_rad(25.0),
				"傾けて機首を引くと旋回する（%.0f 度まわった）" % rad_to_deg(_turned_from(yaw_before)))
			# 5：360 度ロール（D を押し続ける）
			_hold(["move_right"])
		560:
			_report(most_inverted < -0.5,
				"エキスパートなら 360 度ロールできる（いちばん逆さまで %.2f）" % most_inverted)
			_check_muzzle()
			# キーを離して、ノーヴィス操作に切り替える
			_hold([])
			plane.flight_mode = SettingsStore.NOVICE
			plane.rotation = Vector3(0.0, plane.rotation.y, 0.0)
			plane.global_position.y = 220.0
			plane.force_update_transform()
		620:
			# 6：ノーヴィスは傾けるだけで曲がる
			yaw_before = _heading()
			_hold(["move_right"])
		700:
			_report(_bank() > 0.2 and _bank() < 0.99,
				"ノーヴィスの傾きは 80 度までに収まる（%.0f 度）" % rad_to_deg(asin(_bank())))
			_report(_turned_from(yaw_before) > deg_to_rad(20.0),
				"ノーヴィスは傾けるだけで曲がる（%.0f 度まわった）" % rad_to_deg(_turned_from(yaw_before)))
			_hold([])  # 手を離す
		880:
			_report(_bank() < 0.1, "ノーヴィスは手を離すと自動で水平に戻る（%.0f 度）" % rad_to_deg(asin(_bank())))
			# 2：減速しても止まれない
			Input.action_press("throttle_down")
		1020:
			Input.action_release("throttle_down")
			_report(absf(plane.speed - plane.min_speed) < 1.0,
				"Shift で減速しても最低速度で飛び続ける (%.0fm/秒)" % plane.speed)
			# 8：地面へ突っ込ませる
			plane.global_position = Vector3(plane.global_position.x, 40.0, plane.global_position.z)
			plane.rotation.x = deg_to_rad(-60.0)
			plane.force_update_transform()
		1080:
			_report(crashed, "地面に突っ込むと墜落する")
			_report(not plane.is_alive(), "墜落した機体は撃墜と同じ扱いになる（耐久 %d）" % plane.hp)
			_restore()
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


## 機首がどれだけ上を向いているか（1 = 真上）
func _nose_up() -> float:
	return (-plane.global_transform.basis.z).y


## 右にどれだけ傾いているか（1 = 右の翼が真下）
func _bank() -> float:
	return -plane.global_transform.basis.x.y


## 今どちらを向いているか（水平の角度）
func _heading() -> float:
	var forward: Vector3 = -plane.global_transform.basis.z
	return atan2(-forward.x, -forward.z)


## 記録した向きからどれだけ回ったか
func _turned_from(before: float) -> float:
	return absf(wrapf(_heading() - before, -PI, PI))


## 押しているキーを切り替える（複数同時に押せる）
func _hold(actions: Array) -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		if actions.has(action):
			Input.action_press(action)
		else:
			Input.action_release(action)


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


## 任務と設定を元に戻す
func _restore() -> void:
	_hold([])
	_write_or_delete(MissionData.CHOICE_PATH, mission_before)
	_write_or_delete(SettingsStore.PATH, settings_before)


func _write_or_delete(path: String, content: String) -> void:
	if content != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(content)
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
