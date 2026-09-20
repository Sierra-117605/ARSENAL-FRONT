extends Control
## 照準マーク（十字＋中心の点）。ふだんは画面の中央。
## 航空機に乗っている間だけ、弾が実際に飛んで行く先（機首の正面）に重ねる。

@export var color: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var arm_length: float = 10.0
@export var gap: float = 4.0
## プレイヤーの乗員（航空機に乗っているか調べる）
@export var occupant: Occupant
## カメラ土台（画面のどこに当たるか計算する）
@export var camera_rig: CameraRig

## 今の照準の位置（画面の座標）
var mark_position: Vector2 = Vector2.ZERO


func _process(_delta: float) -> void:
	var wanted := _aircraft_mark()
	if wanted != mark_position:
		mark_position = wanted
		queue_redraw()


## 航空機に乗っている時の照準の位置。乗っていなければ画面中央
func _aircraft_mark() -> Vector2:
	if occupant == null or camera_rig == null or camera_rig.camera == null:
		return size / 2.0
	var plane := occupant.get_vehicle() as Aircraft
	if plane == null:
		return size / 2.0
	var aim := Pilotable.aim_point(plane.control)
	if aim == Vector3.ZERO or camera_rig.camera.is_position_behind(aim):
		return size / 2.0
	return camera_rig.camera.unproject_position(aim)


func _draw() -> void:
	var c := mark_position if mark_position != Vector2.ZERO else size / 2.0
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * gap, c + d * (gap + arm_length), color, 2.0)
	draw_circle(c, 1.5, color)
