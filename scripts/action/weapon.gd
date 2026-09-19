class_name Weapon
extends Marker3D
## 武器（Phase 1 は 1 種類）。この点（銃口）から弾を撃ち出す。
## 左クリックを押している間、一定間隔で撃ち続ける。

## 撃ち出す弾のシーン
@export var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
## 次の弾までの間隔（秒）
@export var fire_interval: float = 0.25

var cooldown: float = 0.0


func _physics_process(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)


## 撃てるなら aim_point に向けて 1 発撃つ。撃ったら true
func try_fire(aim_point: Vector3, shooter: CollisionObject3D) -> bool:
	if cooldown > 0.0:
		return false
	var dir := aim_point - global_position
	if dir.length() < 0.01:
		return false
	cooldown = fire_interval
	var bullet: Bullet = bullet_scene.instantiate()
	# 弾は機体の子ではなく、機体と同じ場所（フィールド）に置く
	shooter.get_parent().add_child(bullet)
	bullet.launch(global_position, dir, shooter)
	return true
