class_name CameraView
extends Node
## 視点の共通土台（SPEC §0.3-3）。CameraRig の子として置く。
## 三人称・コックピットなど、視点ごとに継承して update_camera を書く。

## 画面に表示する視点の名前（切り替え UI 用）
@export var view_name: String = ""


## カメラの位置と向きを決める。yaw/pitch は見ている方向（ラジアン）
func update_camera(_camera: Camera3D, _target: Node3D, _yaw: float, _pitch: float) -> void:
	pass
