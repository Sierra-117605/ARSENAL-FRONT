class_name CameraRig
extends Node3D
## カメラの土台。見ている方向（yaw/pitch）を持ち、今の視点(CameraView)にカメラを動かしてもらう。
## 視点は子に置いた CameraView。後からコックピット視点などを子に足せば切り替えられる（SPEC §0.3-3）。

## 追いかける対象
@export var target: Node3D
## 上を向ける限界（度）。これ以上だとカメラが地面に潜る
@export var pitch_max_deg: float = 15.0
## 下を向ける限界（度）
@export var pitch_min_deg: float = -60.0

## 見ている方向の水平角（ラジアン。0 = 最初の正面、+ で左回り）
var yaw: float = 0.0
## 見ている方向の上下角（ラジアン。- で下向き）
var pitch: float = deg_to_rad(-3.0)
## 今使っている視点の番号
var view_index: int = 0

@onready var camera: Camera3D = $Camera3D


func _process(_delta: float) -> void:
	if target == null:
		return
	global_position = target.global_position
	var view := get_current_view()
	if view != null:
		view.update_camera(camera, target, yaw, pitch)


## 見ている方向を回す（マウスの動き量をラジアンで受け取る）
func add_look(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(pitch + d_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))


## 登録されている視点の一覧
func get_views() -> Array[CameraView]:
	var views: Array[CameraView] = []
	for child in get_children():
		if child is CameraView:
			views.append(child)
	return views


## 今の視点
func get_current_view() -> CameraView:
	var views := get_views()
	if views.is_empty():
		return null
	return views[clampi(view_index, 0, views.size() - 1)]


## 次の視点に切り替える（Phase 1 は三人称だけなので変化なし）
func next_view() -> void:
	var count := get_views().size()
	if count > 0:
		view_index = (view_index + 1) % count
