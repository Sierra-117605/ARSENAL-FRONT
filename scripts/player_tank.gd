class_name PlayerTank
extends CharacterBody2D

# Phase 2 プレイヤー機体 (トップダウン)。
# WASD/矢印で移動、マウスで照準、左クリックで射撃。
# ステータスは Inspector または外部から set_stats() で注入。

@export var speed: float = 280.0
@export var soft_attack: int = 25
@export var hard_attack: int = 50
@export var piercing: int = 70
@export var armor: int = 60
@export var hp_max: int = 95

var hp: int = 95
var _fire_cooldown: float = 0.0
const FIRE_INTERVAL: float = 0.35

signal hp_changed(new_hp: int, hp_max: int)
signal died

func _ready() -> void:
	add_to_group("player")
	hp = hp_max
	hp_changed.emit(hp, hp_max)

func set_stats(stats: Dictionary, _hp_max: int) -> void:
	soft_attack = int(stats.get("soft_attack", soft_attack))
	hard_attack = int(stats.get("hard_attack", hard_attack))
	piercing = int(stats.get("piercing", piercing))
	armor = int(stats.get("armor", armor))
	hp_max = _hp_max
	hp = hp_max
	hp_changed.emit(hp, hp_max)

func _physics_process(delta: float) -> void:
	# --- 移動 ---
	var input_vec: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_vec.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_vec.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_vec.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_vec.x += 1
	if input_vec.length() > 0:
		input_vec = input_vec.normalized()
	velocity = input_vec * speed
	move_and_slide()

	# --- 旋回 (マウス方向を向く) ---
	var mouse_pos: Vector2 = get_global_mouse_position()
	rotation = (mouse_pos - global_position).angle()

	# --- 射撃 (連射制御) ---
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _fire_cooldown <= 0.0:
		_fire()
		_fire_cooldown = FIRE_INTERVAL

func _fire() -> void:
	var packed: PackedScene = load("res://scenes/projectile.tscn")
	if packed == null:
		return
	var proj: Projectile = packed.instantiate() as Projectile
	proj.global_position = global_position + Vector2(35, 0).rotated(rotation)
	proj.direction = Vector2(1, 0).rotated(rotation)
	proj.owner_side = "player"
	proj.soft_attack = soft_attack
	proj.hard_attack = hard_attack
	proj.piercing = piercing
	get_parent().add_child(proj)

func take_hit_from_projectile(proj: Projectile) -> void:
	var result: Dictionary = Combat.compute_damage(
		proj.soft_attack, proj.hard_attack, proj.piercing, armor
	)
	hp = max(0, hp - int(result.get("damage", 0)))
	hp_changed.emit(hp, hp_max)
	if hp <= 0:
		died.emit()
		queue_free()
