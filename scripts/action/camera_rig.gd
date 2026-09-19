class_name CameraRig
extends Node3D
## 追いかけカメラの土台。追う対象の位置に毎フレーム移動する。
## 子に置いた Camera3D が、この土台からの相対位置で機体を映す。
## （N1-3 で視点の差し替え＝三人称／将来のコックピットの仕組みを入れる）

## 追いかける対象
@export var target: Node3D


func _process(_delta: float) -> void:
	if target != null:
		global_position = target.global_position
