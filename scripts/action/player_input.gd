class_name PlayerInput
extends Node
## プレイヤーのキー・マウス操作を読み取り、操縦入力にして乗員へ渡す。
## 流れ：キー操作 → PlayerInput → 乗員(Occupant) → 操縦席(Seat) → 乗り物(Pilotable)
## マウスの動きはカメラ土台(CameraRig)の向きを回し、その向きを操縦入力に載せる。

## 操作を渡す相手の乗員
@export var occupant: Occupant
## 見ている方向を持つカメラ土台
@export var camera_rig: CameraRig
## マウス感度（1 ピクセル動かしたときに回る角度・ラジアン）
@export var mouse_sensitivity: float = 0.003

## マウスでカメラを回せる状態か（Esc で解除、画面クリックで再開）
var look_enabled: bool = true


func _ready() -> void:
	InputActions.ensure_registered()
	_set_look_enabled(true)


func _unhandled_input(event: InputEvent) -> void:
	# Esc：マウスカーソルを戻す
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_set_look_enabled(false)
		return
	# カーソルが出ている時の左クリック：再びカメラ操作に戻る（このクリックでは撃たない）
	if event is InputEventMouseButton and event.pressed and not look_enabled:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_set_look_enabled(true)
			get_viewport().set_input_as_handled()
		return
	# マウスの動き：カメラを回す（右へ動かすと右を向く、上へ動かすと上を向く）
	if event is InputEventMouseMotion and look_enabled and camera_rig != null:
		var d: Vector2 = event.screen_relative
		camera_rig.add_look(-d.x * mouse_sensitivity, -d.y * mouse_sensitivity)


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
	if camera_rig != null:
		control["yaw"] = camera_rig.yaw
		control["pitch"] = camera_rig.pitch
	occupant.send_control(control)


## カメラ操作の有効/無効を切り替え、マウスカーソルの表示を合わせる
func _set_look_enabled(enabled: bool) -> void:
	look_enabled = enabled
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE
