extends SceneTree
## N2-1 の自動確認：自機に耐久があり、ダメージで減り、画面に耐久バーが出るか調べる。
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n2_1_hp.gd
## 画像も撮る場合（--headless を外す）：... -- --shot=<保存先.png>

var field: Node
var robot: Robot
var bar: Control
var frame := 0
var failed := false
var shot_path := ""
var damaged_signal := 0
var destroyed_signal := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_path = arg.substr(7)
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	robot = field.get_node("Robot")
	# テストでは保存した構成を読まない（シーンの標準設定のまま使う）
	robot.use_saved_loadout = false
	bar = field.get_node("HUD/HealthBar")
	robot.damaged.connect(func(_hp, _max): damaged_signal += 1)
	robot.destroyed.connect(func(): destroyed_signal += 1)


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		30:
			_report(robot.hp == robot.max_hp and robot.hp > 0, "起動時の耐久は満タン (%d / %d)" % [robot.hp, robot.max_hp])
			_report(bar != null and bar.target == robot, "耐久バーが自機を見ている")
			if shot_path != "":
				_save_shot()
		40:
			robot.take_hit(30)
			_report(robot.hp == robot.max_hp - 30, "ダメージで耐久が減る (残り %d)" % robot.hp)
			_report(damaged_signal == 1, "耐久が減ったことを知らせる")
			_report(robot.is_alive(), "まだ動ける")
		50:
			robot.take_hit(1000)
			_report(robot.hp == 0, "耐久は 0 より下がらない (%d)" % robot.hp)
			_report(destroyed_signal == 1, "撃破を知らせる")
			_report(not robot.is_alive(), "撃破後は動けない扱い")
			var text := JSON.stringify(robot.to_dict())
			_report(text.contains("\"hp\""), "耐久が保存データに入る: " + text)
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _save_shot() -> void:
	await process_frame
	root.get_texture().get_image().save_png(shot_path)
	print("画像を保存: ", shot_path)


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
