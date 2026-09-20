class_name ChaseView
extends CameraView
## 航空機用の視点：機体の真後ろから、機体の向いている方を映す。
## 機体が傾くとカメラも少しだけ一緒に傾くので、旋回している感じが出る（エースコンバット風）。

## 機体の後ろに下がる距離（メートル）
@export var distance: float = 34.0
## 機体より上に上げる高さ
@export var above: float = 9.0
## 機体の前方どのくらい先を見るか
@export var look_ahead: float = 120.0
## 機体の傾きをどれだけ真似るか（0＝いつも水平、1＝機体と同じだけ傾く）
@export var roll_follow: float = 0.45


func update_camera(camera: Camera3D, target: Node3D, _yaw: float, _pitch: float) -> void:
	var basis := target.global_transform.basis
	var forward: Vector3 = -basis.z
	# カメラの「上」は、水平と機体の傾きの中間にする
	var up: Vector3 = Vector3.UP.lerp(basis.y, roll_follow)
	if up.length() < 0.01:
		up = Vector3.UP
	up = up.normalized()
	var pos: Vector3 = target.global_position - forward * distance + up * above
	var look_at: Vector3 = target.global_position + forward * look_ahead
	camera.look_at_from_position(pos, look_at, up)
