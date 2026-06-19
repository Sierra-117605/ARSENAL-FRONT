extends Node2D

# Phase 2-1 出撃モード (最小実装)。
# プレイヤー機体を中央に、敵を 3 機配置。全滅させたら勝利、プレイヤー死亡で敗北。
# 任務システム連携 (現在派遣中の機体を使う等) は Phase 2-3 で。

const PLAYER_SCENE: String = "res://scenes/player_tank.tscn"
const ENEMY_SCENE: String = "res://scenes/enemy_tank.tscn"

@onready var spawn_layer: Node2D = $SpawnLayer
@onready var hp_bar: ProgressBar = $UI/HUD/PlayerHPBar
@onready var hp_label: Label = $UI/HUD/PlayerHPLabel
@onready var enemy_counter: Label = $UI/HUD/EnemyCounter
@onready var message_label: Label = $UI/HUD/MessageLabel
@onready var back_button: Button = $UI/HUD/BackButton
@onready var instruction_label: Label = $UI/HUD/InstructionLabel

var player: PlayerTank = null
var enemies: Array[EnemyTank] = []
var _ended: bool = false

func _ready() -> void:
	print("[ARSENAL FRONT] combat field opened")
	back_button.pressed.connect(_on_back_pressed)
	message_label.visible = false
	back_button.text = "戻る"
	# 出撃モード用の入力アクション (ESC で戻る等) は今は無し
	_spawn_player()
	_spawn_enemies()
	_update_enemy_counter()

func _spawn_player() -> void:
	var packed: PackedScene = load(PLAYER_SCENE)
	player = packed.instantiate() as PlayerTank
	player.global_position = Vector2(0, 0)
	player.hp_changed.connect(_on_player_hp_changed)
	player.died.connect(_on_player_died)
	spawn_layer.add_child(player)
	_on_player_hp_changed(player.hp, player.hp_max)

func _spawn_enemies() -> void:
	var packed: PackedScene = load(ENEMY_SCENE)
	var positions: Array[Vector2] = [
		Vector2(-600, -400),
		Vector2(600, -400),
		Vector2(0, 500),
	]
	for pos in positions:
		var e: EnemyTank = packed.instantiate() as EnemyTank
		e.global_position = pos
		e.died.connect(_on_enemy_died)
		spawn_layer.add_child(e)
		enemies.append(e)

func _on_player_hp_changed(new_hp: int, hp_max: int) -> void:
	hp_bar.max_value = hp_max
	hp_bar.value = new_hp
	hp_label.text = "HP %d / %d" % [new_hp, hp_max]

func _update_enemy_counter() -> void:
	var alive: int = 0
	for e in enemies:
		if is_instance_valid(e):
			alive += 1
	enemy_counter.text = "敵 %d 機 残存" % alive
	if alive == 0 and not _ended:
		_end_combat(true)

func _on_enemy_died(_e: EnemyTank) -> void:
	_update_enemy_counter()

func _on_player_died() -> void:
	if not _ended:
		_end_combat(false)

func _end_combat(won: bool) -> void:
	_ended = true
	message_label.visible = true
	if won:
		message_label.text = "★ 勝利 ★\n敵を殲滅した"
		message_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	else:
		message_label.text = "▼ 敗北 ▼\n機体が撃破された"
		message_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	# プレイヤーが死んでいる場合、操作不能にする (queue_free 済みのはず)
	instruction_label.visible = false

func _on_back_pressed() -> void:
	print("[ARSENAL FRONT] combat field closed, returning to main")
	get_tree().change_scene_to_file("res://scenes/main.tscn")
