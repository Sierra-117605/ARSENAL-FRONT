class_name PlayerInput
extends Node
## プレイヤーのキー・マウス操作を読み取り、操縦入力にして乗員へ渡す。
## 流れ：キー操作 → PlayerInput → 乗員(Occupant) → 操縦席(Seat) → 乗り物(Pilotable)

## 操作を渡す相手の乗員
@export var occupant: Occupant


func _ready() -> void:
	InputActions.ensure_registered()


func _physics_process(_delta: float) -> void:
	if occupant == null:
		return
	var control := Pilotable.empty_control()
	# WASD を「左右」「前後」の 2 つの値にまとめる（前が -1）
	var move := Input.get_vector(
		InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT,
		InputActions.MOVE_FORWARD, InputActions.MOVE_BACK)
	control["move_x"] = move.x
	control["move_z"] = move.y
	occupant.send_control(control)
