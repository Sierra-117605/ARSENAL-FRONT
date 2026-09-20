class_name Aircraft
extends Pilotable
## 攻撃機（SPEC §0.15）。エースコンバット風に「常に前へ飛び続ける」機体。
## 空中で止まることはできず、マウス（＝操縦桿）で機首を上下させ、機体を傾けて旋回する。
##
## 操作：
##   マウス上下 = 機首の上げ下げ、マウス左右 = 機体を傾ける（傾けると旋回する）
##   W/S = 機首の上げ下げ（キーボードでも操作できる）、A/D = 機体を傾ける
##   Space = 加速、Shift = 減速、左クリック = 機関砲
## 地面にぶつかると墜落する。速度を落として水平に近づければ着陸できる。
##
## 操縦方式は 2 つ（ガレージ画面で切り替え。エースコンバットの呼び方に合わせている）：
##   エキスパート：機体を自由に回せる。360 度ロールも背面飛行もできて、自動で水平に戻らない
##   ノーヴィス：傾きが左右 80 度までで、手を離すと自動で水平に戻る（初心者向け）

## いちばん遅く飛べる速さ（メートル/秒）。これ以下には落ちない
@export var min_speed: float = 45.0
## いちばん速い速さ
@export var max_speed: float = 130.0
## 加速・減速の強さ（1 秒でどれだけ速さを変えられるか）
@export var throttle_power: float = 45.0
## 機首を上下に動かす速さ（度/秒）
@export var pitch_speed_deg: float = 55.0
## 機体を傾ける速さ（度/秒）
@export var roll_speed_deg: float = 130.0
## 傾けた時に曲がる強さ（度/秒。傾きが大きいほど速く曲がる）
@export var turn_rate_deg: float = 70.0
## 機首を上下に向けられる限界（度）
@export var pitch_limit_deg: float = 70.0
## これ以上は上がれない高さ（メートル）
@export var ceiling: float = 400.0
## 着陸できる最大の沈み込み速度（メートル/秒）
@export var landing_sink: float = 10.0
## 着陸できる最大の傾き（度）
@export var landing_tilt_deg: float = 20.0
## 地上での減速の強さ
@export var ground_brake: float = 40.0
## 方向舵（A/D と一緒に使う水平の回頭）の速さ（度/秒）
@export var rudder_speed_deg: float = 30.0
## 操縦方式（"expert" / "novice"）。空のままなら保存された設定を使う
@export var flight_mode: String = ""
## 全高（カメラが距離を合わせるのに使う）
var height: float = 5.0
## 照準できる距離（空からは遠くまで狙える）
var aim_range: float = 2600.0

## 今の速さ（メートル/秒）
var speed: float = 0.0
## 離陸直後に地面との接触を無視する残り時間（秒）
var takeoff_grace: float = 0.0
## 地上にいるか（駐機中・着陸後）
var on_ground: bool = true

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

## 墜落した時に知らせる
signal crashed

@onready var weapon: Weapon = get_node_or_null("Weapon")
@onready var gun_pivot: Node3D = get_node_or_null("Visual/GunPivot")
@onready var muzzle_point: Node3D = get_node_or_null("Visual/GunPivot/MuzzlePoint")


func _ready() -> void:
	super._ready()
	if flight_mode == "":
		flight_mode = SettingsStore.flight_mode()


## エキスパート操作か（ロール自由・自動で水平に戻らない）
func is_expert() -> bool:
	return flight_mode != SettingsStore.NOVICE


func _physics_process(delta: float) -> void:
	if not is_alive():
		# 撃墜されたら錐揉みしながら落ちる
		rotation.z += 3.0 * delta
		velocity.y -= gravity * delta
		move_and_slide()
		return

	if on_ground:
		_run_on_ground(delta)
	else:
		_fly(delta)
	_aim_gun()

	if control["fire"] and weapon != null:
		weapon.try_fire(Pilotable.aim_point(control), self)


## 駐機中・着陸後の動き。加速していけば浮き上がる
func _run_on_ground(delta: float) -> void:
	var throttle := float(control.get("throttle", 0.0))
	if throttle > 0.0:
		speed = clampf(speed + throttle * throttle_power * delta, 0.0, max_speed)
	else:
		speed = move_toward(speed, 0.0, ground_brake * delta)
	# 地上では機体を水平に戻す
	_level_off()
	# 左右の入力で向きを変える（滑走路での方向転換）
	rotation.y -= _roll_input() * deg_to_rad(40.0) * delta
	var forward := -global_transform.basis.z
	velocity = forward * speed
	velocity.y = -2.0  # 地面に押し付けておく
	move_and_slide()
	# 十分な速さになったら離陸する（機首を少し上げて地面から離れる）
	if speed >= min_speed:
		on_ground = false
		rotation.x = deg_to_rad(12.0)
		velocity.y = 6.0
		takeoff_grace = 0.8
		GameLog.write("航空機", "%s が離陸した（速度 %.0fm/秒）" % [name, speed])


