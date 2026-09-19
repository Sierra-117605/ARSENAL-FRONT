class_name ThirdPersonView
extends CameraView
## 三人称視点（肩越し）：機体の右後ろ上方から、見ている方向を映す。
## 機体が画面のやや左に映り、画面中央の照準が機体に隠れない（SPEC §0.7）。

## 回転の中心の高さ（機体の足元から。胸〜頭のあたり）
@export var pivot_height: float = 3.5
## 回転の中心からカメラまでの距離
@export var distance: float = 9.0
## カメラを右にずらす量（肩越し）
@export var shoulder_offset: float = 2.5
## カメラが地面に潜らないための最低の高さ
@export var min_camera_height: float = 0.5


func update_camera(camera: Camera3D, target: Node3D, yaw: float, pitch: float) -> void:
	var pivot := target.global_position + Vector3(0.0, pivot_height, 0.0)
	var look := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	# 見ている方向の真後ろに下がった位置にカメラを置く
	var pos := pivot + look * Vector3(shoulder_offset, 0.0, distance)
	pos.y = maxf(pos.y, target.global_position.y + min_camera_height)
	camera.global_transform = Transform3D(look, pos)
