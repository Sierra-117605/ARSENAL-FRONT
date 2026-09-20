class_name Tank
extends Pilotable
## 戦車（SPEC §0.13 柱1：乗り換えの幅を広げる）。
## ロボットと違い、車体は向いた方向にしか進めない（横歩きできない）。
## 代わりに速く、低くて撃たれにくい。砲塔は狙った方向へ向く。

## 前進の速さ（メートル/秒）
@export var drive_speed: float = 22.0
## 後退の速さ
@export var reverse_speed: float = 10.0
## 車体の旋回の速さ（度/秒）
@export var turn_speed_deg: float = 70.0
## 加速の滑らかさ
@export var acceleration: float = 25.0
## 全高（カメラが距離を合わせるのに使う）
var height: float = 3.2
## 照準できる距離
var aim_range: float = 1800.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var weapon: Weapon = get_node_or_null("Weapon")
@onready var turret: Node3D = get_node_or_null("Visual/Turret")
@onready var muzzle_point: Node3D = get_node_or_null("Visual/Turret/MuzzlePoint")


func _physics_process(delta: float) -> void:
	if not is_alive():
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	# 左右の入力で車体が旋回する（その場で横には動けない）
	rotation.y -= float(control["move_x"]) * deg_to_rad(turn_speed_deg) * delta

	# 前後の入力で進む。後退は遅い
	var forward := -global_transform.basis.z
	var input_z := float(control["move_z"])
	var wanted := Vector3.ZERO
	if input_z < 0.0:
		wanted = forward * drive_speed * -input_z
	elif input_z > 0.0:
		wanted = -forward * reverse_speed * input_z
	velocity.x = move_toward(velocity.x, wanted.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, wanted.z, acceleration * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()

	# 砲塔は狙っている方向へ向く（車体の向きとは別）
	var aim := Pilotable.aim_point(control)
	if turret != null and aim != Vector3.ZERO:
		var to_aim: Vector3 = aim - turret.global_position
		if Vector2(to_aim.x, to_aim.z).length() > 0.1:
			var wanted_yaw := atan2(-to_aim.x, -to_aim.z)
			turret.global_rotation.y = wanted_yaw

	# 銃口を砲身の先に合わせる（弾が砲口から出るように）
	if weapon != null and muzzle_point != null:
		weapon.global_transform = muzzle_point.global_transform

	if control["fire"] and weapon != null:
		weapon.try_fire(aim, self)


## 保存用の状態
func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["kind"] = "tank"
	return data
