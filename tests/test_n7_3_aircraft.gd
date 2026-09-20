extends SceneTree
## 攻撃機（AI 専用）の確認（SPEC §0.15）。
## 2026-09-21 決定：攻撃機はプレイヤーが乗らず、AI が飛ばして空から支援する。
##
## 確かめること：
##  1. 戦場に攻撃機があり、AI 乗員が座っている
##  2. AI が自分で加速して離陸する
##  3. 決まった高さを保って飛び続ける（墜落しない・地面すれすれにならない）
##  4. 敵の方へ向きを変えて飛ぶ
##  5. 攻撃機の射撃が敵に当たる
##  6. プレイヤーは攻撃機に乗り込めない（近づいて F を押しても乗れない）
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n7_3_aircraft.gd

var field: Node
var plane: Aircraft
var input: PlayerInput
var pilot: Occupant
var enemy: Robot
var frame := 0
var failed := false
var mission_before := ""
var lowest := 9999.0
var took_off_frame := -1
var enemy_hp_start := 0
var enemy_was_hit := false


func _initialize() -> void:
	if FileAccess.file_exists(MissionData.CHOICE_PATH):
		mission_before = FileAccess.get_file_as_string(MissionData.CHOICE_PATH)
	MissionData.save_choice("sweep_plain", "normal")
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	plane = field.get_node("Aircraft")
	(field.get_node("Robot") as Robot).use_saved_loadout = false
	input = field.get_node("PlayerInput")
	pilot = field.get_node("Pilot")
	enemy = field.get_node("Enemies/Enemy1")
	enemy.damaged.connect(func(_hp: int, _max: int): enemy_was_hit = true)
	# 攻撃機の働きだけを見たいので、他の敵は取り除く
	for other in ["Enemy2", "Enemy3"]:
		field.get_node("Enemies/" + other).queue_free()


func _physics_process(_delta: float) -> bool:
	frame += 1
	if is_instance_valid(plane) and not plane.is_landed():
		if took_off_frame < 0:
			took_off_frame = frame
		# 離陸から 3 秒経ってからの高度を見る（上がりきるまでは数えない）
		elif frame > took_off_frame + 180:
			lowest = minf(lowest, plane.global_position.y)
	match frame:
		10:
			var seat: Seat = plane.get_node("DriverSeat")
			_report(seat.occupant is AIPilot, "攻撃機には AI 乗員が座っている")
			_report(not seat.player_can_board, "攻撃機はプレイヤーが乗り込めない設定になっている")
			enemy_hp_start = enemy.hp
		200:
			_report(took_off_frame > 0, "AI が自分で離陸する（%.1f 秒後・高度 %.0fm）" % [
				took_off_frame / 60.0, plane.global_position.y])
			_report(plane.is_alive(), "離陸してすぐ墜落しない")
			# 6：プレイヤーが降りて攻撃機に近づいても乗れない
			input.toggle_board()
		215:
			var soldier: Node3D = pilot.body
			soldier.global_position = Vector3(plane.global_position.x + 5.0, 0.0, plane.global_position.z)
			soldier.force_update_transform()
		225:
			_report(not input.toggle_board(), "兵士が近づいても攻撃機には乗り込めない")
			_report(pilot.get_vehicle() == null, "乗り込めなかったので徒歩のまま")
		1200:
			_report(plane.is_alive(), "20 秒飛び続けても墜落しない（高度 %.0fm）" % plane.global_position.y)
			_report(lowest > 20.0, "地面すれすれまで下がらない（いちばん低くて %.0fm）" % lowest)
			_report(plane.global_position.y < 300.0, "高く上がりすぎない（%.0fm）" % plane.global_position.y)
			if is_instance_valid(enemy) and enemy.is_alive():
				var to_enemy: Vector3 = enemy.global_position - plane.global_position
				var forward: Vector3 = -plane.global_transform.basis.z
				var angle := forward.angle_to(to_enemy.normalized())
				_report(angle < deg_to_rad(110.0), "敵の方へ向きを変えて飛ぶ（ずれ %.0f 度）" % rad_to_deg(angle))
				_report(enemy.hp < enemy_hp_start,
					"攻撃機の射撃が敵に当たる（敵の耐久 %d → %d）" % [enemy_hp_start, enemy.hp])
			else:
				_report(enemy_was_hit, "攻撃機の射撃が敵に当たる（敵を倒した）")
			_restore()
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _restore() -> void:
	if mission_before != "":
		var f := FileAccess.open(MissionData.CHOICE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(mission_before)
	elif FileAccess.file_exists(MissionData.CHOICE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MissionData.CHOICE_PATH))


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
