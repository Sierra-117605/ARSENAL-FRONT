extends SceneTree
## N4-2 の自動確認：機種を選ぶと性能・全高・脚の数が変わり、保存されるか調べる。
##
## 確かめること：
##  1. 機種データが 4 機種読み込める
##  2. 偵察は軽くて速い、突撃は硬くて遅い（機種ごとの倍率が効いている）
##  3. 機体に機種を反映すると、全高・見た目の大きさ・当たり判定が変わる
##  4. 四脚の機種にすると後脚が出る（二脚では隠れている）
##  5. カメラが大きい機体ほど引く
##  6. ガレージで機種を選ぶと表示が変わり、機種ごと保存される
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n4_2_machines.gd

var field: Node
var robot: Robot
var view: ThirdPersonView
var camera: Camera3D
var garage: Control
var frame := 0
var failed := false
var saved_before := ""
var cam_distance_small := 0.0


func _initialize() -> void:
	if FileAccess.file_exists(LoadoutStore.PATH):
		saved_before = FileAccess.get_file_as_string(LoadoutStore.PATH)
	_check_data()
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	robot = field.get_node("Robot")
	robot.use_saved_loadout = false
	view = field.get_node("CameraRig/ThirdPersonView")
	camera = field.get_node("CameraRig/Camera3D")


## 1・2：機種データと性能の傾向
func _check_data() -> void:
	var types := RobotParts.machine_types()
	_report(types.size() == 4, "機種が 4 つある (%d)" % types.size())
	var base := RobotParts.default_loadout()
	var scout := RobotParts.compute_stats(base, "scout_walker")
	var multi := RobotParts.compute_stats(base, "multirole_walker")
	var assault := RobotParts.compute_stats(base, "assault_walker")
	var arty := RobotParts.compute_stats(base, "artillery_walker")
	_report(int(scout["max_hp"]) < int(multi["max_hp"]) and float(scout["walk_speed"]) > float(multi["walk_speed"]),
		"偵察は柔らかく速い (耐久 %d / 速さ %.1f)" % [scout["max_hp"], scout["walk_speed"]])
	_report(int(assault["max_hp"]) > int(multi["max_hp"]) and float(assault["walk_speed"]) < float(multi["walk_speed"]),
		"突撃は硬く遅い (耐久 %d / 速さ %.1f)" % [assault["max_hp"], assault["walk_speed"]])
	_report(float(arty["aim_range"]) > float(multi["aim_range"]) and str(arty["legs"]) == "quad",
		"砲撃は遠くまで狙える四脚 (照準 %.0fm)" % arty["aim_range"])
	_report(float(scout["height"]) == 8.0 and float(assault["height"]) == 16.0,
		"機種ごとの全高 (偵察 %.0fm / 突撃 %.0fm)" % [scout["height"], assault["height"]])


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			# 3：偵察（8m）にする
			robot.apply_loadout(RobotParts.default_loadout(), "scout_walker")
			_report(is_equal_approx(robot.height, 8.0), "機体の全高が 8m になる (%.1f)" % robot.height)
			_report(is_equal_approx(robot.get_node("Visual").scale.x, 2.0),
				"見た目の大きさが 8m 相当になる (倍率 %.2f)" % robot.get_node("Visual").scale.x)
			var shape: CapsuleShape3D = robot.get_node("Collision").shape
			_report(is_equal_approx(shape.height, 8.0), "当たり判定の高さも 8m (%.1f)" % shape.height)
			_report(not robot.get_node("Visual/RearLegPivotL").visible, "二脚では後脚が隠れている")
		15:
			cam_distance_small = camera.global_position.distance_to(robot.global_position)
			# 4：砲撃（16m・四脚）にする
			robot.apply_loadout(RobotParts.default_loadout(), "artillery_walker")
		20:
			_report(is_equal_approx(robot.height, 16.0), "機体の全高が 16m になる (%.1f)" % robot.height)
			_report(robot.get_node("Visual/RearLegPivotL").visible and robot.get_node("Visual/RearLegPivotR").visible,
				"四脚では後脚が出る")
			# 5：カメラが引く
			var far := camera.global_position.distance_to(robot.global_position)
			_report(far > cam_distance_small,
				"大きい機体ほどカメラが引く (%.0fm → %.0fm)" % [cam_distance_small, far])
			# 6：ガレージ
			garage = load("res://scenes/garage.tscn").instantiate()
			root.add_child(garage)
		30:
			garage.machine_id = "multirole_walker"
			garage._refresh()
			var before: String = garage.stats_label.text
			garage._on_machine_selected(2)  # 3 番目＝突撃歩行機
			_report(garage.machine_id == "assault_walker", "ガレージで機種を選べる (%s)" % garage.machine_id)
			_report(garage.stats_label.text != before, "機種を変えると性能表示が変わる")
			_report(garage.machine_desc.text.contains("16"), "機種の欄に全高 16m が表示される (%s)" % garage.machine_desc.text)
			garage._on_sortie_test()
		35:
			var saved := LoadoutStore.load_saved()
			_report(str(saved.get("machine_type", "")) == "assault_walker",
				"選んだ機種が保存される (%s)" % saved.get("machine_type", ""))
			_restore_save()
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


## テストで書き換えた保存ファイルを元に戻す
func _restore_save() -> void:
	if saved_before != "":
		var f := FileAccess.open(LoadoutStore.PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(saved_before)
	elif FileAccess.file_exists(LoadoutStore.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LoadoutStore.PATH))


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
