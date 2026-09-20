extends SceneTree
## N2-2 の自動確認：敵ロボットが自機に近づき、撃ってきて、こちらの耐久が減るか調べる。
## プレイヤーは操作せず、その場に立っているだけ。
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n2_2_enemy.gd
## 画像も撮る場合（--headless を外す）：... -- --shot=<保存先.png>

const MAX_FRAMES := 1800  # 30 秒で打ち切り

var field: Node
var robot: Robot
var enemy: Robot
var mission_before := ""
var frame := 0
var failed := false
var shot_path := ""
var shot_taken := false
var start_distance := 0.0
var closest := 99999.0
var first_hit_frame := -1
var done := false


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
	robot = field.get_node("Robot")
	# テストでは保存した構成を読まない（シーンの標準設定のまま使う）
	robot.use_saved_loadout = false
	enemy = field.get_node("Enemies/Enemy1")
	# このテストは「敵 1 体がプレイヤーを追う」ことだけを見るので、味方機は遠ざける
	field.get_node("SpareRobot").position = Vector3(800, 0, 800)
	for other in ["Enemy2", "Enemy3"]:
		field.get_node("Enemies/" + other).queue_free()
	robot.damaged.connect(_on_player_damaged)


func _on_player_damaged(hp: int, _max: int) -> void:
	if first_hit_frame < 0:
		first_hit_frame = frame
		print("  （%.1f 秒後に初被弾。残り耐久 %d）" % [frame / 60.0, hp])


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame == 5:
		start_distance = _distance()
		_report(enemy != null and enemy.is_alive(), "敵ロボットがいる（耐久 %d）" % enemy.max_hp)
		_report(enemy.max_hp == 180, "敵の耐久はシーンで設定した 180 のまま（構成で上書きされない）")
		_report(start_distance > 100.0, "敵は遠くから始まる (%.0fm)" % start_distance)
		return false
	closest = minf(closest, _distance())
	if not shot_taken and shot_path != "" and _distance() < 80.0:
		shot_taken = true
		_save_shot()
	if done:
		return false
	# 自機の耐久が減った後、少し様子を見てから判定
	if (first_hit_frame > 0 and frame > first_hit_frame + 120) or frame > MAX_FRAMES:
		done = true
		_finish()
		return true
	return false


func _finish() -> void:
	_report(closest < start_distance - 50.0, "敵が近づいてくる (%.0fm → %.0fm)" % [start_distance, closest])
	_report(closest > 20.0, "近づきすぎず距離を保つ (最短 %.0fm)" % closest)
	_report(first_hit_frame > 0, "敵が撃ってきて自機に当たる")
	_report(robot.hp < robot.max_hp, "自機の耐久が減る (残り %d / %d)" % [robot.hp, robot.max_hp])
	_restore_mission()
	print("RESULT: ", "FAIL" if failed else "PASS")


func _distance() -> float:
	var d: Vector3 = enemy.global_position - robot.global_position
	return Vector2(d.x, d.z).length()


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
