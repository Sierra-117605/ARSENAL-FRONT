extends Control

# Phase 1 メイン画面 (タブ切り替え)。
# - アセンブル: 保存済み設計の一覧 + 編集 (スロット選択) + リアルタイムステータス
# - 戦闘デモ : 保存済み設計の総当たり 1v1 を自動で実行してログ表示

# 初回起動時に user://designs.json が無い場合に流し込むサンプル設計。
const SEED_DESIGNS: Array[Dictionary] = [
	{
		"id": "design_mbt_alpha",
		"name": "Type-1 MBT (アルファ)",
		"category": "mbt",
		"slots": {
			"hull": "hull_medium",
			"main_armament": "gun_120mm_smooth",
			"turret": "turret_rotary",
			"engine": "engine_standard",
			"armor": "armor_heavy",
			"suspension": "suspension_standard",
		},
		"modules": ["mod_radio", "mod_smoke_launcher"],
	},
	{
		"id": "design_scout_beta",
		"name": "Scout Beta (偵察戦闘車)",
		"category": "scout",
		"slots": {
			"hull": "hull_light",
			"main_armament": "gun_30mm_auto",
			"turret": "turret_rws",
			"engine": "engine_high",
			"armor": "armor_light",
			"suspension": "suspension_high_speed",
		},
		"modules": ["mod_radio", "mod_night_vision"],
	},
	{
		"id": "design_atgm_gamma",
		"name": "ATGM Gamma (対戦車ミサイル車両)",
		"category": "atgm",
		"slots": {
			"hull": "hull_medium",
			"main_armament": "launcher_atgm",
			"turret": "turret_rotary",
			"engine": "engine_standard",
			"armor": "armor_medium",
			"suspension": "suspension_standard",
		},
		"modules": ["mod_radio"],
	},
]

const MAX_BATTLES: int = 6  # 戦闘デモの最大件数 (出力を爆発させない)

# --- ランタイム状態 ---
var catalog: PartsCatalog = null
var saved_designs: Array = []     # 永続化される設計一覧 (Dictionary 配列)
var editing_index: int = 0        # saved_designs のうちどれを編集中か
var editing_design: Dictionary = {} # 編集中のバッファ (保存前)

# UI 参照
var slot_dropdowns: Dictionary = {}    # slot_name -> OptionButton
var stat_value_labels: Dictionary = {} # stat_key -> Label
var weight_value_label: Label = null
var _suppress_signals: bool = false    # UI 再構築中の連鎖イベント抑止

@onready var tabs: TabContainer = $Layout/VBox/Tabs
@onready var design_list: ItemList = $Layout/VBox/Tabs/AssembleTab/HBox/SavedPanel/DesignList
@onready var new_button: Button = $Layout/VBox/Tabs/AssembleTab/HBox/SavedPanel/ButtonsRow/NewButton
@onready var save_button: Button = $Layout/VBox/Tabs/AssembleTab/HBox/SavedPanel/ButtonsRow/SaveButton
@onready var duplicate_button: Button = $Layout/VBox/Tabs/AssembleTab/HBox/SavedPanel/ButtonsRow/DuplicateButton
@onready var delete_button: Button = $Layout/VBox/Tabs/AssembleTab/HBox/SavedPanel/ButtonsRow/DeleteButton
@onready var name_edit: LineEdit = $Layout/VBox/Tabs/AssembleTab/HBox/EditorPanel/NameRow/NameEdit
@onready var slots_container: VBoxContainer = $Layout/VBox/Tabs/AssembleTab/HBox/EditorPanel/SlotsContainer
@onready var stats_container: VBoxContainer = $Layout/VBox/Tabs/AssembleTab/HBox/StatsPanel/StatsContainer
@onready var battle_output: Label = $Layout/VBox/Tabs/BattleTab/Scroll/Output

func _ready() -> void:
	print("[ARSENAL FRONT] boot ok")
	var win_size: Vector2i = DisplayServer.window_get_size()
	var viewport_size: Vector2 = get_viewport_rect().size
	print("[ARSENAL FRONT] window=%dx%d  viewport=%dx%d" % [win_size.x, win_size.y, int(viewport_size.x), int(viewport_size.y)])

	catalog = PartsCatalog.new()
	var loaded: int = catalog.load_all()
	print("[ARSENAL FRONT] parts loaded: %d" % loaded)

	_load_or_seed_designs()
	print("[ARSENAL FRONT] designs loaded: %d (%s)" % [saved_designs.size(), SaveIO.get_designs_absolute_path()])

	tabs.set_tab_title(0, "アセンブル")
	tabs.set_tab_title(1, "戦闘デモ")

	_setup_assembler()
	_run_battles_and_display()

# === セーブ/ロード ====================================================

