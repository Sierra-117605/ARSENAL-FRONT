class_name Helicopter
extends Pilotable
## ヘリコプター（SPEC §0.16）。プレイヤーが乗れる空の機体。
## 攻撃機（ジェット）と違って**その場に止まれる**ので、ロボットや戦車と同じ感覚で操縦できる。
##
## 操作：
##   W/S = 前進・後退、A/D = 左右に平行移動（機首は狙っている方向を向く）
##   Space = 上昇、Shift = 下降。どちらも押していなければその高さで止まる（ホバリング）
##   マウス = 狙う方向、左クリックまたは Ctrl = 機関砲
## 誰も乗っていない時は AI が操縦して、決まった高さで戦う。

## 前進の速さ（メートル/秒）
@export var forward_speed: float = 34.0
## 後退の速さ
@export var back_speed: float = 18.0
## 左右に平行移動する速さ
@export var strafe_speed: float = 24.0
## 加速の滑らかさ
@export var acceleration: float = 30.0
## 上昇・下降の速さ
@export var climb_speed: float = 18.0
## 上下の加速の滑らかさ
@export var climb_acceleration: float = 60.0
## 機首が狙う方向へ向く速さ（度/秒）
@export var turn_speed_deg: float = 120.0
## これ以上は上がれない高さ（メートル）
@export var ceiling: float = 220.0
## 進む向きに機体を傾ける角度（度。見た目だけ）
@export var tilt_deg: float = 12.0
## AI が操縦している時に保つ高さ（メートル）
@export var ai_cruise_height: float = 35.0
## AI は出撃直後この秒数だけ着陸して待つ（プレイヤーが乗り込む時間。過ぎたら AI が飛び立つ）
@export var ai_wait_time: float = 25.0
## 誰も乗っていない時に自分で降りてくる速さ（メートル/秒）
@export var landing_speed: float = 8.0
## 全高（カメラが距離を合わせるのに使う）
var height: float = 6.0
## 照準できる距離
var aim_range: float = 1800.0

@onready var weapon: Weapon = get_node_or_null("Weapon")
@onready var visual: Node3D = get_node_or_null("Visual")
@onready var rotor: Node3D = get_node_or_null("Visual/Rotor")
@onready var gun_pivot: Node3D = get_node_or_null("Visual/GunPivot")
@onready var muzzle_point: Node3D = get_node_or_null("Visual/GunPivot/MuzzlePoint")

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

## AI が待機している残り時間（秒）
var ai_wait_left: float = 0.0


func _ready() -> void:
	super._ready()
	ai_wait_left = ai_wait_time


func _physics_process(delta: float) -> void:
	if rotor != null:
		rotor.rotate_y(18.0 * delta)  # 回転翼を回す（見た目）
	if not is_alive():
		# 撃墜されたら落ちる
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		velocity.y -= gravity * delta
		move_and_slide()
		return

	# プレイヤーが乗っている間は待機時間を数え直す（降りてもすぐには飛び立たない）
	if _driver_is_ai():
		ai_wait_left = maxf(ai_wait_left - delta, 0.0)
	else:
		ai_wait_left = ai_wait_time

	_turn_to_aim(delta)
	_move_horizontal(delta)
	_move_vertical(delta)
	move_and_slide()
	_update_tilt(delta)
	_aim_gun()

	if control["fire"] and weapon != null:
		weapon.try_fire(Pilotable.aim_point(control), self)


## 機首を狙っている方向へ向ける
func _turn_to_aim(delta: float) -> void:
	var aim := Pilotable.aim_point(control)
	if aim == Vector3.ZERO:
		return
	var to_aim: Vector3 = aim - global_position
	if Vector2(to_aim.x, to_aim.z).length() < 0.1:
		return
	var wanted := atan2(-to_aim.x, -to_aim.z)
	rotation.y = rotate_toward(rotation.y, wanted, deg_to_rad(turn_speed_deg) * delta)


## 前後・左右の動き（機首の向きが基準）
func _move_horizontal(delta: float) -> void:
	if _ai_waiting():
		# 待機中は動かない（乗り込む相手が近づけるように）
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		return
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


## 上下の動き。入力が無ければその高さで止まる（ホバリング）
func _move_vertical(delta: float) -> void:
	var lift := float(control.get("lift", 0.0))
	if lift > 0.0 and global_position.y >= ceiling:
		lift = 0.0  # 上限の高さまで来たらそれ以上は上がらない
	var wanted := lift * climb_speed
	if lift == 0.0:
		if _ai_waiting():
			wanted = 0.0 if is_on_floor() else -landing_speed
		elif _driver_is_ai():
			# AI が操縦している時は、決まった高さまで自分で上がって飛び続ける
			wanted = clampf(ai_cruise_height - global_position.y, -climb_speed, climb_speed)
		elif not _has_driver() and not is_on_floor():
			# 誰も乗っていない機体は、ゆっくり降りて自分で着陸する
			wanted = -landing_speed
		elif is_on_floor():
			wanted = 0.0
	velocity.y = move_toward(velocity.y, wanted, climb_acceleration * delta)


## 進んでいる向きへ機体を少し傾ける（見た目だけ。ヘリらしさを出す）
func _update_tilt(delta: float) -> void:
	if visual == null:
		return
	var wanted_pitch := -float(control["move_z"]) * deg_to_rad(tilt_deg)
	var wanted_roll := -float(control["move_x"]) * deg_to_rad(tilt_deg)
	visual.rotation.x = move_toward(visual.rotation.x, wanted_pitch, deg_to_rad(60.0) * delta)
	visual.rotation.z = move_toward(visual.rotation.z, wanted_roll, deg_to_rad(60.0) * delta)


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


## AI が「まだ飛び立たずに待っている」状態か
func _ai_waiting() -> bool:
	return _driver_is_ai() and ai_wait_left > 0.0


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
	data["kind"] = "helicopter"
	data["altitude"] = global_position.y
	return data
