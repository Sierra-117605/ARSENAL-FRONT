extends SceneTree
## N3-1 の自動確認：パーツを変えると機体の性能が変わるか調べる。
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n3_1_parts.gd

var failed := false


func _initialize() -> void:
	_check_catalog()
	_check_stats()
	_check_apply()
	print("RESULT: ", "FAIL" if failed else "PASS")
	quit()


func _check_catalog() -> void:
	var slots := RobotParts.slots()
	_report(slots.size() == 6, "スロットが 6 つある (%s)" % [slots])
	var ok := true
	for slot in slots:
		if RobotParts.parts_for(slot).size() < 2:
			ok = false
	_report(ok, "どのスロットにも選べるパーツが 2 つ以上ある")
	_report(RobotParts.slot_name("legs") == "脚", "スロットの日本語名が引ける")


func _check_stats() -> void:
	var base := RobotParts.compute_stats(RobotParts.default_loadout())
	_report(int(base["max_hp"]) > 0 and float(base["walk_speed"]) > 0.0,
		"標準構成の性能：耐久 %d / 速さ %.1f / 威力 %d / 連射 %.2f 秒" %
		[base["max_hp"], base["walk_speed"], base["damage"], base["fire_interval"]])

	# 重い脚にすると遅くなる
	var heavy := RobotParts.default_loadout()
	heavy["legs"] = "legs_heavy"
	var heavy_stats := RobotParts.compute_stats(heavy)
	_report(float(heavy_stats["walk_speed"]) < float(base["walk_speed"]),
		"重量脚部にすると遅くなる (%.1f → %.1f)" % [base["walk_speed"], heavy_stats["walk_speed"]])

	# 重装甲フレームにすると硬くなるが遅くなる
	var tanky := RobotParts.default_loadout()
	tanky["body"] = "body_heavy"
	var tanky_stats := RobotParts.compute_stats(tanky)
	_report(int(tanky_stats["max_hp"]) > int(base["max_hp"]) and float(tanky_stats["walk_speed"]) < float(base["walk_speed"]),
		"重装甲フレームは硬いが遅い (耐久 %d / 速さ %.1f)" % [tanky_stats["max_hp"], tanky_stats["walk_speed"]])

	# キャノンは 1 発が重く、連射は遅い
	var cannon := RobotParts.default_loadout()
	cannon["weapon"] = "weapon_cannon"
	var cannon_stats := RobotParts.compute_stats(cannon)
	_report(int(cannon_stats["damage"]) > int(base["damage"]) and float(cannon_stats["fire_interval"]) > float(base["fire_interval"]),
		"キャノンは威力が高く連射が遅い (威力 %d / 連射 %.2f 秒)" % [cannon_stats["damage"], cannon_stats["fire_interval"]])

	# 高出力ジェネレータは連射が速くなる
	var rapid := RobotParts.default_loadout()
	rapid["generator"] = "gen_rapid"
	var rapid_stats := RobotParts.compute_stats(rapid)
	_report(float(rapid_stats["fire_interval"]) < float(base["fire_interval"]),
		"高出力ジェネレータで連射が速くなる (%.2f → %.2f 秒)" % [base["fire_interval"], rapid_stats["fire_interval"]])

	# 知らないパーツ名は標準に直される
	var broken := {"legs": "存在しないパーツ", "weapon": "weapon_gatling"}
	var fixed := RobotParts.sanitize(broken)
	_report(fixed["legs"] == "legs_standard" and fixed["weapon"] == "weapon_gatling",
		"おかしな構成は標準のパーツで埋められる")


func _check_apply() -> void:
	var field: Node = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	var robot: Robot = field.get_node("Robot")
	var weapon: Weapon = robot.get_node("Weapon")
	var before_hp := robot.max_hp
	var before_speed := robot.walk_speed
	robot.apply_loadout({"body": "body_heavy", "legs": "legs_heavy", "weapon": "weapon_cannon"})
	_report(robot.max_hp > before_hp, "機体に反映：耐久 %d → %d" % [before_hp, robot.max_hp])
	_report(robot.walk_speed < before_speed, "機体に反映：速さ %.1f → %.1f" % [before_speed, robot.walk_speed])
	_report(weapon.damage == 90 and weapon.fire_interval > 1.0,
		"武器に反映：威力 %d / 連射 %.2f 秒" % [weapon.damage, weapon.fire_interval])
	var text := JSON.stringify(robot.to_dict())
	_report(text.contains("loadout"), "構成が保存データに入る")


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