func _load_or_seed_designs() -> void:
	saved_designs = SaveIO.load_designs()
	if saved_designs.is_empty():
		# 初回起動: SEED_DESIGNS を deep copy して保存
		saved_designs = []
		for d in SEED_DESIGNS:
			saved_designs.append((d as Dictionary).duplicate(true))
		SaveIO.save_designs(saved_designs)
		print("[ARSENAL FRONT] seeded designs (first launch)")

func _persist_and_refresh_battles() -> void:
	SaveIO.save_designs(saved_designs)
	_run_battles_and_display()

# === アセンブル画面 ===================================================

func _setup_assembler() -> void:
	# まず編集対象を1つに固定
	editing_index = 0
	editing_design = (saved_designs[editing_index] as Dictionary).duplicate(true)

	# 信号接続
	name_edit.text_changed.connect(_on_design_name_changed)
	design_list.item_selected.connect(_on_design_list_selected)
	new_button.pressed.connect(_on_new_pressed)
	save_button.pressed.connect(_on_save_pressed)
	duplicate_button.pressed.connect(_on_duplicate_pressed)
	delete_button.pressed.connect(_on_delete_pressed)

	# スロット行・ステータス行を生成 (一度だけ)
	for slot in Unit.FIXED_SLOTS:
		_build_slot_row(String(slot))
	for key in Stats.KEYS:
		_build_stat_row(String(key))
	_build_weight_row()

	_refresh_design_list()
	_load_editing_into_ui()

func _build_slot_row(slot: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label: Label = Label.new()
	label.text = "%s :" % slot
	label.custom_minimum_size = Vector2(130, 0)
	row.add_child(label)

	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var part_ids: Array = catalog.parts_by_slot.get(slot, [])
	for i in part_ids.size():
		var pid: String = String(part_ids[i])
		var pname: String = String(catalog.get_part(pid).get("name", pid))
		option.add_item(pname, i)
		option.set_item_metadata(i, pid)
	option.item_selected.connect(_on_part_selected.bind(slot, option))
	slot_dropdowns[slot] = option
	row.add_child(option)
	slots_container.add_child(row)

func _build_stat_row(key: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = "%s :" % String(Stats.LABELS.get(key, key))
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)
	var value: Label = Label.new()
	value.text = "0"
	value.add_theme_font_size_override("font_size", 16)
	row.add_child(value)
	stat_value_labels[key] = value
	stats_container.add_child(row)

func _build_weight_row() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = "重量合計 :"
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)
	weight_value_label = Label.new()
	weight_value_label.text = "0"
	row.add_child(weight_value_label)
	stats_container.add_child(row)

# editing_design の中身を UI 各所に反映する。
# UI 操作からのイベント連鎖を抑えるため _suppress_signals を立てる。
func _load_editing_into_ui() -> void:
	_suppress_signals = true
	name_edit.text = String(editing_design.get("name", ""))
	var slots: Dictionary = editing_design.get("slots", {})
	for slot in slot_dropdowns:
		var option: OptionButton = slot_dropdowns[slot]
		var current_pid: String = String(slots.get(slot, ""))
		for i in option.item_count:
			if String(option.get_item_metadata(i)) == current_pid:
				option.select(i)
				break
	_suppress_signals = false
	_refresh_stats()

func _refresh_design_list() -> void:
	_suppress_signals = true
	design_list.clear()
	for d in saved_designs:
		var name: String = String(d.get("name", ""))
		var category: String = String(d.get("category", ""))
		design_list.add_item("[%s] %s" % [category, name])
	if editing_index < design_list.item_count:
		design_list.select(editing_index)
	_suppress_signals = false

func _refresh_stats() -> void:
	var stats: Dictionary = Unit.compute_stats(editing_design, catalog)
	for key in Stats.KEYS:
		var k: String = String(key)
		if stat_value_labels.has(k):
			(stat_value_labels[k] as Label).text = str(int(stats.get(k, 0)))
	if weight_value_label != null:
		weight_value_label.text = str(Unit.total_weight(editing_design, catalog))

# --- UI イベントハンドラ -----------------------------------------------

func _on_part_selected(index: int, slot: String, option: OptionButton) -> void:
	if _suppress_signals:
		return
	var pid: String = String(option.get_item_metadata(index))
	if not editing_design.has("slots"):
		editing_design["slots"] = {}
	(editing_design["slots"] as Dictionary)[slot] = pid
	_refresh_stats()

func _on_design_name_changed(new_name: String) -> void:
	if _suppress_signals:
		return
	editing_design["name"] = new_name

func _on_design_list_selected(index: int) -> void:
	if _suppress_signals:
		return
	if index < 0 or index >= saved_designs.size():
		return
	# 編集バッファの未保存変更は破棄される (保存ボタンを押していなければ)
	editing_index = index
	editing_design = (saved_designs[editing_index] as Dictionary).duplicate(true)
	_load_editing_into_ui()

