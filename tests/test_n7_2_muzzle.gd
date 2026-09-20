extends SceneTree
## 弾の出どころの確認（開発者の「正面以外に撃つと違う所から出る」指摘を受けて）。
##
## 確かめること：
##  1. ロボットの腕が、狙っている方向へ向く
##  2. 弾はその腕の先（銃口）から出る
##  3. 横や上を狙っても、弾の出どころが腕の先のままずれない
##  4. 戦車の砲身の先から弾が出る（砲塔を回しても追従する）
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n7_2_muzzle.gd

var field: Node
var robot: Robot
var tank: Tank
var rig: CameraRig
var frame := 0
var failed := false
var mission_before := ""


func _initialize() -> void:
	if FileAccess.file_exists(MissionData.CHOICE_PATH):
		mission_before = FileAccess.get_file_as_string(MissionData.CHOICE_PATH)
	MissionData.save_choice("sweep_plain", "normal")
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	robot = field.get_node("Robot")
	robot.use_saved_loadout = false
	tank = field.get_node("Tank")
	rig = field.get_node("CameraRig")
	# 他の機体の弾が混ざらないように取り除く
	field.get_node("SpareRobot").queue_free()
	for enemy in field.get_node("Enemies").get_children():
		enemy.queue_free()


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			_check_direction(Vector3(0, 6, -120), "正面")
		20:
			_check_direction(Vector3(120, 6, 0), "右")
		30:
			_check_direction(Vector3(-100, 6, 60), "左後ろ")
		40:
			_check_direction(Vector3(0, 90, -60), "上")
		50:
			# 4：戦車の砲身
			var turret: Node3D = tank.get_node("Visual/Turret")
			var muzzle: Node3D = tank.get_node("Visual/Turret/MuzzlePoint")
			tank.control["aim"] = {"x": 100.0, "y": 4.0, "z": tank.global_position.z}
		52:
			var muzzle: Node3D = tank.get_node("Visual/Turret/MuzzlePoint")
			var weapon: Weapon = tank.get_node("Weapon")
			var gap := weapon.global_position.distance_to(muzzle.global_position)
			_report(gap < 0.5, "戦車：銃口が砲身の先にある（ずれ %.2fm）" % gap)
			var bullet := _fire_and_find(tank, weapon)
			if bullet != null:
				var from_muzzle := bullet.global_position.distance_to(muzzle.global_position)
				_report(from_muzzle < 12.0, "戦車：弾が砲身の先から出る（%.1fm）" % from_muzzle)
			else:
				_report(false, "戦車：弾が出なかった")
			_restore()
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


## 指定の方向を狙って、腕の向きと弾の出どころを確かめる
func _check_direction(aim: Vector3, label: String) -> void:
	robot.control["aim"] = {"x": aim.x, "y": aim.y, "z": aim.z}
	robot._aim_arm()
	var pivot: Node3D = robot.get_node("Visual/ArmPivotR")
	var muzzle: Node3D = robot.get_node("Visual/ArmPivotR/MuzzlePoint")
	# 腕が狙う方向を向いているか（腕は -Z 方向を向く作り）
	var arm_dir: Vector3 = -pivot.global_basis.z
	var want_dir: Vector3 = (aim - pivot.global_position).normalized()
	_report(arm_dir.dot(want_dir) > 0.97, "%s を狙うと腕がその方向を向く" % label)
	# 銃口が腕の先に付いているか
	var weapon: Weapon = robot.get_node("Weapon")
	var gap := weapon.global_position.distance_to(muzzle.global_position)
	_report(gap < 0.5, "%s：銃口が腕の先にある（ずれ %.2fm）" % [label, gap])
	# 実際に撃って、弾が銃口の近くから出ているか
	var bullet := _fire_and_find(robot, weapon)
	if bullet == null:
		_report(false, "%s：弾が出なかった" % label)
		return
	var distance := bullet.global_position.distance_to(muzzle.global_position)
	_report(distance < 12.0, "%s：弾が銃口の位置から出る（%.1fm）" % [label, distance])


## 1 発撃って、その弾を返す
func _fire_and_find(shooter: Pilotable, weapon: Weapon) -> Bullet:
	weapon.cooldown = 0.0
	var aim := Pilotable.aim_point(shooter.control)
	if not weapon.try_fire(aim, shooter):
		return null
	var newest: Bullet = null
	for child in field.get_children():
		if child is Bullet and (child as Bullet).shooter_rid == shooter.get_rid():
			newest = child
	return newest


func _restore() -> void:
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
