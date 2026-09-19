extends Control
## 画面中央の照準マーク（十字＋中心の点）。

@export var color: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var arm_length: float = 10.0
@export var gap: float = 4.0


func _draw() -> void:
	var c := size / 2.0
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * gap, c + d * (gap + arm_length), color, 2.0)
	draw_circle(c, 1.5, color)
