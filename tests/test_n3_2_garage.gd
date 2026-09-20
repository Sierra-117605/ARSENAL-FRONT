extends SceneTree
## N3-2・N3-4 の自動確認：ガレージ画面でパーツを選ぶと性能表示が変わり、出撃で構成が保存されるか調べる。
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n3_2_garage.gd
## 画像も撮る場合（--headless を外す）：... -- --shot=<保存先.png>

var garage: Control
var frame := 0
var failed := false
var shot_path := ""
var text_before := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_path = arg.substr(7)
	# 前回の保存を消しておく
	if FileAccess.file_exists(LoadoutStore.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LoadoutStore.PATH))
	garage = load("res://scenes/garage.tscn").instantiate()
	root.add_child(garage)


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			_report(garage.pickers.size() == 6, "6 つの部位の選択欄がある (%d)" % garage.pickers.size())
			text_before = garage.stats_label.text
			_report(text_before.contains("耐久"), "性能表示に日本語が出ている")
			# 武器をキャノンに、脚を重量脚部に変える
			_select(garage, "weapon", "weapon_cannon")
			_select(garage, "legs", "legs_heavy")
		15:
			_report(garage.stats_label.text != text_before, "パーツを変えると性能表示が変わる")
			_report(garage.stats_label.text.contains("90"), "キャノンの威力 90 が表示される")
			if shot_path != "":
				_save_shot()
		25:
			# 「出撃」を押した時と同じ処理（場面の切り替えはテストでは行わない）
			LoadoutStore.save(garage.loadout)
			var saved := LoadoutStore.load_saved()
			_report(saved.get("weapon", "") == "weapon_cannon" and saved.get("legs", "") == "legs_heavy",
				"選んだ構成が保存される (%s)" % [saved])
			# テストで書いた保存ファイルは消しておく（実際の遊びに影響させない）
			DirAccess.remove_absolute(ProjectSettings.globalize_path(LoadoutStore.PATH))
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _select(g: Control, slot: String, part_id: String) -> void:
	var parts := RobotParts.parts_for(slot)
	for i in parts.size():
		if parts[i].get("id", "") == part_id:
			g.pickers[slot].select(i)
			g._on_part_selected(i, slot)
			return
	_report(false, "パーツが見つからない: " + part_id)


func _save_shot() -> void:
	await process_frame
	root.get_texture().get_image().save_png(shot_path)
	print("画像を保存: ", shot_path)


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
