class_name Robot
extends Pilotable
## 二足歩行ロボット。操縦入力に従って歩く。

## 歩く速さ（メートル/秒）
@export var walk_speed: float = 6.0
## 歩き出し・止まりの滑らかさ（大きいほどキビキビ）
@export var acceleration: float = 30.0

## 重力の強さ（プロジェクト設定の値を使う）
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _physics_process(delta: float) -> void:
	# 機体をカメラの向き（操縦入力の yaw）に合わせる（SPEC §0.7）
	rotation.y = control["yaw"]
	# 入力を機体の向き基準の方向に直す（前 = 機体の正面）
	var input_dir := Vector3(control["move_x"], 0.0, control["move_z"])
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	var target := global_transform.basis * input_dir * walk_speed

	# 水平方向は目標速度へ徐々に近づける
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	# 地面にいなければ落ちる
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
