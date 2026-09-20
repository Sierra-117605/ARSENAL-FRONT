extends Control
## ガレージ画面（SPEC §0.11）。6 つの部位のパーツを選び、性能を見て、「出撃」で戦闘へ。
## 画面の中身はこのスクリプトで組み立てる（部品が多く、後から増えても崩れにくいため）。

## 出撃した時に読み込む戦闘の場面
const FIELD_SCENE := "res://scenes/field_3d.tscn"

## 今選んでいる構成
var loadout: Dictionary = {}
## 今選んでいる機種
var machine_id: String = ""
var machine_picker: OptionButton
var machine_desc: Label
## スロット名 → 選択欄
var pickers: Dictionary = {}
## 選んだパーツの説明を出すラベル
var descriptions: Dictionary = {}
var stats_label: RichTextLabel


func _ready() -> void:
	# ガレージではマウスカーソルを出す（戦闘画面では隠れているため）
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	loadout = LoadoutStore.load_saved()
	machine_id = str(loadout.get("machine_type", RobotParts.default_machine_id()))
	_build_ui()
	_refresh()


## 画面を組み立てる
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root_box := VBoxContainer.new()
	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_box.add_theme_constant_override("separation", 16)
	root_box.offset_left = 48
	root_box.offset_top = 36
	root_box.offset_right = -48
	root_box.offset_bottom = -36
	add_child(root_box)

	var title := Label.new()
	title.text = "ARSENAL FRONT ─ ガレージ"
	title.add_theme_font_size_override("font_size", 40)
	root_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "機種を選び、部位ごとにパーツを選んでください。"
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.78, 0.8))
	root_box.add_child(subtitle)

	# 機種の選択欄（一番上。機種で全高と基礎性能が変わる）
	var machine_row := HBoxContainer.new()
	machine_row.add_theme_constant_override("separation", 16)
	root_box.add_child(machine_row)
	var machine_label := Label.new()
	machine_label.text = "機種"
	machine_label.add_theme_font_size_override("font_size", 24)
	machine_row.add_child(machine_label)
	machine_picker = OptionButton.new()
	machine_picker.custom_minimum_size = Vector2(460, 42)
	var machines := RobotParts.machine_types()
	for i in machines.size():
		machine_picker.add_item(str(machines[i].get("name", "")), i)
		if machines[i].get("id", "") == machine_id:
			machine_picker.select(i)
	machine_picker.item_selected.connect(_on_machine_selected)
	machine_row.add_child(machine_picker)
	machine_desc = Label.new()
	machine_desc.add_theme_color_override("font_color", Color(0.72, 0.75, 0.78))
	machine_row.add_child(machine_desc)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 40)
	root_box.add_child(columns)

	# 左：部位ごとの選択欄（2 列に並べ、画面に収まらない時はスクロールできる）
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for slot in RobotParts.slots():
		grid.add_child(_build_slot_row(slot))

	# 右：性能表示
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	columns.add_child(right)
	var right_box := VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 10)
	right.add_child(right_box)
	var stats_title := Label.new()
	stats_title.text = "この構成の性能"
	stats_title.add_theme_font_size_override("font_size", 26)
	right_box.add_child(stats_title)
	stats_label = RichTextLabel.new()
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_child(stats_label)

	# 下：出撃ボタンと操作説明
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 24)
	root_box.add_child(bottom)
	var sortie := Button.new()
	sortie.text = "出撃"
	sortie.custom_minimum_size = Vector2(200, 56)
	sortie.add_theme_font_size_override("font_size", 28)
	# ボタンだと分かるように色を付ける
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.22, 0.45, 0.3) if state == "normal" else Color(0.3, 0.6, 0.4)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(10)
		sortie.add_theme_stylebox_override(state, style)
	sortie.pressed.connect(_on_sortie)
	bottom.add_child(sortie)
	var help := Label.new()
	help.text = "操作：WASD 移動／マウス カメラ／左クリック 射撃／Esc カーソル／R やり直し／G ガレージへ戻る"
	help.add_theme_color_override("font_color", Color(0.7, 0.73, 0.75))
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(help)


## 1 つの部位ぶんの行（名前・選択欄・説明）
func _build_slot_row(slot: String) -> Control:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = RobotParts.slot_name(slot)
	label.add_theme_font_size_override("font_size", 20)
	box.add_child(label)

	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(300, 38)
	var parts := RobotParts.parts_for(slot)
	for i in parts.size():
		picker.add_item(str(parts[i].get("name", parts[i].get("id", ""))), i)
		if parts[i].get("id", "") == loadout.get(slot, ""):
			picker.select(i)
	picker.item_selected.connect(_on_part_selected.bind(slot))
	box.add_child(picker)
	pickers[slot] = picker

	var desc := Label.new()
	desc.custom_minimum_size = Vector2(300, 22)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", Color(0.68, 0.71, 0.74))
	desc.add_theme_font_size_override("font_size", 16)
	box.add_child(desc)
	descriptions[slot] = desc
	return box


func _on_machine_selected(index: int) -> void:
	var machines := RobotParts.machine_types()
	if index >= 0 and index < machines.size():
		machine_id = str(machines[index].get("id", ""))
		_refresh()


func _on_part_selected(index: int, slot: String) -> void:
	var parts := RobotParts.parts_for(slot)
	if index >= 0 and index < parts.size():
		loadout[slot] = parts[index].get("id", "")
		_refresh()


## 性能表示と説明を今の構成に合わせる
func _refresh() -> void:
	var stats := RobotParts.compute_stats(loadout, machine_id)
	var machine := RobotParts.find_machine(machine_id)
	if machine_desc != null:
		machine_desc.text = "%s ／ 全高 約 %.0fm ／ %s" % [
			str(machine.get("desc", "")), float(machine.get("height", 12.0)),
			"四脚" if str(machine.get("legs", "")) == "quad" else "二脚"]
	for slot in RobotParts.slots():
		var part := RobotParts.find(str(loadout.get(slot, "")))
		descriptions[slot].text = str(part.get("desc", ""))
	var shots := 1.0 / maxf(float(stats["fire_interval"]), 0.01)
	stats_label.text = "\n".join([
		"[b]機種[/b]　　　%s" % stats.get("machine_name", ""),
		"[b]全高[/b]　　　約 %.0f m" % stats.get("height", 12.0),
		"[b]耐久[/b]　　　%d" % stats["max_hp"],
		"[b]歩く速さ[/b]　%.1f m/秒" % stats["walk_speed"],
		"[b]弾の威力[/b]　%d" % stats["damage"],
		"[b]連射[/b]　　　%.2f 秒ごと（毎秒 %.1f 発）" % [stats["fire_interval"], shots],
		"[b]毎秒の火力[/b]　%.0f" % (float(stats["damage"]) * shots),
		"[b]弾の速さ[/b]　%.0f m/秒" % stats["bullet_speed"],
		"[b]照準距離[/b]　%.0f m" % stats["aim_range"],
		"[b]弾のばらつき[/b] %.1f（小さいほど正確）" % stats["spread"],
	])


func _on_sortie() -> void:
	_on_sortie_test()
	get_tree().change_scene_to_file(FIELD_SCENE)


## 出撃時の保存だけを行う（自動テストから呼ぶ。場面は切り替えない）
func _on_sortie_test() -> void:
	loadout["machine_type"] = machine_id
	LoadoutStore.save(loadout)
