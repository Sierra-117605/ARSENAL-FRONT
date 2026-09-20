extends Control
## 画面中央に「勝利」「撃破」を出す表示。
## 文字は英語（Godot の既定フォントに日本語の字が入っていないため）。

## 進行役
@export var battle: Battle

var message: String = ""
var reward_text: String = ""
## 任務名（英数字のみ。日本語は既定フォントに無いため id を使う）
var mission_text: String = ""
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
	if battle != null:
		mission_text = "%s (%s)" % [battle.mission.get("id", ""), battle.mission.get("difficulty", "")]
		reward_text = "materials +%d / rare +%d" % [battle.earned_materials, battle.earned_rare]
		if not battle.earned_blueprints.is_empty():
			var names: Array[String] = []
			for part_id in battle.earned_blueprints:
				names.append(str(RobotParts.find(part_id).get("name", part_id)))
			reward_text += "   /   blueprint: " + ", ".join(names)
	queue_redraw()


func _draw() -> void:
	if message == "":
		return
	var font := ThemeDB.fallback_font
	var center := size / 2.0
	# 見やすいように後ろを暗くする
	draw_rect(Rect2(Vector2(0, center.y - 100), Vector2(size.x, 200)), Color(0, 0, 0, 0.5))
	draw_string(font, Vector2(0, center.y - 46), mission_text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(0.85, 0.88, 0.9))
	draw_string(font, Vector2(0, center.y), message, HORIZONTAL_ALIGNMENT_CENTER, size.x, 72, color)
	draw_string(font, Vector2(0, center.y + 44), reward_text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(1, 0.95, 0.7))
	draw_string(font, Vector2(0, center.y + 78), "press R to retry   /   G for garage",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Color(1, 1, 1, 0.9))
