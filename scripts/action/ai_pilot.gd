class_name AIPilot
extends Occupant
## コンピュータが動かす乗員。人の代わりに操縦席に座り、相手を追って撃つ。
## プレイヤー側と同じ「乗員 → 操縦席 → 乗り物」の道を通るので、
## 同じ機体をプレイヤーが操縦することもできる（乗り換え＝UNAC 方式、SPEC §0.13）。
##
## 毎フレーム考えること：
##  1. 誰を狙うか（指定があればその相手、無ければ敵陣営で最も近い相手）
##  2. 撃てるか（物陰にさえぎられていないか）
##  3. どこへ動くか（近すぎたら下がる／遠ければ寄る／横に動いて的になりにくくする／
##     物陰越しなら回り込む／耐久が減ったら距離を取る）
##  4. どこを狙うか（動いている相手の未来位置＝見越し射撃）

## 追いかける相手（固定で指定する場合）
@export var chase_target: Node3D
## プレイヤーの乗員。指定すると「今その人が乗っている機体」を追いかける（乗り換えに追従する）
@export var chase_occupant: Occupant
## この距離を保とうとする（メートル）
@export var preferred_distance: float = 55.0
## この距離まで近づくと撃ち始める（メートル）
@export var fire_range: float = 90.0
## 相手のどのくらいの高さを狙うか（足元からの高さ）
@export var aim_height: float = 6.0
## 撃つ間隔（秒）。プレイヤーより遅くしてある
@export var fire_interval: float = 2.0
## 保つ距離の許容幅（この幅の中では前後に動かない）
@export var distance_margin: float = 8.0
## 狙いのブレ（メートル）。0 だと百発百中で厳しすぎる
@export var aim_spread: float = 4.0
## 横移動の強さ（0 で横に動かない）
@export var strafe_strength: float = 0.8
## 横移動の向きを変える間隔（秒）
@export var strafe_interval: float = 2.5
## 耐久がこの割合を下回ると距離を取る
@export var retreat_hp_ratio: float = 0.35
## 距離を取るときに広げる距離（メートル）
@export var retreat_distance: float = 45.0
## 狙いを分散させる範囲（近い順にこの数の中から選ぶ）
@export var target_spread_count: int = 2

## 何機目の AI か（狙う相手を分散させるのに使う）
static var _spawn_count: int = 0
var _squad_index: int = 0

## 今の横移動の向き（+1 / -1）
var _strafe_dir: float = 1.0
var _strafe_timer: float = 0.0
## 物陰にさえぎられている間、回り込む向き
var _flank_dir: float = 1.0


func _ready() -> void:
	super._ready()
	var vehicle := get_vehicle()
	if vehicle != null and vehicle.get("weapon") != null:
		vehicle.weapon.fire_interval = fire_interval
	_squad_index = _spawn_count
	_spawn_count += 1
	# 機体ごとに癖をずらす（全員が同じ動きにならないように）
	_strafe_timer = randf() * strafe_interval
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0
	_flank_dir = _strafe_dir


func _physics_process(delta: float) -> void:
	var vehicle := get_vehicle()
	if vehicle == null:
		return
	var control := Pilotable.empty_control()
	var prey := _current_target()
	if not vehicle.is_alive() or prey == null or not _alive(prey):
		send_control(control)
		return

	var to_target: Vector3 = prey.global_position - vehicle.global_position
	var distance := Vector2(to_target.x, to_target.z).length()
	control["yaw"] = atan2(-to_target.x, -to_target.z)

	# 耐久が減っていたら、いつもより離れて戦う
	var keep := preferred_distance
	if float(vehicle.hp) / float(maxi(vehicle.max_hp, 1)) < retreat_hp_ratio:
		keep += retreat_distance

	# 前後：遠ければ寄る、近すぎれば下がる
	if distance > keep + distance_margin:
		control["move_z"] = -1.0
	elif distance < keep - distance_margin:
		control["move_z"] = 1.0

	# 横移動：一定時間ごとに向きを変えて、まっすぐ近づかない
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = strafe_interval
		_strafe_dir = -_strafe_dir
	control["move_x"] = _strafe_dir * strafe_strength

	# 撃てるか：物陰にさえぎられていないか調べる
	var aim_point := _lead_aim(vehicle, prey)
	if not _has_line_of_fire(vehicle, prey, aim_point):
		# さえぎられている間は、少し寄りながら横へ回り込む（撃たない）
		control["move_x"] = _flank_dir
		control["move_z"] = -0.6
	elif distance <= fire_range:
		control["fire"] = true
		var aim := aim_point + _spread()
		control["aim"] = {"x": aim.x, "y": aim.y, "z": aim.z}
	send_control(control)


