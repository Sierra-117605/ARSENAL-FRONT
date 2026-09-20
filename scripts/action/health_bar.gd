extends Control
## 画面左下に出す自機の耐久バー。
## 文字は英語（Godot の既定フォントに日本語の字が入っていないため）。

## 耐久を表示する相手
@export var target: Pilotable
@export var bar_size: Vector2 = Vector2(320, 26)
@export var margin: Vector2 = Vector2(28, 28)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if target == null:
		return
	var ratio := 0.0
	if target.max_hp > 0:
		ratio = clampf(float(target.hp) / float(target.max_hp), 0.0, 1.0)
	var pos := Vector2(margin.x, size.y - margin.y - bar_size.y)
	# 枠と背景
	draw_rect(Rect2(pos, bar_size), Color(0, 0, 0, 0.45))
	# 残り耐久（多い=緑、少ない=赤）
	var fill := Color(0.3, 0.85, 0.35).lerp(Color(0.9, 0.2, 0.15), 1.0 - ratio)
	draw_rect(Rect2(pos, Vector2(bar_size.x * ratio, bar_size.y)), fill)
	draw_rect(Rect2(pos, bar_size), Color(1, 1, 1, 0.8), false, 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, pos + Vector2(8, bar_size.y - 7), "HP %d / %d" % [target.hp, target.max_hp],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1))
