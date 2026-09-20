extends SceneTree
## 鹵獲・技術ツリー・希少素材の確認（開発の中身を深めた部分。SPEC §0.13）。
##
## 確かめること：
##  1. 敵の部位（腕・脚・頭）を壊してから倒すと、その部位の設計図と希少素材が手に入る
##  2. 部位を壊さずに倒した場合は、部位に対応する鹵獲は起きない
##  3. 前提パーツが未開発だと、上位パーツは開発できない（理由が出る）
##  4. 前提を開発すると、上位パーツも開発できるようになる
##  5. 希少素材が足りないと開発できない
##  6. 開発すると資材と希少素材の両方が減る
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n4_9_capture.gd

var field: Node
var battle: Battle
var enemy: Robot
var frame := 0
var failed := false
var progress_before := ""


func _initialize() -> void:
	if FileAccess.file_exists(ProgressStore.PATH):
		progress_before = FileAccess.get_file_as_string(ProgressStore.PATH)
	ProgressStore.save_progress(ProgressStore.fresh())
	_check_tech_tree()
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	battle = field
	enemy = field.get_node("Enemies/Enemy1")
	(field.get_node("Robot") as Robot).use_saved_loadout = false


## 3〜6：技術ツリーと希少素材（戦闘とは別に確かめる）
func _check_tech_tree() -> void:
	var progress := ProgressStore.fresh()
	progress["blueprints"] = ["weapon_cannon"]
	progress["materials"] = 9999
	progress["rare"] = 9999
	var blocker := ProgressStore.develop_blocker(progress, "weapon_cannon")
	_report(blocker.begins_with("前提"), "前提パーツが無いと開発できない（%s）" % blocker)
	# 前提（ガトリング）を開発済みにする
	progress["unlocked"].append("weapon_gatling")
	_report(ProgressStore.develop_blocker(progress, "weapon_cannon") == "",
		"前提を開発すると、上位パーツも開発できる")
	# 希少素材を 0 にすると開発できない
	progress["rare"] = 0
	_report(ProgressStore.develop_blocker(progress, "weapon_cannon") == "希少素材が足りない",
		"希少素材が足りないと開発できない")
	progress["rare"] = 5
	var materials_before: int = progress["materials"]
	_report(ProgressStore.develop(progress, "weapon_cannon"), "条件がそろえば開発できる")
	_report(int(progress["materials"]) == materials_before - 260 and int(progress["rare"]) == 2,
		"資材と希少素材の両方が減る（資材 %d / 希少 %d）" % [progress["materials"], progress["rare"]])


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			# 1：敵 1 体の腕を壊してから倒す
			var shape_index := _shape_index_of(enemy, "HitArmR")
			var guard := 0
			while not enemy.is_part_broken("arm_right") and guard < 60:
				enemy.take_hit_at_shape(10, shape_index)
				guard += 1
			enemy.take_hit(100000)
		15:
			var captured_arm := false
			for part_id in battle.earned_blueprints:
				if str(RobotParts.find(part_id).get("slot", "")) == "arms":
					captured_arm = true
			_report(captured_arm, "壊した腕の設計図を鹵獲できた (%s)" % [battle.earned_blueprints])
			_report(battle.earned_rare > 0, "希少素材も手に入る (%d)" % battle.earned_rare)
			# 2：部位を壊さずに次の敵を倒す
			battle.earned_blueprints.clear()
			var other: Robot = field.get_node("Enemies/Enemy2")
			other.take_hit(100000)
		20:
			var only_arms := true
			for part_id in battle.earned_blueprints:
				if str(RobotParts.find(part_id).get("slot", "")) == "arms":
					only_arms = false
			_report(only_arms, "部位を壊さずに倒した分では腕は鹵獲されない")
			_restore()
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _shape_index_of(body: CollisionObject3D, node_name: String) -> int:
	for owner_id in body.get_shape_owners():
		var node := body.shape_owner_get_owner(owner_id)
		if node != null and node.name == node_name:
			return body.shape_owner_get_shape_index(owner_id, 0)
	return -1


func _restore() -> void:
	if progress_before != "":
		var f := FileAccess.open(ProgressStore.PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(progress_before)
	elif FileAccess.file_exists(ProgressStore.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ProgressStore.PATH))


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
