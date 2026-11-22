extends SceneTree
## 見た目を確かめるための「決まった位置・角度のスクショ」を撮る道具（TODO N8-0）。
##
## 毎回まったく同じ条件で撮れるように、次のことをしている：
##  - 窓の大きさを 1920×1080 に固定する
##  - AI と戦闘の進行を止める（機体が動かないので絵が毎回同じになる）
##  - 機体・カメラを決め打ちの位置に置く
##  - 決まったフレーム数だけ待ってから保存する
##
## 使い方（--headless は付けない。付けると描画されない）：
##   Godot_v4.6.3-stable_win64_console.exe --path . --script res://tools/shot_set.gd -- --tag=mech --out=docs/visual_log/tmp
##   tag は mech（機体のアップ）／battle（戦闘の三人称）／boss（ボス戦）
##
## 保存先：<out>/<tag>.png

const SHOT_WIDTH := 1920
const SHOT_HEIGHT := 1080
const SETTLE_FRAMES := 40  # 機体が着地して落ち着くまで待つフレーム数

var tag := "mech"
var out_dir := "docs/visual_log/tmp"
var field: Node
var frame := 0
var mission_before := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			tag = arg.substr(6)
		elif arg.begins_with("--out="):
			out_dir = arg.substr(6)

	# 窓と描画の大きさを固定する（撮る絵の大きさを毎回同じにする）
	root.content_scale_size = Vector2i(SHOT_WIDTH, SHOT_HEIGHT)
	root.size = Vector2i(SHOT_WIDTH, SHOT_HEIGHT)
	DisplayServer.window_set_size(Vector2i(SHOT_WIDTH, SHOT_HEIGHT))

	# 任務を固定する（ボスの絵だけ別の任務）
	if FileAccess.file_exists(MissionData.CHOICE_PATH):
		mission_before = FileAccess.get_file_as_string(MissionData.CHOICE_PATH)
	if tag == "boss":
		MissionData.save_choice("railgun_fortress", "normal")
	else:
		MissionData.save_choice("sweep_plain", "normal")

	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	var robot: Robot = field.get_node("Robot")
	robot.use_saved_loadout = false  # 保存した構成に左右されないよう、シーンの標準で撮る


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		_freeze_everything()
		_place_subjects()
	if frame == SETTLE_FRAMES:
		_place_camera()
	if frame == SETTLE_FRAMES + 4:
		_save()
		_restore_mission()
		return true
	return false


## AI と戦闘の進行を止める（毎回同じ絵にするため）
func _freeze_everything() -> void:
	for node in root.find_children("*", "Node", true, false):
		if node is AIPilot or node is PlayerInput:
			node.set_physics_process(false)
			node.set_process(false)
	# 機体には「何も操作していない」入力を渡しておく
	for node in get_nodes_in_group_safe("pilotable"):
		(node as Pilotable).apply_control(Pilotable.empty_control())


## グループの中身を安全に取る
func get_nodes_in_group_safe(group: String) -> Array:
	return root.get_tree().get_nodes_in_group(group) if root.get_tree() != null else []


## 機体・兵士を決まった位置に置く
func _place_subjects() -> void:
	var robot: Robot = field.get_node("Robot")
	var soldier: Node3D = field.get_node_or_null("Soldier")
	var tank: Node3D = field.get_node_or_null("Tank")
	var heli: Node3D = field.get_node_or_null("Helicopter")
	var plane: Node3D = field.get_node_or_null("Aircraft")
	var spare: Node3D = field.get_node_or_null("SpareRobot")
	# 大きさ比べ用の目印（巨大な白文字）は見た目の判断の邪魔になるので隠す
	var refs: Node3D = field.get_node_or_null("ScaleRefs")
	if refs != null:
		refs.visible = false
	match tag:
		"mech":
			# 機体のアップ：自機だけを広い場所に置き、他は画面の外へどける
			robot.position = Vector3(0, 0, 0)
			robot.rotation.y = deg_to_rad(18.0)
			for other in [soldier, tank, heli, plane, spare]:
				if other != null:
					other.position = Vector3(2000, 0, 2000)
			for enemy in field.get_node("Enemies").get_children():
				(enemy as Node3D).position = Vector3(2000, 0, 2000)
			var targets: Node3D = field.get_node_or_null("Targets")
			if targets != null:
				targets.visible = false
		"battle":
			# 戦闘中の絵：自機の前方に敵を 3 体並べる
			robot.position = Vector3(0, 0, -40)
			robot.rotation.y = 0.0
			var spots := [Vector3(-26, 0, -118), Vector3(6, 0, -132), Vector3(34, 0, -110)]
			var i := 0
			for enemy in field.get_node("Enemies").get_children():
				(enemy as Node3D).position = spots[i % spots.size()]
				(enemy as Node3D).rotation.y = PI
				i += 1
			if spare != null:
				spare.position = Vector3(24, 0, -22)
			if tank != null:
				tank.position = Vector3(-24, 0, -14)
			if heli != null:
				heli.position = Vector3(44, 0, 10)
			if plane != null:
				plane.position = Vector3(2000, 0, 2000)
		"boss":
			# ボス戦の絵：要塞の正面に自機を置く
			robot.position = Vector3(0, 0, -150)
			robot.rotation.y = 0.0
			for other in [tank, heli, plane, spare]:
				if other != null:
					other.position = Vector3(2000, 0, 2000)
			for enemy in field.get_node("Enemies").get_children():
				(enemy as Node3D).position = Vector3(2000, 0, 2000)


## カメラを決まった位置・角度に置く
func _place_camera() -> void:
	var rig: CameraRig = field.get_node("CameraRig")
	var camera: Camera3D = field.get_node("CameraRig/Camera3D")
	# カメラ土台が毎フレーム動かすのを止めて、こちらで位置を決める
	rig.set_process(false)
	rig.set_physics_process(false)
	var from := Vector3.ZERO
	var look := Vector3.ZERO
	match tag:
		"mech":
			from = Vector3(16.0, 11.0, 22.0)
			look = Vector3(0.0, 7.0, 0.0)
		"battle":
			from = Vector3(7.5, 16.0, -14.0)
			look = Vector3(0.0, 7.0, -70.0)
		"boss":
			from = Vector3(13.0, 34.0, -168.0)
			look = Vector3(0.0, 12.0, -258.0)
	camera.global_position = from
	camera.look_at(look, Vector3.UP)
	camera.current = true


## 画像を保存する
func _save() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out_dir))
	var path := "res://" + out_dir + "/" + tag + ".png"
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(path))
	print("SHOT SAVED: ", ProjectSettings.globalize_path(path), " ", image.get_width(), "x", image.get_height())


func _restore_mission() -> void:
	if mission_before != "":
		var f := FileAccess.open(MissionData.CHOICE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(mission_before)
	elif FileAccess.file_exists(MissionData.CHOICE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MissionData.CHOICE_PATH))
