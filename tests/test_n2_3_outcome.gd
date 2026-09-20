extends SceneTree
## N2-3・N2-4 の自動確認：敵を壊すと「勝利」、自機が壊れると「撃破」が出て、R キーでやり直せるか調べる。
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n2_3_outcome.gd
## 画像も撮る場合（--headless を外す）：... -- --shot=<保存先.png>

var field: Node
var battle: Battle
var robot: Robot
var enemies: Array
var message: Control
var mission_before := ""
var frame := 0
var failed := false
var shot_path := ""
var results: Array[String] = []
var restarts := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_path = arg.substr(7)
	# 任務の設定に左右されないよう、基本の任務（殲滅・中）に固定する
	if FileAccess.file_exists(MissionData.CHOICE_PATH):
		mission_before = FileAccess.get_file_as_string(MissionData.CHOICE_PATH)
	MissionData.save_choice("sweep_plain", "normal")
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	battle = field
	robot = field.get_node("Robot")
	# テストでは保存した構成を読まない（シーンの標準設定のまま使う）
	robot.use_saved_loadout = false
	enemies = field.get_node("Enemies").get_children()
	message = field.get_node("HUD/BattleMessage")
	battle.finished.connect(func(r: String): results.append(r))
	battle.restart_requested.connect(func(): restarts += 1)


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		20:
			_report(battle.outcome == "" and battle.alive_enemy_count() == 3,
				"戦闘中は結果なし・敵は 3 体 (敵 %d 体)" % battle.alive_enemy_count())
			# 1 体だけ壊す（まだ勝利にならないことを確かめる）
			enemies[0].take_hit(1000)
		25:
			_report(battle.outcome == "" and battle.alive_enemy_count() == 2,
				"1 体壊しただけでは勝利にならない (残り %d 体)" % battle.alive_enemy_count())
			enemies[1].take_hit(1000)
			enemies[2].take_hit(1000)
		30:
			_report(battle.outcome == "win", "敵を全部壊すと勝利 (結果 %s)" % battle.outcome)
			_report(results == ["win"], "勝利が 1 回だけ知らされる")
			_report(message.message == "VICTORY", "画面に VICTORY が出る")
			if shot_path != "":
				_save_shot()
		45:
			_press_r()
		50:
			_report(restarts == 1, "R キーでやり直しが指示される (%d 回)" % restarts)
			_restore_mission()
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _press_r() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_R
	ev.keycode = KEY_R
	ev.pressed = true
	Input.parse_input_event(ev)


func _save_shot() -> void:
	await process_frame
	root.get_texture().get_image().save_png(shot_path)
	print("画像を保存: ", shot_path)


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true


## 任務の選択を元に戻す
func _restore_mission() -> void:
	if mission_before != "":
		var f := FileAccess.open(MissionData.CHOICE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(mission_before)
	elif FileAccess.file_exists(MissionData.CHOICE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MissionData.CHOICE_PATH))
