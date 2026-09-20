extends SceneTree
## ボス戦がクリアできるかの確認（開発者の「クリアできない／奥の目標が狙えない」指摘を受けて）。
##
## 確かめること：
##  1. 各段階の部位に、戦場の正面から射線が通る（物陰や土台に隠れていない）
##  2. 自動プレイ役が実際に撃って、すべての部位を破壊できる
##  3. 最後に勝利になる
##  4. レールガンの予兆で警告音、発射で発射音が鳴る
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n6_3_boss_reachable.gd

const APPROACH_DISTANCE := 90.0  # 部位から何メートル手前に立って撃つか

var field: Node
var battle: Node
var boss: BossFortress
var robot: Robot
var weapon: Weapon
var frame := 0
var failed := false
var mission_before := ""
var progress_before := ""
var target_part: BossPart = null
var shots := 0
var alarm_heard := false
var railgun_heard := false


func _initialize() -> void:
	mission_before = _read(MissionData.CHOICE_PATH)
	progress_before = _read(ProgressStore.PATH)
	MissionData.save_choice("railgun_fortress", "easy")
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	battle = field
	robot = field.get_node("Robot")
	robot.use_saved_loadout = false


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame > 3600:
		_report(false, "60 秒以内に要塞を壊し切れなかった（段階 %d／撃った弾 %d 発）" % [
			boss.stage if boss != null else 0, shots])
		_finish_test()
		return true
	if frame == 10:
		boss = battle.boss
		# 通常の敵は今回の確認に関係ないので取り除く
		for enemy in battle._enemies():
			(enemy as Node).queue_free()
		weapon = robot.get_node("Weapon")
		# 自機を頑丈にして、射線の確認に集中する
		robot.max_hp = 100000
		robot.hp = robot.max_hp
		# 決着前に必ず 1 回レールガンが鳴るよう、発射を早める
		boss.railgun_timer = boss.warning_time + 0.2
		return false
	if boss == null:
		return false
	_check_sounds()
	if battle.outcome != "":
		_report(battle.outcome == "win", "要塞を壊し切って勝利できる (%s)" % battle.outcome)
		_report(alarm_heard, "レールガンの予兆で警告音が鳴る")
		_report(railgun_heard, "レールガンの発射音が鳴る")
		_finish_test()
		return true

	# 今の段階で生きている部位を 1 つ選び、その正面に立って撃ち続ける
	if target_part == null or not is_instance_valid(target_part) or not target_part.is_alive():
		target_part = _next_part()
		if target_part == null:
			return false
		# 撃てる位置を探す（正面側を中心に、角度と距離を変えて試す）
		var found := _move_to_firing_spot(target_part)
		_report(found, "%s を撃てる位置がある（正面側から）" % target_part.part_label)
	weapon.cooldown = 0.0
	robot._aim_arm()
	if weapon.try_fire(target_part.global_position, robot):
		shots += 1
	return false


## 今の段階で生きている部位
func _next_part() -> BossPart:
	for part in boss.parts_of_stage(boss.stage):
		if part.is_alive():
			return part
	return null


## その部位を撃てる位置へ移動する。見つかれば true
func _move_to_firing_spot(part: BossPart) -> bool:
	for distance in [APPROACH_DISTANCE, 60.0, 130.0]:
		for step in 13:
			# 正面（戦場側）を中心に左右へ振る
			var angle := deg_to_rad(-60.0 + 10.0 * float(step))
			var offset: Vector3 = Vector3(sin(angle), 0.0, cos(angle)) * float(distance)
			var spot: Vector3 = part.global_position + offset
			spot.y = 0.0
			# 要塞の土台の上や中には立てない（プレイヤーも入れない場所なので試さない）
			if spot.z < boss.global_position.z + 70.0:
				continue
			robot.global_position = spot
			robot.force_update_transform()
			# 銃口の位置を今の姿勢に合わせてから射線を調べる（1 フレーム前の位置で判定しない）
			robot._aim_arm()
			if _has_line_of_fire(part):
				return true
	return false


## 銃口から部位まで射線が通っているか
func _has_line_of_fire(part: BossPart) -> bool:
	var from: Vector3 = weapon.global_position
	var query := PhysicsRayQueryParameters3D.create(from, part.global_position)
	query.exclude = [robot.get_rid()]
	var hit := robot.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == part


## 警告音・発射音が鳴ったか（音を鳴らす部品が増えたかで判定）
func _check_sounds() -> void:
	for child in root.get_children():
		if child is AudioStreamPlayer:
			if child.stream == Sounds.stream(Sounds.ALARM):
				alarm_heard = true
			elif child.stream == Sounds.stream(Sounds.RAILGUN):
				railgun_heard = true
		for sub in child.get_children():
			if sub is AudioStreamPlayer:
				if sub.stream == Sounds.stream(Sounds.ALARM):
					alarm_heard = true
				elif sub.stream == Sounds.stream(Sounds.RAILGUN):
					railgun_heard = true


func _finish_test() -> void:
	_restore()
	print("RESULT: ", "FAIL" if failed else "PASS")


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _restore() -> void:
	_write_or_delete(MissionData.CHOICE_PATH, mission_before)
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