## 飛んでいる間の動き
func _fly(delta: float) -> void:
	takeoff_grace = maxf(takeoff_grace - delta, 0.0)
	# 加速・減速（何も押していなければ今の速さを保つ）
	var throttle := float(control.get("throttle", 0.0))
	speed = clampf(speed + throttle * throttle_power * delta, min_speed, max_speed)

	if is_expert():
		_turn_expert(delta)
	else:
		_turn_novice(delta)

	# 機首の向いている方向へ、今の速さで進み続ける
	var forward := -global_transform.basis.z
	velocity = forward * speed
	if move_and_slide():
		_touch_ground()


## エキスパート操作：機体そのものの軸で回す。何度でもロールでき、背面飛行もできる
func _turn_expert(delta: float) -> void:
	var pitch_input := _pitch_input()
	var roll_input := _roll_input()
	var yaw_input := float(control.get("rudder", 0.0))
	# 機体から見た軸で回す（世界の上下に縛られないので一回転できる）
	var turn := Basis.IDENTITY
	turn = turn.rotated(Vector3.RIGHT, pitch_input * deg_to_rad(pitch_speed_deg) * delta)
	turn = turn.rotated(Vector3.BACK, -roll_input * deg_to_rad(roll_speed_deg) * delta)
	turn = turn.rotated(Vector3.UP, -yaw_input * deg_to_rad(rudder_speed_deg) * delta)
	transform.basis = (transform.basis * turn).orthonormalized()
	# 上限の高さを超えたら機首を下げる
	if global_position.y > ceiling:
		var nose_up: float = (-transform.basis.z).y
		if nose_up > 0.0:
			transform.basis = (transform.basis * Basis(Vector3.RIGHT,
				-deg_to_rad(60.0) * delta)).orthonormalized()


## ノーヴィス操作：傾きは左右 80 度まで。手を離すと自動で水平に戻る
func _turn_novice(delta: float) -> void:
	var pitch_input := _pitch_input()
	rotation.x = clampf(rotation.x + pitch_input * deg_to_rad(pitch_speed_deg) * delta,
		-deg_to_rad(pitch_limit_deg), deg_to_rad(pitch_limit_deg))
	var roll_input := _roll_input()
	if absf(roll_input) > 0.05:
		rotation.z = clampf(rotation.z - roll_input * deg_to_rad(roll_speed_deg) * delta,
			-deg_to_rad(80.0), deg_to_rad(80.0))
	else:
		rotation.z = move_toward(rotation.z, 0.0, deg_to_rad(40.0) * delta)
	# 傾けている方向へ旋回する（傾けるだけで曲がってくれる）
	rotation.y += sin(rotation.z) * deg_to_rad(turn_rate_deg) * delta
	if global_position.y > ceiling and rotation.x > 0.0:
		rotation.x = move_toward(rotation.x, 0.0, deg_to_rad(60.0) * delta)


## 地面・建物に触れた：条件が良ければ着陸、そうでなければ墜落
func _touch_ground() -> void:
	if takeoff_grace > 0.0:
		return  # 離陸した直後は地面をこすっても墜落しない
	# どれだけ傾いているか（機体の上が真上からどれだけずれているか）
	var tilt := transform.basis.y.angle_to(Vector3.UP)
	var sinking := -velocity.y
	var gentle: bool = sinking < landing_sink and tilt < deg_to_rad(landing_tilt_deg) \
		and speed < min_speed + 25.0 and is_on_floor()
	if gentle:
		on_ground = true
		_level_off()
		velocity = Vector3.ZERO
		GameLog.write("航空機", "%s が着陸した（速度 %.0fm/秒）" % [name, speed])
		return
	crash()


## 機体を水平に戻す（向きはそのまま）
func _level_off() -> void:
	var forward: Vector3 = -transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	rotation = Vector3(0.0, atan2(-forward.x, -forward.z), 0.0)


## 墜落する（撃墜と同じ扱い）
func crash() -> void:
	if not is_alive():
		return
	GameLog.write("航空機", "%s が墜落した（速度 %.0fm/秒・高さ %.0fm）" % [
		name, speed, global_position.y])
	crashed.emit()
	take_hit(max_hp)


## 機首を上げ下げする入力（＋で上向き）。マウスとキーボードの両方を足す
func _pitch_input() -> float:
	# move_z は W で -1（機首下げ）、S で +1（機首上げ）
	return clampf(float(control.get("stick_y", 0.0)) + float(control["move_z"]), -1.0, 1.0)


## 機体を傾ける入力（＋で右に傾く）
func _roll_input() -> float:
	return clampf(float(control.get("stick_x", 0.0)) + float(control["move_x"]), -1.0, 1.0)


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


## 地上にいるか（空中では乗り降りできない）
func is_landed() -> bool:
	return on_ground


## 保存用の状態
func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["kind"] = "aircraft"
	data["altitude"] = global_position.y
	data["speed"] = speed
	data["on_ground"] = on_ground
	data["flight_mode"] = flight_mode
	return data
