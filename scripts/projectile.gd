class_name Projectile
extends Area2D

# Phase 2 用の弾丸。
# Area2D で発射元の攻撃ステータスを保持し、敵 (collision_mask の対象) に当たったら
# Combat.compute_damage で単発ダメージを計算して TakeHit シグナルを叩く。

@export var speed: float = 900.0
@export var lifetime: float = 2.0

var direction: Vector2 = Vector2.RIGHT
var owner_side: String = "player"    # "player" or "enemy"
var soft_attack: int = 0
var hard_attack: int = 0
var piercing: int = 0

var _age: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_age += delta
	if _age >= lifetime:
		queue_free()

func _on_body_entered(body: Node) -> void:
	# 自分の発射元側にはダメージを与えない
	if owner_side == "player" and body.is_in_group("player"):
		return
	if owner_side == "enemy" and body.is_in_group("enemy"):
		return
	if body.has_method("take_hit_from_projectile"):
		body.take_hit_from_projectile(self)
	queue_free()
