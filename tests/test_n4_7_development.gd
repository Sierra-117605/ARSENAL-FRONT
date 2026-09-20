extends SceneTree
## 開発ツリーの確認（差別化の柱・案3＝設計図から開発。SPEC §0.13）。
##
## 確かめること：
##  1. 最初は各部位の標準パーツだけが使える（キャノンなどは未開発）
##  2. 敵を倒すと資材が手に入り、勝つと設計図が 1 つ手に入る
##  3. 戦果は保存され、次の起動でも残る
##  4. 資材が足りなければ開発できない／足りれば開発できて資材が減る（前提と希少素材はそろえた状態で確認）
##  5. 開発したパーツはガレージで選べるようになる
##  6. 未開発のパーツは選択欄で選べない（グレーアウト）
##  7. 未開発のパーツが構成に残っていても、起動時に標準品へ戻す（不正防止）
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n4_7_development.gd

var field: Node
var battle: Battle
var garage: Control
var frame := 0
var failed := false
var progress_before := ""
var loadout_before := ""


func _initialize() -> void:
	# 開発者の保存データを覚えておく（最後に戻す）
	if FileAccess.file_exists(ProgressStore.PATH):
		progress_before = FileAccess.get_file_as_string(ProgressStore.PATH)
	if FileAccess.file_exists(LoadoutStore.PATH):
		loadout_before = FileAccess.get_file_as_string(LoadoutStore.PATH)
	ProgressStore.save_progress(ProgressStore.fresh())

	_check_initial_state()
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	battle = field
	(field.get_node("Robot") as Robot).use_saved_loadout = false


## 1：最初に使えるパーツ
func _check_initial_state() -> void:
	var progress := ProgressStore.load_progress()
	_report(ProgressStore.is_unlocked(progress, "weapon_rifle"), "標準ライフルは最初から使える")
	_report(not ProgressStore.is_unlocked(progress, "weapon_cannon"), "キャノンは最初は未開発")
	_report(int(progress.get("materials", 0)) == 0, "最初の資材は 0")


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			# 2：敵を全部倒して勝つ
			for enemy in field.get_node("Enemies").get_children():
				(enemy as Pilotable).take_hit(100000)
		15:
			_report(battle.outcome == "win", "勝利した")
			_report(battle.earned_materials > 0, "資材が手に入る (%d)" % battle.earned_materials)
			_report(battle.earned_blueprints.size() == 1,
				"設計図が 1 つ手に入る (%s)" % [battle.earned_blueprints])
			# 3：保存されているか
			var progress := ProgressStore.load_progress()
			_report(int(progress.get("materials", 0)) == battle.earned_materials,
				"戦果が保存されている（資材 %d）" % progress["materials"])
			_report((progress.get("blueprints", []) as Array).size() == 1, "設計図も保存されている")
		20:
			# 4：開発（まずは資材が足りない状態で試す）
			var progress := ProgressStore.load_progress()
			var part_id: String = progress["blueprints"][0]
			var part := RobotParts.find(part_id)
			var cost := int(part.get("develop_cost", 100))
			# 前提パーツと希少素材はそろっている状態にして、資材の判定だけを見る
			for required in part.get("requires", []):
				if not (progress["unlocked"] as Array).has(str(required)):
					progress["unlocked"].append(str(required))
			progress["rare"] = int(part.get("rare_cost", 0)) + 5
			progress["materials"] = cost - 1
			_report(not ProgressStore.develop(progress, part_id),
				"資材が足りないと開発できない (%d / %d)" % [progress["materials"], cost])
			progress["materials"] = cost + 50
			_report(ProgressStore.develop(progress, part_id), "資材が足りれば開発できる")
			_report(int(progress["materials"]) == 50, "開発すると資材が減る (残り %d)" % progress["materials"])
			_report(ProgressStore.is_unlocked(progress, part_id), "開発したパーツが使えるようになる")
			_report(not (progress.get("blueprints", []) as Array).has(part_id), "設計図は使われて無くなる")
			ProgressStore.save_progress(progress)
		25:
			# 5・6：ガレージでの見え方
			garage = load("res://scenes/garage.tscn").instantiate()
			root.add_child(garage)
		30:
			var progress := ProgressStore.load_progress()
			var developed: String = progress["unlocked"].back()
			var slot := str(RobotParts.find(developed).get("slot", ""))
			var picker: OptionButton = garage.pickers[slot]
			var developed_ok := false
			for i in picker.item_count:
				var parts := RobotParts.parts_for(slot)
				if str(parts[i].get("id", "")) == developed:
					developed_ok = not picker.is_item_disabled(i)
			_report(developed_ok, "開発したパーツはガレージで選べる (%s)" % developed)
			# 未開発のパーツは、どの部位でも選べない状態になっているか
			var locked_total := 0
			var locked_disabled := 0
			for other_slot in RobotParts.slots():
				var other_picker: OptionButton = garage.pickers[other_slot]
				var other_parts := RobotParts.parts_for(other_slot)
				for i in other_parts.size():
					if not ProgressStore.is_unlocked(progress, str(other_parts[i].get("id", ""))):
						locked_total += 1
						if other_picker.is_item_disabled(i):
							locked_disabled += 1
			_report(locked_total > 0 and locked_disabled == locked_total,
				"未開発のパーツは選べない（%d 件すべてグレーアウト）" % locked_total)
			# 7：未開発パーツが構成に残っていた場合
			LoadoutStore.save({"weapon": "weapon_gatling", "machine_type": "multirole_walker"})
		35:
			var garage2: Control = load("res://scenes/garage.tscn").instantiate()
			root.add_child(garage2)
		40:
			var loaded_weapon := str((root.get_children().back() as Control).loadout.get("weapon", ""))
			var progress := ProgressStore.load_progress()
			var ok := ProgressStore.is_unlocked(progress, loaded_weapon)
			_report(ok, "未開発のパーツは起動時に標準品へ戻る (%s)" % loaded_weapon)
			_restore()
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


## 開発者の保存データを元に戻す
func _restore() -> void:
	_write_or_delete(ProgressStore.PATH, progress_before)
	_write_or_delete(LoadoutStore.PATH, loadout_before)


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