## 見越し射撃：弾が届くまでに相手が進む分だけ先を狙う
func _lead_aim(vehicle: Pilotable, prey: Node3D) -> Vector3:
	var point: Vector3 = prey.global_position + Vector3(0.0, aim_height, 0.0)
	var bullet_speed := 300.0
	if vehicle.get("weapon") != null:
		bullet_speed = vehicle.weapon.bullet_speed
	var prey_velocity := Vector3.ZERO
	if prey is CharacterBody3D:
		prey_velocity = (prey as CharacterBody3D).velocity
	var travel_time := vehicle.global_position.distance_to(point) / maxf(bullet_speed, 1.0)
	return point + prey_velocity * travel_time


## 銃口から狙う点まで、物陰にさえぎられていないか
func _has_line_of_fire(vehicle: Pilotable, prey: Node3D, aim_point: Vector3) -> bool:
	var muzzle: Node3D = vehicle.get_node_or_null("Weapon")
	var from: Vector3 = muzzle.global_position if muzzle != null else vehicle.global_position
	var query := PhysicsRayQueryParameters3D.create(from, aim_point)
	query.exclude = [vehicle.get_rid()]
	var hit := vehicle.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	# 狙っている相手そのものに当たるなら、射線は通っている
	return hit["collider"] == prey


## 今狙うべき相手
## 1. 指定があり、それが生きていればその相手
## 2. いなければ、敵陣営でいちばん近い機体
func _current_target() -> Node3D:
	if chase_occupant != null:
		var piloted := chase_occupant.get_vehicle()
		if piloted != null and piloted.is_alive():
			return piloted
	if chase_target != null and _alive(chase_target):
		return chase_target
	return _nearest_enemy()


## 敵陣営から狙う相手を選ぶ。
## 近い順に並べ、上位（既定では 2 機）の中から機体ごとに違う相手を選ぶ。
## こうしないと敵が全員そろって同じ相手に群がってしまう。
func _nearest_enemy() -> Pilotable:
	var vehicle := get_vehicle()
	if vehicle == null:
		return null
	var enemy_team := "enemy" if vehicle.team == "player" else "player"
	var candidates: Array[Pilotable] = []
	for node in vehicle.get_tree().get_nodes_in_group("team_" + enemy_team):
		var other := node as Pilotable
		if other != null and other.is_alive():
			candidates.append(other)
	if candidates.is_empty():
		return null
	# 近い順に並べる
	var origin := vehicle.global_position
	candidates.sort_custom(func(a: Pilotable, b: Pilotable) -> bool:
		return origin.distance_to(a.global_position) < origin.distance_to(b.global_position))
	var choices := mini(candidates.size(), target_spread_count)
	return candidates[_squad_index % choices]


## 狙いのブレを作る
func _spread() -> Vector3:
	return Vector3(randf_range(-aim_spread, aim_spread), randf_range(-aim_spread, aim_spread),
		randf_range(-aim_spread, aim_spread))


## その相手がまだ生きているか
func _alive(node: Node3D) -> bool:
	if node is Pilotable:
		return (node as Pilotable).is_alive()
	return true
