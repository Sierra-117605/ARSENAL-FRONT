extends Control
## 画面中央に「勝利」「撃破」を出す表示。
## 文字は英語（Godot の既定フォントに日本語の字が入っていないため）。

## 進行役
@export var battle: Battle

var message: String = ""
var color: Color = Color.WHITE


func _ready() -> void:
	if battle != null:
		battle.finished.connect(_on_finished)


func _on_finished(result: String) -> void:
	if result == "win":
		message = "VICTORY"
		color = Color(0.5, 1.0, 0.6)
	else:
		message = "DESTROYED"
		color = Color(1.0, 0.45, 0.4)
	queue_redraw()


func _draw() -> void:
	if message == "":
		return
	var font := ThemeDB.fallback_font
	var center := size / 2.0
	# 見やすいように後ろを暗くする
	draw_rect(Rect2(Vector2(0, center.y - 90), Vector2(size.x, 180)), Color(0, 0, 0, 0.5))
	draw_string(font, Vector2(0, center.y), message, HORIZONTAL_ALIGNMENT_CENTER, size.x, 72, color)
	draw_string(font, Vector2(0, center.y + 52), "press R to retry",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 28, Color(1, 1, 1, 0.9))
