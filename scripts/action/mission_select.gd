extends Control
## 任務選択画面（SPEC §0.14）。起動すると最初にこの画面が出る。
## 任務と難易度を選び、「この任務で出撃準備」を押すとガレージへ進む。

const GARAGE_SCENE := "res://scenes/garage.tscn"

var mission_id: String = ""
var difficulty: String = "normal"
var mission_list: ItemList
var difficulty_buttons: Array[Button] = []
var detail_label: RichTextLabel


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var choice := MissionData.load_choice()
	mission_id = str(choice["mission"])
	difficulty = str(choice["difficulty"])
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root_box := VBoxContainer.new()
	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_box.offset_left = 48
	root_box.offset_top = 36
	root_box.offset_right = -48
	root_box.offset_bottom = -36
	root_box.add_theme_constant_override("separation", 14)
	add_child(root_box)

	var title := Label.new()
	title.text = "ARSENAL FRONT ─ 任務選択"
	title.add_theme_font_size_override("font_size", 40)
	root_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "任務と難易度を選んでください。難しいほど敵が多く強く、報酬も増えます。"
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.78, 0.8))
	root_box.add_child(subtitle)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 32)
	root_box.add_child(columns)

	# 左：任務の一覧
	mission_list = ItemList.new()
	mission_list.custom_minimum_size = Vector2(420, 0)
	mission_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for mission in MissionData.all():
		mission_list.add_item(str(mission.get("name", "")))
		if str(mission.get("id", "")) == mission_id:
			mission_list.select(mission_list.item_count - 1)
	mission_list.item_selected.connect(_on_mission_selected)
	columns.add_child(mission_list)

	# 右：難易度と任務の詳細
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)

	var difficulty_row := HBoxContainer.new()
	difficulty_row.add_theme_constant_override("separation", 12)
	right.add_child(difficulty_row)
	var difficulty_label := Label.new()
	difficulty_label.text = "難易度"
	difficulty_label.add_theme_font_size_override("font_size", 22)
	difficulty_row.add_child(difficulty_label)
	for key in MissionData.difficulty_keys():
		var button := Button.new()
		var button_text: String = {"easy": "易", "normal": "中", "hard": "難"}.get(key, key)
		button.text = button_text
		button.custom_minimum_size = Vector2(90, 42)
		button.toggle_mode = true
		button.pressed.connect(_on_difficulty_selected.bind(str(key)))
		button.set_meta("key", key)
		difficulty_buttons.append(button)
		difficulty_row.add_child(button)

	detail_label = RichTextLabel.new()
	detail_label.bbcode_enabled = true
	detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail_label)

	# 下：出撃準備へ
	var bottom := HBoxContainer.new()
	bottom.custom_minimum_size = Vector2(0, 64)
	bottom.add_theme_constant_override("separation", 24)
	root_box.add_child(bottom)
	var go := Button.new()
	go.text = "この任務で出撃準備"
	go.custom_minimum_size = Vector2(280, 56)
	go.add_theme_font_size_override("font_size", 24)
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.22, 0.45, 0.3) if state == "normal" else Color(0.3, 0.6, 0.4)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(10)
		go.add_theme_stylebox_override(state, style)
	go.pressed.connect(_on_go)
	bottom.add_child(go)
	var help := Label.new()
	help.text = "選んだ任務はガレージの「出撃」でそのまま始まります。"
	help.add_theme_color_override("font_color", Color(0.7, 0.73, 0.75))
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(help)


func _on_mission_selected(index: int) -> void:
	var list := MissionData.all()
	if index >= 0 and index < list.size():
		mission_id = str(list[index].get("id", ""))
		_refresh()


func _on_difficulty_selected(key: String) -> void:
	difficulty = key
	_refresh()


## 選んだ内容に合わせて表示を作り直す
func _refresh() -> void:
	for button in difficulty_buttons:
		button.button_pressed = str(button.get_meta("key")) == difficulty
	var setup := MissionData.setup(mission_id, difficulty)
	var kind: String = {
		"annihilate": "殲滅：敵を全機撃破する",
		"defend": "防衛：制限時間まで拠点を守り切る",
		"destroy": "破壊：制限時間内に目標を壊す",
	}.get(str(setup["type"]), "")
	var lines: Array[String] = [
		"[b]%s[/b]（%s）" % [setup["name"], setup["difficulty_name"]],
		str(setup["desc"]),
		"",
		"[b]目標[/b]　　%s" % kind,
		"[b]敵[/b]　　　%d 体（耐久 %d ／ 射撃間隔 %.1f 秒）" % [
			setup["enemy_count"], setup["enemy_hp"], setup["enemy_fire_interval"]],
	]
	if float(setup["time_limit"]) > 0.0:
		lines.append("[b]制限時間[/b]　%.0f 秒" % setup["time_limit"])
	if int(setup["objective_hp"]) > 0:
		lines.append("[b]%s[/b]　耐久 %d" % [
			"守る拠点" if str(setup["type"]) == "defend" else "破壊目標", setup["objective_hp"]])
	lines.append("[b]報酬[/b]　　資材 %d ／ 希少素材 %d（撃破ごとに資材 +60、鹵獲で希少素材 +2）" % [
		setup["materials"], setup["rare"]])
	detail_label.text = "\n".join(lines)


func _on_go() -> void:
	MissionData.save_choice(mission_id, difficulty)
	GameLog.write("任務", "%s（%s）を選択" % [
		MissionData.find(mission_id).get("name", mission_id), difficulty])
	get_tree().change_scene_to_file(GARAGE_SCENE)
