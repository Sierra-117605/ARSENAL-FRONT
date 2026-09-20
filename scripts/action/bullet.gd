class_name Bullet
extends Node3D
## 目に見えて飛んでいく弾（SPEC §0.7）。
## 毎フレーム「前の位置→今の位置」の線で当たりを調べるので、速くてもすり抜けない。
## 当たった相手が take_hit を持っていれば呼ぶ（標的などが受け取る）。

## 飛ぶ速さ（メートル/秒）
@export var speed: float = 300.0
## これだけ飛んだら消える（メートル）
@export var max_distance: float = 1200.0
## 1 発のダメージ（標的の耐久を減らす量）
@export var damage: int = 10

## 飛ぶ向き（長さ 1）
var direction: Vector3 = Vector3.FORWARD
## 撃った本人（自分には当たらない）
var shooter_rid: RID
## 撃った機体ごとの命中数（自動プレイ検証で命中率を出すために数えている）
static var hit_counts: Dictionary = {}
## 撃った機体の識別番号
var shooter_id: int = 0
var travelled: float = 0.0


## 発射位置と向きを決める（シーンに追加した直後に呼ぶ）
func launch(from: Vector3, dir: Vector3, shooter: CollisionObject3D) -> void:
	direction = dir.normalized()
	if shooter != null:
		shooter_rid = shooter.get_rid()
		shooter_id = shooter.get_instance_id()
	# 弾の見た目を飛ぶ向きにそろえる（-Z が進行方向）
	global_transform = Transform3D(Basis.looking_at(direction), from)


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + direction * speed * delta
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if shooter_rid.is_valid():
		query.exclude = [shooter_rid]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		Sounds.play_at(self, Sounds.IMPACT, hit["position"])
		var target: Object = hit["collider"]
		if target != null and target.has_method("take_hit"):
			target.take_hit(damage)
			hit_counts[shooter_id] = int(hit_counts.get(shooter_id, 0)) + 1
		queue_free()
		return
	global_position = to
	travelled += speed * delta
	if travelled >= max_distance:
		queue_free()
