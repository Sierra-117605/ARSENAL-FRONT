class_name ThirdPersonView
extends CameraView
## 三人称視点（肩越し）：機体の右後ろ上方から、見ている方向を映す。
## 機体が画面のやや左に映り、画面中央の照準が機体に隠れない（SPEC §0.7）。

## この数値は全高 12m の機体を基準にしている（機種で全高が変わると比例させる）
@export var base_machine_height: float = 12.0
## 縮尺の下限（兵士 1.8m でもこの割合までしか寄らない）
@export var min_factor: float = 0.28
## 回転の中心の高さ（機体の足元から。胸〜頭のあたり）
@export var pivot_height: float = 10.4
## 回転の中心からカメラまでの距離
@export var distance: float = 27.2
## カメラを右にずらす量（肩越し）
@export var shoulder_offset: float = 7.6
## カメラが地面に潜らないための最低の高さ
@export var min_camera_height: float = 1.6


func update_camera(camera: Camera3D, target: Node3D, yaw: float, pitch: float) -> void:
	# 機体が大きいほどカメラを引く
	var factor := 1.0
	if target.get("height") != null:
		# 小さい相手（兵士など）でもカメラが近づきすぎないよう下限を設ける
		factor = maxf(float(target.get("height")) / base_machine_height, min_factor)
	var pivot := target.global_position + Vector3(0.0, pivot_height * factor, 0.0)
	var look := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	# 見ている方向の真後ろに下がった位置にカメラを置く
	var pos := pivot + look * Vector3(shoulder_offset * factor, 0.0, distance * factor)
	pos.y = maxf(pos.y, target.global_position.y + min_camera_height)
	camera.global_transform = Transform3D(look, pos)
