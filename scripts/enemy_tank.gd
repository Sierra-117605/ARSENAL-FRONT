class_name EnemyTank
extends CharacterBody2D

# Phase 2-1 minimum: 敵機体は静止して撃たれるだけ。
# AI (移動・射撃) は Phase 2-2 で追加予定。

@export var soft_attack: int = 10
@export var hard_attack: int = 70
@export var piercing: int = 90
@export var armor: int = 45
@export var hp_max: int = 80

var hp: int = 80

signal died(enemy: EnemyTank)

func _ready() -> void:
	add_to_group("enemy")
	hp = hp_max

func set_stats(stats: Dictionary, _hp_max: int) -> void:
	soft_attack = int(stats.get("soft_attack", soft_attack))
	hard_attack = int(stats.get("hard_attack", hard_attack))
	piercing = int(stats.get("piercing", piercing))
	armor = int(stats.get("armor", armor))
	hp_max = _hp_max
	hp = hp_max

func take_hit_from_projectile(proj: Projectile) -> void:
	var result: Dictionary = Combat.compute_damage(
		proj.soft_attack, proj.hard_attack, proj.piercing, armor
	)
	hp = max(0, hp - int(result.get("damage", 0)))
	if hp <= 0:
		died.emit(self)
		queue_free()
