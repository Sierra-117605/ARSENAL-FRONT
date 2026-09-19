class_name Robot
extends Pilotable
## 二足歩行ロボット。操縦入力に従って歩く。
## Phase 1 の自機は多用途歩行機（全高 約 12m、SPEC §0.9）。

## 機種（SPEC §0.9 の機種区分。保存用の文字列）
@export var machine_type: String = "multirole_walker"
## 歩く速さ（メートル/秒）
@export var walk_speed: float = 10.0
## 歩き出し・止まりの滑らかさ（大きいほどキビキビ）
@export var acceleration: float = 40.0

## 重力の強さ（プロジェクト設定の値を使う）
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

## 腕の武器（Phase 1 は 1 種類）
@onready var weapon: Weapon = get_node_or_null("Weapon")


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

	# 射撃ボタンが押されていれば、照準の先へ撃つ
	if control["fire"] and weapon != null:
		weapon.try_fire(Pilotable.aim_point(control), self)


## 保存用の状態に機種を加える
func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["machine_type"] = machine_type
	return data


## 保存した状態から機種も戻す
func from_dict(data: Dictionary) -> void:
	super.from_dict(data)
	machine_type = data.get("machine_type", machine_type)
