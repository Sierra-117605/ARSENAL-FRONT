class_name EnemyTank
extends CharacterBody2D

# Phase 2-2 敵機体 AI 最小実装:
# - プレイヤーを向く
# - preferred_distance を保ちながら接近/後退
# - 射程内なら一定間隔で射撃

@export var speed: float = 130.0
@export var soft_attack: int = 10
@export var hard_attack: int = 70
@export var piercing: int = 90
@export var armor: int = 45
@export var hp_max: int = 80
@export var preferred_distance: float = 360.0
@export var fire_range: float = 520.0

const FIRE_INTERVAL: float = 1.6
const DEAD_ZONE: float = 40.0  # preferred_distance との±これ以内は静止

var hp: int = 80
var _fire_cooldown: float = 0.0
var _player_ref: Node2D = null

signal died(enemy: EnemyTank)

func _ready() -> void:
	add_to_group("enemy")
	hp = hp_max
	_fire_cooldown = randf() * FIRE_INTERVAL  # 初回射撃をずらして同時射出を避ける

func set_stats(stats: Dictionary, _hp_max: int) -> void:
	soft_attack = int(stats.get("soft_attack", soft_attack))
	hard_attack = int(stats.get("hard_attack", hard_attack))
	piercing = int(stats.get("piercing", piercing))
	armor = int(stats.get("armor", armor))
	hp_max = _hp_max
	hp = hp_max

func _physics_process(delta: float) -> void:
	# プレイヤー参照のキャッシュ (死んでたらクリア)
	if not is_instance_valid(_player_ref):
		var players: Array = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player_ref = players[0]
		else:
			velocity = Vector2.ZERO
			move_and_slide()
			return

	var to_player: Vector2 = _player_ref.global_position - global_position
	var dist: float = to_player.length()
	if dist <= 0.001:
		return

	# 旋回 (プレイヤー方向)
	rotation = to_player.angle()

	# 接近/後退/静止
	var dir: Vector2 = to_player.normalized()
	if dist > preferred_distance + DEAD_ZONE:
		velocity = dir * speed
	elif dist < preferred_distance - DEAD_ZONE:
		velocity = -dir * speed * 0.6  # 後退は少し遅く
	else:
		velocity = Vector2.ZERO
	move_and_slide()

	# 射撃
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta
	if dist <= fire_range and _fire_cooldown <= 0.0:
		_fire()
		_fire_cooldown = FIRE_INTERVAL

func _fire() -> void:
	var packed: PackedScene = load("res://scenes/projectile.tscn")
	if packed == null:
		return
	var proj: Projectile = packed.instantiate() as Projectile
	proj.global_position = global_position + Vector2(35, 0).rotated(rotation)
	proj.direction = Vector2(1, 0).rotated(rotation)
	proj.owner_side = "enemy"
	proj.soft_attack = soft_attack
	proj.hard_attack = hard_attack
	proj.piercing = piercing
	get_parent().add_child(proj)

func take_hit_from_projectile(proj: Projectile) -> void:
	var result: Dictionary = Combat.compute_damage(
		proj.soft_attack, proj.hard_attack, proj.piercing, armor
	)
	hp = max(0, hp - int(result.get("damage", 0)))
	if hp <= 0:
		died.emit(self)
		queue_free()
