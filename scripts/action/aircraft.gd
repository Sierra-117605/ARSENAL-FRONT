class_name Aircraft
extends Pilotable
## 攻撃機（垂直に浮き上がれる機体）。
## 空を飛べるので物陰や地形を越えて回り込めるが、装甲は薄く、当たればすぐ落ちる。
##
## 操作（SPEC §0.15）：
##   W/S = 前進・後退、A/D = 左右に平行移動、Space = 上昇、Shift = 下降
##   マウス = 狙う方向（機首がその方向へ向く）、左クリック = 機関砲
## 上昇も下降もしていない時は、その高さのまま浮いて止まる（ホバリング）。

## 前進の速さ（メートル/秒）
@export var forward_speed: float = 55.0
## 後退の速さ
@export var back_speed: float = 22.0
## 左右に平行移動する速さ
@export var strafe_speed: float = 32.0
## 加速の滑らかさ
@export var acceleration: float = 45.0
## 上昇・下降の速さ
@export var climb_speed: float = 22.0
## 上下の加速の滑らかさ
@export var climb_acceleration: float = 80.0
## 機首が狙う方向へ向く速さ（度/秒）
@export var turn_speed_deg: float = 110.0
## これ以上は上がれない高さ（メートル）
@export var ceiling: float = 220.0
## 見た目の傾き（度）。曲がる時に機体を傾ける
@export var bank_deg: float = 25.0
## AI が操縦している時に保つ高さ（メートル）。プレイヤーが乗っている間は使わない
@export var ai_cruise_height: float = 40.0
## 誰も乗っていない時に自分で降りてくる速さ（メートル/秒）
@export var landing_speed: float = 8.0
## 全高（カメラが距離を合わせるのに使う）
var height: float = 5.0
## 照準できる距離（空からは遠くまで狙える）
var aim_range: float = 2600.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var weapon: Weapon = get_node_or_null("Weapon")
@onready var visual: Node3D = get_node_or_null("Visual")
@onready var gun_pivot: Node3D = get_node_or_null("Visual/GunPivot")
@onready var muzzle_point: Node3D = get_node_or_null("Visual/GunPivot/MuzzlePoint")


func _physics_process(delta: float) -> void:
	if not is_alive():
		# 撃墜されたら推力を失って落ちる
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		velocity.y -= gravity * delta
		move_and_slide()
		return

	_turn_to_aim(delta)
	_move_horizontal(delta)
	_move_vertical(delta)
	move_and_slide()
	_update_bank(delta)
	_aim_gun()

	if control["fire"] and weapon != null:
		weapon.try_fire(Pilotable.aim_point(control), self)


## 機首を狙っている方向へ向ける（すぐには向かず、少しずつ回る）
func _turn_to_aim(delta: float) -> void:
	var aim := Pilotable.aim_point(control)
	if aim == Vector3.ZERO:
		return
	var to_aim: Vector3 = aim - global_position
	if Vector2(to_aim.x, to_aim.z).length() < 0.1:
		return
	var wanted := atan2(-to_aim.x, -to_aim.z)
	rotation.y = rotate_toward(rotation.y, wanted, deg_to_rad(turn_speed_deg) * delta)


## 前後・左右の動き（機首の向きを基準に動く）
func _move_horizontal(delta: float) -> void:
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	var input_z := float(control["move_z"])
	var wanted := right * float(control["move_x"]) * strafe_speed
	if input_z < 0.0:
		wanted += forward * forward_speed * -input_z
	elif input_z > 0.0:
		wanted += -forward * back_speed * input_z
	velocity.x = move_toward(velocity.x, wanted.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, wanted.z, acceleration * delta)


## 上下の動き。入力が無ければその高さで浮いて止まる
func _move_vertical(delta: float) -> void:
	var lift := float(control.get("lift", 0.0))
	if lift > 0.0 and global_position.y >= ceiling:
		lift = 0.0  # 上限の高さまで来たらそれ以上は上がらない
	var wanted := lift * climb_speed
	if lift == 0.0:
		if _driver_is_ai():
			# AI が操縦している時は、決まった高さまで自分で上がって飛び続ける
			var diff := ai_cruise_height - global_position.y
			wanted = clampf(diff, -climb_speed, climb_speed)
		elif not _has_driver() and not is_on_floor():
			# 誰も乗っていない機体は、ゆっくり降りて自分で着陸する
			wanted = -landing_speed
	velocity.y = move_toward(velocity.y, wanted, climb_acceleration * delta)


## 曲がる時・横に動く時に機体を傾ける（見た目だけ）
func _update_bank(delta: float) -> void:
	if visual == null:
		return
	var wanted := -float(control["move_x"]) * deg_to_rad(bank_deg)
	visual.rotation.z = move_toward(visual.rotation.z, wanted, deg_to_rad(90.0) * delta)


## 機関砲を狙っている方向へ向け、弾が銃口の先から出るようにする
func _aim_gun() -> void:
	if gun_pivot == null:
		return
	var aim := Pilotable.aim_point(control)
	if aim != Vector3.ZERO:
		var to_aim: Vector3 = aim - gun_pivot.global_position
		if to_aim.length() > 0.5:
			gun_pivot.global_basis = Basis.looking_at(to_aim.normalized())
	if weapon != null and muzzle_point != null:
		weapon.global_transform = muzzle_point.global_transform


## 操縦席に誰か座っているか
func _has_driver() -> bool:
	for seat in get_seats():
		if seat.is_driver:
			return seat.occupant != null
	return false


## 今の操縦者が AI かどうか
func _driver_is_ai() -> bool:
	for seat in get_seats():
		if seat.is_driver:
			return seat.occupant is AIPilot
	return false


## 地上に降りているか（空中では乗り降りできない）
func is_landed() -> bool:
	return is_on_floor()


## 保存用の状態
func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["kind"] = "aircraft"
	data["altitude"] = global_position.y
	return data
