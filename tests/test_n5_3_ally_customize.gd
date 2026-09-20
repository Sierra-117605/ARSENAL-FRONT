extends SceneTree
## 味方機のカスタマイズの確認（開発者の要望）。
##
## 確かめること：
##  1. ガレージで「自機／味方機」を切り替えられる
##  2. 味方機の機種とパーツを、自機とは別に選べる
##  3. 出撃すると、自機と味方機の構成が別々に保存される
##  4. 戦場では、味方機が保存した構成（機種・耐久・武器）で出てくる
##  5. 自機の構成は味方機の変更に影響されない
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n5_3_ally_customize.gd

var garage: Control
var field: Node
var frame := 0
var stage := 0
var failed := false
var loadout_before := ""
var ally_before := ""
var progress_before := ""


func _initialize() -> void:
	loadout_before = _read(LoadoutStore.PATH)
	ally_before = _read(LoadoutStore.ALLY_PATH)
	progress_before = _read(ProgressStore.PATH)
	# 確認に使うパーツを開発済みにしておく
	var progress := ProgressStore.fresh()
	for part_id in ["weapon_cannon", "weapon_gatling", "legs_heavy", "body_heavy"]:
		progress["unlocked"].append(part_id)
	ProgressStore.save_progress(progress)
	garage = load("res://scenes/garage.tscn").instantiate()
	root.add_child(garage)


func _physics_process(_delta: float) -> bool:
	frame += 1
	match stage:
		0:
			if frame == 10:
				_report(garage.editing == "player", "最初は自機を編集している")
				# 自機：突撃歩行機＋キャノン
				garage._on_machine_selected(2)
				_select_part("weapon", "weapon_cannon")
				_report(str(garage.loadout.get("weapon", "")) == "weapon_cannon",
					"自機に武器を設定できる (%s)" % garage.loadout.get("weapon", ""))
				# 味方機に切り替え
				garage._on_target_selected("ally")
				_report(garage.editing == "ally", "味方機の編集に切り替えられる")
				_report(garage.current_loadout() == garage.ally_loadout, "編集の対象が味方機の構成になる")
				# 味方機：偵察歩行機＋ガトリング
				garage._on_machine_selected(0)
				_select_part("weapon", "weapon_gatling")
				_report(str(garage.ally_loadout.get("weapon", "")) == "weapon_gatling",
					"味方機に別の武器を設定できる (%s)" % garage.ally_loadout.get("weapon", ""))
				_report(str(garage.loadout.get("weapon", "")) == "weapon_cannon",
					"自機の構成は変わっていない (%s)" % garage.loadout.get("weapon", ""))
				garage._on_sortie_test()
			elif frame == 15:
				var saved := LoadoutStore.load_saved()
				var ally := LoadoutStore.load_ally()
				_report(str(saved.get("machine_type", "")) == "assault_walker"
						and str(saved.get("weapon", "")) == "weapon_cannon",
					"自機の構成が保存される (%s / %s)" % [saved.get("machine_type", ""), saved.get("weapon", "")])
				_report(str(ally.get("machine_type", "")) == "scout_walker"
						and str(ally.get("weapon", "")) == "weapon_gatling",
					"味方機の構成が別に保存される (%s / %s)" % [ally.get("machine_type", ""), ally.get("weapon", "")])
				stage = 1
				frame = 0
				garage.queue_free()
				field = load("res://scenes/field_3d.tscn").instantiate()
				root.add_child(field)
		1:
			if frame == 20:
				var ally: Robot = field.get_node("SpareRobot")
				var player: Robot = field.get_node("Robot")
				_report(ally.machine_type == "scout_walker",
					"戦場の味方機が選んだ機種で出てくる (%s／全高 %.0fm)" % [ally.machine_type, ally.height])
				_report(str(ally.loadout.get("weapon", "")) == "weapon_gatling",
					"味方機が選んだ武器を持っている (%s)" % ally.loadout.get("weapon", ""))
				_report(ally.get_node("Weapon").damage == 4,
					"味方機の武器の威力が反映される (%d)" % ally.get_node("Weapon").damage)
				_report(player.machine_type == "assault_walker",
					"自機は自分の機種で出てくる (%s／全高 %.0fm)" % [player.machine_type, player.height])
				_restore()
				print("RESULT: ", "FAIL" if failed else "PASS")
				return true
	return false


## ガレージで指定のパーツを選ぶ
func _select_part(slot: String, part_id: String) -> void:
	var parts := RobotParts.parts_for(slot)
	for i in parts.size():
		if str(parts[i].get("id", "")) == part_id:
			garage._on_part_selected(i, slot)
			return


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _restore() -> void:
	_write_or_delete(LoadoutStore.PATH, loadout_before)
	_write_or_delete(LoadoutStore.ALLY_PATH, ally_before)
	_write_or_delete(ProgressStore.PATH, progress_before)


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
