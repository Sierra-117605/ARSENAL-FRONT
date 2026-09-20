extends SceneTree
## 自動プレイ検証：プレイヤー役を簡単な操作ルールで動かし、戦闘の結果を数値で出す。
##
## 測るもの：勝敗／決着までの秒数／終了時の自機の残り耐久／撃った弾と命中数（命中率）／
##           倒した敵の数／味方機が生き残ったか
##
## 使い方（構成や機種を変えて比べられる）：
##   Godot_console.exe --headless --path . --script res://tests/tool_playtest.gd -- \
##       machine_type=multirole_walker weapon=weapon_cannon legs=legs_standard
##   さらに --shot=<保存先.png> を付けると（--headless なしで）戦闘中の画面も保存する
##
## プレイヤー役の操作ルール：いちばん近い敵を向いて、遠ければ近づき、近すぎれば下がり、
## 横に動きながら、射線が通っていれば撃つ（人間の平均的な動きの代わり）

const MAX_SECONDS := 120.0
const KEEP_DISTANCE := 70.0
const STRAFE_INTERVAL := 1.5

var field: Node
var battle: Battle
var pilot: Occupant
var rig: CameraRig
var loadout := {}
var shot_path := ""
var shot_taken := false
var frame := 0
var strafe_dir := 1.0
var strafe_timer := 0.0
var shots_fired := 0
var hits := 0
var start_hp := 0
var saved_before := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_path = arg.substr(7)
		elif arg.contains("="):
			var kv := arg.split("=")
			loadout[kv[0]] = kv[1]
	if FileAccess.file_exists(LoadoutStore.PATH):
		saved_before = FileAccess.get_file_as_string(LoadoutStore.PATH)
	if not loadout.is_empty():
		LoadoutStore.save(loadout)
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	battle = field
	pilot = field.get_node("Pilot")
	rig = field.get_node("CameraRig")
	# 命中数は「自機が撃った弾」だけを数える（味方 AI の命中と混ざらないように）
	Bullet.hit_counts.clear()


func _physics_process(delta: float) -> bool:
	frame += 1
	var vehicle := pilot.get_vehicle()
	if frame == 5 and vehicle != null:
		start_hp = vehicle.max_hp
	if battle.outcome != "" or frame > MAX_SECONDS * 60.0:
		_finish(vehicle)
		return true
	if vehicle == null or not vehicle.is_alive():
		return false

	var prey := _nearest_enemy(vehicle)
	if prey == null:
		return false

	# 敵の方を向く（カメラ＝機体の向き）
	var to_target: Vector3 = prey.global_position - vehicle.global_position
	rig.yaw = atan2(-to_target.x, -to_target.z)
	rig.pitch = clampf(atan2(to_target.y + 6.0, Vector2(to_target.x, to_target.z).length()),
		deg_to_rad(rig.pitch_min_deg), deg_to_rad(rig.pitch_max_deg))

	# 距離を取りつつ横に動く
	var distance := Vector2(to_target.x, to_target.z).length()
	Input.action_release("move_forward")
	Input.action_release("move_back")
	if distance > KEEP_DISTANCE + 10.0:
		Input.action_press("move_forward")
	elif distance < KEEP_DISTANCE - 10.0:
		Input.action_press("move_back")
	strafe_timer -= delta
	if strafe_timer <= 0.0:
		strafe_timer = STRAFE_INTERVAL
		strafe_dir = -strafe_dir
		Input.action_release("move_left")
		Input.action_release("move_right")
		Input.action_press("move_right" if strafe_dir > 0.0 else "move_left")

	# 射線が通っていれば撃つ。ふさがれていたら回り込む
	var weapon: Weapon = vehicle.get_node_or_null("Weapon")
	var aim: Vector3 = prey.global_position + Vector3(0, 6, 0)
	var clear := _has_line_of_fire(vehicle, prey, aim)
	if not clear:
		Input.action_release("move_back")
		Input.action_press("move_forward")
	elif weapon != null and distance < 200.0:
		if weapon.try_fire(aim, vehicle):
			shots_fired += 1
	if shot_path != "" and not shot_taken and frame > 240:
		shot_taken = true
		_save_shot()
	return false


## 銃口から狙う点まで、物陰にさえぎられていないか
func _has_line_of_fire(vehicle: Pilotable, prey: Node3D, aim: Vector3) -> bool:
	var muzzle: Node3D = vehicle.get_node_or_null("Weapon")
	var from: Vector3 = muzzle.global_position if muzzle != null else vehicle.global_position
	var query := PhysicsRayQueryParameters3D.create(from, aim)
	query.exclude = [vehicle.get_rid()]
	var hit := vehicle.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == prey


func _nearest_enemy(vehicle: Pilotable) -> Pilotable:
	var nearest: Pilotable = null
	var nearest_distance := INF
	for node in vehicle.get_tree().get_nodes_in_group("team_enemy"):
		var other := node as Pilotable
		if other == null or not other.is_alive():
			continue
		var d := vehicle.global_position.distance_to(other.global_position)
		if d < nearest_distance:
			nearest = other
			nearest_distance = d
	return nearest


func _finish(vehicle: Pilotable) -> void:
	var seconds := frame / 60.0
	var enemies_left := battle.alive_enemy_count()
	var enemy_total := field.get_node("Enemies").get_child_count()
	var ally: Robot = field.get_node_or_null("SpareRobot")
	var hp_text := "—"
	if vehicle != null and is_instance_valid(vehicle):
		hp_text = "%d / %d" % [vehicle.hp, vehicle.max_hp]
	if vehicle != null and is_instance_valid(vehicle):
		hits = int(Bullet.hit_counts.get(vehicle.get_instance_id(), 0))
	var accuracy := 0.0
	if shots_fired > 0:
		accuracy = 100.0 * float(hits) / float(shots_fired)
	print("=== 自動プレイ結果 ===")
	print("構成: ", loadout if not loadout.is_empty() else "（保存済みの構成）")
	print("結果: ", "勝利" if battle.outcome == "win" else ("撃破された" if battle.outcome == "lose" else "時間切れ"))
	print("決着までの時間: %.1f 秒" % seconds)
	print("自機の残り耐久: ", hp_text)
	print("倒した敵: %d 体 / 残り %d 体" % [maxi(enemy_total - enemies_left, 0), enemies_left])
	print("撃った弾: %d 発、命中: %d 発（命中率 %.0f%%）" % [shots_fired, hits, accuracy])
	if ally != null and is_instance_valid(ally):
		print("味方機: ", "生存（耐久 %d / %d）" % [ally.hp, ally.max_hp] if ally.is_alive() else "撃破された")
	_restore_save()


func _restore_save() -> void:
	if saved_before != "":
		var f := FileAccess.open(LoadoutStore.PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(saved_before)
	elif FileAccess.file_exists(LoadoutStore.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LoadoutStore.PATH))


func _save_shot() -> void:
	await process_frame
	root.get_texture().get_image().save_png(shot_path)
	print("画像を保存: ", shot_path)
