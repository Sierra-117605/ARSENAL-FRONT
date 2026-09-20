extends SceneTree
## ヘリコプター（プレイヤーが乗れる空の機体）の確認（SPEC §0.16）。
##
## 確かめること：
##  1. 戦場にヘリが駐機していて、兵士が歩いて行けば乗り込める
##  2. Space で上がり、キーを離すとその高さで止まる（ホバリング）
##  3. W で前へ、A/D で左右へ平行移動できる（ロボットと同じ感覚）
##  4. 機首が狙っている方向を向き、弾は機首の銃口の先から出る
##  5. 空中では降りられない。Shift で降りて着陸すれば降りられる
##  6. 出撃直後は AI が着陸したまま待つ（その間に乗り込める）
##  7. 降りたあと、待機時間が過ぎると AI が操縦して飛び上がる
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n7_4_helicopter.gd

var field: Node
var heli: Helicopter
var robot: Robot
var rig: CameraRig
var input: PlayerInput
var pilot: Occupant
var frame := 0
var failed := false
var mission_before := ""
var hover_height := 0.0


func _initialize() -> void:
	if FileAccess.file_exists(MissionData.CHOICE_PATH):
		mission_before = FileAccess.get_file_as_string(MissionData.CHOICE_PATH)
	MissionData.save_choice("sweep_plain", "normal")
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	heli = field.get_node("Helicopter")
	robot = field.get_node("Robot")
	robot.use_saved_loadout = false
	rig = field.get_node("CameraRig")
	input = field.get_node("PlayerInput")
	pilot = field.get_node("Pilot")
	# 飛び方の確認に集中するため、敵と味方の攻撃機は取り除く
	for enemy in field.get_node("Enemies").get_children():
		enemy.queue_free()
	var plane := field.get_node_or_null("Aircraft")
	if plane != null:
		plane.queue_free()


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		30:
			_report(heli != null, "戦場にヘリが置かれている")
			_report(heli.is_landed() and heli.global_position.y < 1.0,
				"出撃直後は AI が着陸したまま待っている（高さ %.1fm）" % heli.global_position.y)
			input.toggle_board()  # 自機のロボットから降りる
		40:
			var soldier: Node3D = pilot.body
			soldier.global_position = heli.global_position + Vector3(6, 0, 0)
			soldier.force_update_transform()
		50:
			_report(input.toggle_board(), "兵士がヘリに乗り込める")
			_report(pilot.get_vehicle() == heli, "操縦する機体がヘリになる")
			rig.yaw = 0.0  # 正面（-Z 方向）を向かせる
			Input.action_press("throttle_up")  # Space（上昇）
		140:
			_report(heli.global_position.y > 12.0, "Space で上がる（高さ %.0fm）" % heli.global_position.y)
			_report(not input.try_exit(), "空中では降りられない")
			Input.action_release("throttle_up")
		170:
			hover_height = heli.global_position.y
		230:
			var drift: float = absf(heli.global_position.y - hover_height)
			_report(drift < 1.5, "キーを離すとその高さで止まる（ずれ %.1fm）" % drift)
			set_meta("pos_before", heli.global_position)
			Input.action_press("move_forward")
		350:
			var moved: float = heli.global_position.distance_to(Vector3(get_meta("pos_before")))
			_report(moved > 30.0, "W で前へ飛ぶ（2 秒で %.0fm）" % moved)
			Input.action_release("move_forward")
			set_meta("pos_before", heli.global_position)
			Input.action_press("move_right")
		440:
			var before: Vector3 = get_meta("pos_before")
			var side: float = absf(heli.global_position.x - before.x)
			_report(side > 15.0, "D で右へ平行移動できる（%.0fm）" % side)
			Input.action_release("move_right")
			_check_muzzle()
			Input.action_press("throttle_down")  # Shift（下降）
		700:
			Input.action_release("throttle_down")
			_report(heli.is_landed(), "Shift で下がって着陸できる（高さ %.1fm）" % heli.global_position.y)
			_report(input.try_exit(), "着陸していれば降りられる")
			set_meta("height_at_exit", heli.global_position.y)
			# 待機時間を短くして、AI が飛び立つところまで確かめる
			heli.ai_wait_time = 0.5
			heli.ai_wait_left = 0.5
		900:
			_report(heli.global_position.y > float(get_meta("height_at_exit")) + 10.0,
				"待機時間が過ぎると AI が操縦して飛び上がる（高さ %.0fm）" % heli.global_position.y)
			_restore()
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


## 機首を向けた方向の銃口から弾が出るか確かめる
func _check_muzzle() -> void:
	var aim: Vector3 = heli.global_position + Vector3(120.0, 4.0, 0.0)
	heli.control["aim"] = {"x": aim.x, "y": aim.y, "z": aim.z}
	heli._aim_gun()
	var muzzle: Node3D = heli.get_node("Visual/GunPivot/MuzzlePoint")
	var weapon: Weapon = heli.get_node("Weapon")
	var gap := weapon.global_position.distance_to(muzzle.global_position)
	_report(gap < 0.5, "銃口が機首の先にある（ずれ %.2fm）" % gap)
	weapon.cooldown = 0.0
	if not weapon.try_fire(aim, heli):
		_report(false, "弾が出なかった")
		return
	var newest: Bullet = null
	for child in field.get_children():
		if child is Bullet and (child as Bullet).shooter_rid == heli.get_rid():
			newest = child
	if newest == null:
		_report(false, "弾が見つからない")
		return
	var distance := newest.global_position.distance_to(muzzle.global_position)
	_report(distance < 15.0, "弾が銃口の位置から出る（%.1fm）" % distance)


func _restore() -> void:
	for action in ["move_forward", "move_right", "throttle_up", "throttle_down"]:
		Input.action_release(action)
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