func _on_save_pressed() -> void:
	# 編集バッファを saved_designs に書き戻して永続化
	saved_designs[editing_index] = editing_design.duplicate(true)
	_persist_and_refresh_battles()
	_refresh_design_list()

func _on_new_pressed() -> void:
	# 空の新規設計を作って末尾に追加
	var new_design: Dictionary = {
		"id": _next_design_id(),
		"name": "新規設計",
		"category": "mbt",
		"slots": {
			"hull": "hull_medium",
			"main_armament": "gun_105mm_smooth",
			"turret": "turret_rotary",
			"engine": "engine_standard",
			"armor": "armor_medium",
			"suspension": "suspension_standard",
		},
		"modules": [],
	}
	saved_designs.append(new_design)
	editing_index = saved_designs.size() - 1
	editing_design = new_design.duplicate(true)
	_persist_and_refresh_battles()
	_refresh_design_list()
	_load_editing_into_ui()

func _on_duplicate_pressed() -> void:
	var src: Dictionary = (saved_designs[editing_index] as Dictionary).duplicate(true)
	src["id"] = _next_design_id()
	src["name"] = String(src.get("name", "")) + " (複製)"
	saved_designs.append(src)
	editing_index = saved_designs.size() - 1
	editing_design = src.duplicate(true)
	_persist_and_refresh_battles()
	_refresh_design_list()
	_load_editing_into_ui()

func _on_delete_pressed() -> void:
	if saved_designs.size() <= 1:
		print("[ARSENAL FRONT] cannot delete the last design")
		return
	saved_designs.remove_at(editing_index)
	editing_index = clampi(editing_index, 0, saved_designs.size() - 1)
	editing_design = (saved_designs[editing_index] as Dictionary).duplicate(true)
	_persist_and_refresh_battles()
	_refresh_design_list()
	_load_editing_into_ui()

# 新規 / 複製で使う一意な id 生成。design_NNN 形式の最大値 + 1。
func _next_design_id() -> String:
	var max_num: int = 0
	for d in saved_designs:
		var id: String = String(d.get("id", ""))
		if id.begins_with("design_"):
			var suffix: String = id.substr("design_".length())
			if suffix.is_valid_int():
				var n: int = int(suffix)
				if n > max_num:
					max_num = n
	return "design_%03d" % (max_num + 1)

# === 戦闘デモ画面 (保存済み設計の総当たり 1v1) ==========================

func _run_battles_and_display() -> void:
	var sections: Array[String] = []
	sections.append("===== 保存済み設計 (%d 件) =====" % saved_designs.size())
	for d in saved_designs:
		var stats: Dictionary = Unit.compute_stats(d, catalog)
		var stat_pairs: Array[String] = []
		for k in Stats.KEYS:
			stat_pairs.append("%s=%d" % [Stats.LABELS[k], int(stats[k])])
		sections.append("  [%s] %s  →  %s" % [
			String(d.get("category", "")),
			String(d.get("name", "")),
			"  ".join(stat_pairs),
		])

	if saved_designs.size() < 2:
		sections.append("")
		sections.append("(戦闘デモには 2 つ以上の設計が必要です)")
		battle_output.text = "\n".join(sections)
		return

	# 総当たり (i, j) ペアを最大 MAX_BATTLES 件まで生成
	var pairs: Array = []
	for i in range(saved_designs.size()):
		for j in range(i + 1, saved_designs.size()):
			pairs.append([i, j])
			if pairs.size() >= MAX_BATTLES:
				break
		if pairs.size() >= MAX_BATTLES:
			break

	sections.append("")
	sections.append("===== 戦闘サマリ (1v1 総当たり、最大 %d 件) =====" % MAX_BATTLES)
	var battle_results: Array = []
	var n: int = 0
	for pair in pairs:
		n += 1
		var red_design: Dictionary = saved_designs[pair[0]]
		var blue_design: Dictionary = saved_designs[pair[1]]
		var label: String = "%s vs %s" % [String(red_design.get("name", "")), String(blue_design.get("name", ""))]
		var red_unit: Dictionary = Combat.make_instance(red_design, "red", "R%d_1" % n, catalog)
		var blue_unit: Dictionary = Combat.make_instance(blue_design, "blue", "B%d_1" % n, catalog)
		var result: Dictionary = Combat.run([red_unit], [blue_unit])
		battle_results.append({ "label": label, "result": result, "n": n })
		sections.append("  #%d  %s  →  %s  (%d ラウンド)" % [
			n, label,
			Combat.winner_label(String(result.get("winner", ""))),
			int(result.get("round", 0)),
		])

	sections.append("")
	sections.append("===== 戦闘詳細ログ =====")
	for br in battle_results:
		var res: Dictionary = br.get("result", {})
		sections.append("")
		sections.append("--- 戦闘 #%d: %s ---" % [int(br.get("n", 0)), String(br.get("label", ""))])
		sections.append(Combat.format_log(res.get("log", [])))

	battle_output.text = "\n".join(sections)
