class_name Soldier
extends Pilotable
## 兵士（徒歩）。ロボットや車両と同じ「操縦可能な物」として作る（SPEC §0.3-1）。
## 乗員がこの体を動かし、乗り物に乗り込むとこの体は機体に預けられる。

## 歩く速さ（メートル/秒）
@export var walk_speed: float = 6.0
## 走り出し・止まりの滑らかさ
@export var acceleration: float = 30.0
## 全高（カメラが距離を合わせるのに使う）
var height: float = 1.8
## 照準できる距離
var aim_range: float = 400.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var weapon: Weapon = get_node_or_null("Weapon")


func _ready() -> void:
	super._ready()
	# 兵士は機体より脆い
	if max_hp > 100:
		max_hp = 100
		hp = max_hp


func _physics_process(delta: float) -> void:
	if not is_alive():
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	rotation.y = control["yaw"]
	var input_dir := Vector3(control["move_x"], 0.0, control["move_z"])
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	var target := global_transform.basis * input_dir * walk_speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()

	if control["fire"] and weapon != null:
		weapon.try_fire(Pilotable.aim_point(control), self)


## 乗り物に乗り込む時：体を隠して動かなくする
func enter_vehicle() -> void:
	visible = false
	set_physics_process(false)
	# 当たり判定も止める（機体の中にいる扱い）
	for owner_id in get_shape_owners():
		shape_owner_set_disabled(owner_id, true)


## 乗り物から降りる時：指定の場所に体を戻す
func exit_vehicle(at_position: Vector3, facing_yaw: float) -> void:
	global_position = at_position
	rotation.y = facing_yaw
	velocity = Vector3.ZERO
	visible = true
	set_physics_process(true)
	for owner_id in get_shape_owners():
		shape_owner_set_disabled(owner_id, false)
