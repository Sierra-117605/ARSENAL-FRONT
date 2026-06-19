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
var game_state: GameState = null  # 司令官モードのゲーム状態

# UI 参照
var slot_dropdowns: Dictionary = {}    # slot_name -> OptionButton
var stat_value_labels: Dictionary = {} # stat_key -> Label
var weight_value_label: Label = null
var _suppress_signals: bool = false    # UI 再構築中の連鎖イベント抑止

@onready var tabs: TabContainer = $Layout/VBox/Tabs

# 司令官タブ
@onready var commander_day_label: Label = $Layout/VBox/Tabs/CommanderTab/VBox/Header/DayLabel
@onready var commander_funds_label: Label = $Layout/VBox/Tabs/CommanderTab/VBox/Header/FundsLabel
@onready var commander_materials_label: Label = $Layout/VBox/Tabs/CommanderTab/VBox/Header/MaterialsLabel
@onready var commander_design_selector: OptionButton = $Layout/VBox/Tabs/CommanderTab/VBox/Main/ProductionPanel/DesignRow/DesignSelector
@onready var commander_cost_label: Label = $Layout/VBox/Tabs/CommanderTab/VBox/Main/ProductionPanel/CostLabel
@onready var commander_produce_button: Button = $Layout/VBox/Tabs/CommanderTab/VBox/Main/ProductionPanel/ProduceButton
@onready var commander_inventory_list: ItemList = $Layout/VBox/Tabs/CommanderTab/VBox/Main/ProductionPanel/InventoryList
@onready var commander_next_day_button: Button = $Layout/VBox/Tabs/CommanderTab/VBox/Footer/NextDayButton

# 司令官タブ (任務エリア)
@onready var available_list: ItemList = $Layout/VBox/Tabs/CommanderTab/VBox/Main/MissionPanel/AvailableList
@onready var dispatch_unit_selector: OptionButton = $Layout/VBox/Tabs/CommanderTab/VBox/Main/MissionPanel/DispatchRow/DispatchUnitSelector
@onready var dispatch_button: Button = $Layout/VBox/Tabs/CommanderTab/VBox/Main/MissionPanel/DispatchRow/DispatchButton
@onready var active_list: ItemList = $Layout/VBox/Tabs/CommanderTab/VBox/Main/MissionPanel/ActiveList
@onready var mission_log_text: Label = $Layout/VBox/Tabs/CommanderTab/VBox/Main/MissionPanel/LogScroll/LogText

# アセンブルタブ
@onready var design_list: ItemList = $Layout/VBox/Tabs/AssembleTab/HBox/SavedPanel/DesignList
@onready var new_button: Button = $Layout/VBox/Tabs/AssembleTab/HBox/SavedPanel/ButtonsRow/NewButton
@onready var save_button: Button = $Layout/VBox/Tabs/AssembleTab/HBox/SavedPanel/ButtonsRow/SaveButton
@onready var duplicate_button: Button = $Layout/VBox/Tabs/AssembleTab/HBox/SavedPanel/ButtonsRow/DuplicateButton
@onready var delete_button: Button = $Layout/VBox/Tabs/AssembleTab/HBox/SavedPanel/ButtonsRow/DeleteButton
@onready var name_edit: LineEdit = $Layout/VBox/Tabs/AssembleTab/HBox/EditorPanel/NameRow/NameEdit
@onready var slots_container: VBoxContainer = $Layout/VBox/Tabs/AssembleTab/HBox/EditorPanel/SlotsContainer
@onready var stats_container: VBoxContainer = $Layout/VBox/Tabs/AssembleTab/HBox/StatsPanel/StatsContainer

# 戦闘デモタブ
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

	game_state = GameState.new()
	if game_state.load_from():
		print("[ARSENAL FRONT] gamestate loaded (Day %d, funds %d, materials %d, inventory %d)" % [game_state.day(), game_state.funds(), game_state.materials(), game_state.inventory().size()])
	else:
		game_state.save_to()
		print("[ARSENAL FRONT] gamestate created (default, %s)" % GameState.get_save_absolute_path())

	tabs.set_tab_title(0, "司令官")
	tabs.set_tab_title(1, "アセンブル")
	tabs.set_tab_title(2, "戦闘デモ")

	_setup_assembler()
	_setup_commander()
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
	# 設計が変わったら司令官タブの設計セレクタも更新
	if commander_design_selector != null:
		_populate_commander_design_selector()
		_refresh_commander_display()

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

# === 司令官モード (T7-1/2/4) ============================================

func _setup_commander() -> void:
	_populate_commander_design_selector()
	commander_design_selector.item_selected.connect(_on_commander_design_changed)
	commander_produce_button.pressed.connect(_on_produce_pressed)
	commander_next_day_button.pressed.connect(_on_next_day_pressed)
	dispatch_button.pressed.connect(_on_dispatch_pressed)
	available_list.item_selected.connect(_on_available_mission_selected)
	# 起動時に受注可能任務が無ければ 3 件補充
	if game_state.available_missions().is_empty():
		_replenish_available_missions(3)
		game_state.save_to()
	_refresh_commander_display()

func _populate_commander_design_selector() -> void:
	commander_design_selector.clear()
	for i in saved_designs.size():
		var d: Dictionary = saved_designs[i]
		commander_design_selector.add_item("[%s] %s" % [String(d.get("category", "")), String(d.get("name", ""))], i)
	if saved_designs.size() > 0:
		commander_design_selector.select(0)

func _refresh_commander_display() -> void:
	commander_day_label.text = "Day %d" % game_state.day()
	commander_funds_label.text = "資金: %d" % game_state.funds()
	commander_materials_label.text = "素材: %d" % game_state.materials()

	# 製造コスト表示と「製造する」ボタンの有効/無効
	var sel_idx: int = commander_design_selector.selected
	if sel_idx >= 0 and sel_idx < saved_designs.size():
		var design: Dictionary = saved_designs[sel_idx]
		var weight: int = Unit.total_weight(design, catalog)
		var cost: Dictionary = GameState.production_cost_for(weight)
		commander_cost_label.text = "重量 %d  →  製造コスト: 資金 %d / 素材 %d" % [
			weight, int(cost.get("funds", 0)), int(cost.get("materials", 0)),
		]
		commander_produce_button.disabled = not game_state.can_afford(cost)
	else:
		commander_cost_label.text = "(設計が選択されていません)"
		commander_produce_button.disabled = true

	# 在庫リスト
	commander_inventory_list.clear()
	var inv: Array = game_state.inventory()
	for unit in inv:
		var u: Dictionary = unit
		var line: String = "%s  (Day %d 製造)" % [
			String(u.get("name", "?")),
			int(u.get("produced_day", 0)),
		]
		commander_inventory_list.add_item(line)

	# 任務エリア更新
	_refresh_missions_display()

func _on_commander_design_changed(_idx: int) -> void:
	_refresh_commander_display()

func _on_produce_pressed() -> void:
	var sel_idx: int = commander_design_selector.selected
	if sel_idx < 0 or sel_idx >= saved_designs.size():
		return
	var design: Dictionary = saved_designs[sel_idx]
	var weight: int = Unit.total_weight(design, catalog)
	var cost: Dictionary = GameState.production_cost_for(weight)
	if not game_state.can_afford(cost):
		return

	# 資源消費 + 在庫追加 をイベントで適用
	game_state.apply({ "type": "add_funds", "delta": -int(cost.get("funds", 0)) })
	game_state.apply({ "type": "add_materials", "delta": -int(cost.get("materials", 0)) })

	# 製造ユニットを Combat.make_instance 形式で生成 (戦闘でそのまま使える形)
	var unit_id: String = "u_d%d_%03d" % [game_state.day(), game_state.inventory().size() + 1]
	var instance: Dictionary = Combat.make_instance(design, "player", unit_id, catalog)
	instance["produced_day"] = game_state.day()
	game_state.apply({ "type": "produce_unit", "unit": instance })

	game_state.save_to()
	_refresh_commander_display()
	print("[ARSENAL FRONT] produced %s (Day %d)" % [String(instance.get("name", "")), game_state.day()])

func _on_next_day_pressed() -> void:
	game_state.apply({ "type": "advance_day", "days": 1 })
	# 日進行で解決日に達した任務を自動戦闘で解決
	_resolve_due_missions()
	# 受注可能が枯れていたら補充
	if game_state.available_missions().size() < 3:
		_replenish_available_missions(3 - game_state.available_missions().size())
	game_state.save_to()
	_refresh_commander_display()

# === 任務システム (T7-3) ================================================

func _replenish_available_missions(count: int) -> void:
	for i in count:
		var mid: String = "m_d%d_%03d" % [game_state.day(), randi() % 1000]
		var mission: Dictionary = Missions.generate_one(mid)
		game_state.apply({ "type": "add_available_mission", "mission": mission })

func _refresh_missions_display() -> void:
	# 受注可能リスト
	available_list.clear()
	for m in game_state.available_missions():
		var md: Dictionary = m
		var line: String = "[%s] %s  (%d 日)  報酬: 資金 %d / 素材 %d" % [
			Missions.difficulty_label(String(md.get("difficulty", ""))),
			String(md.get("name", "?")),
			int(md.get("duration_days", 0)),
			int(md.get("reward_funds", 0)),
			int(md.get("reward_materials", 0)),
		]
		available_list.add_item(line)

	# 派遣機体セレクタ
	dispatch_unit_selector.clear()
	for i in game_state.inventory().size():
		var u: Dictionary = game_state.inventory()[i]
		dispatch_unit_selector.add_item(String(u.get("name", "?")), i)
	if game_state.inventory().size() > 0:
		dispatch_unit_selector.select(0)

	# 派遣ボタンの活性条件: 任務が選ばれていて、派遣可能ユニットがいる
	dispatch_button.disabled = (
		available_list.get_selected_items().size() == 0
		or game_state.inventory().size() == 0
	)

	# 派遣中リスト
	active_list.clear()
	for entry in game_state.active_missions():
		var ed: Dictionary = entry
		var m2: Dictionary = ed.get("mission", {})
		var u2: Dictionary = ed.get("unit", {})
		var line2: String = "[%s] %s  (%s)  Day %d 帰還" % [
			Missions.difficulty_label(String(m2.get("difficulty", ""))),
			String(m2.get("name", "?")),
			String(u2.get("name", "?")),
			int(ed.get("return_day", 0)),
		]
		active_list.add_item(line2)

	# 任務結果ログ
	var log_lines: Array[String] = []
	for entry2 in game_state.mission_log():
		var le: Dictionary = entry2
		log_lines.append(String(le.get("text", "")))
	if log_lines.is_empty():
		mission_log_text.text = "(まだ任務結果はありません)"
	else:
		mission_log_text.text = "\n".join(log_lines)

func _on_available_mission_selected(_idx: int) -> void:
	dispatch_button.disabled = (game_state.inventory().size() == 0)

func _on_dispatch_pressed() -> void:
	var sel_missions: PackedInt32Array = available_list.get_selected_items()
	if sel_missions.size() == 0:
		return
	var mission_idx: int = sel_missions[0]
	var avail: Array = game_state.available_missions()
	if mission_idx >= avail.size():
		return
	var mission: Dictionary = avail[mission_idx]

	var unit_sel: int = dispatch_unit_selector.selected
	var inv: Array = game_state.inventory()
	if unit_sel < 0 or unit_sel >= inv.size():
		return
	var unit: Dictionary = inv[unit_sel]

	game_state.apply({
		"type": "dispatch_mission",
		"mission": mission,
		"unit": unit,
		"dispatch_day": game_state.day(),
	})
	game_state.save_to()
	_refresh_commander_display()

# active_missions のうち return_day を迎えたものを自動戦闘で解決する。
func _resolve_due_missions() -> void:
	var active_snapshot: Array = game_state.active_missions().duplicate()
	for entry in active_snapshot:
		var ed: Dictionary = entry
		if game_state.day() < int(ed.get("return_day", 0)):
			continue
		var mission: Dictionary = ed.get("mission", {})
		var unit: Dictionary = ed.get("unit", {})
		var result: Dictionary = Missions.resolve(mission, unit, catalog)
		var winner: String = String(result.get("winner", ""))
		var won: bool = (winner == "red")
		var reward_funds: int = int(mission.get("reward_funds", 0)) if won else 0
		var reward_materials: int = int(mission.get("reward_materials", 0)) if won else 0

		if reward_funds > 0:
			game_state.apply({ "type": "add_funds", "delta": reward_funds })
		if reward_materials > 0:
			game_state.apply({ "type": "add_materials", "delta": reward_materials })

		var verdict: String = "勝利" if won else "敗北"
		var text: String = "Day %d  [%s] %s (%s)  → %s  | %s  報酬: 資金 +%d / 素材 +%d" % [
			game_state.day(),
			Missions.difficulty_label(String(mission.get("difficulty", ""))),
			String(mission.get("name", "?")),
			String(unit.get("name", "?")),
			verdict,
			Combat.winner_label(winner),
			reward_funds, reward_materials,
		]
		game_state.apply({
			"type": "complete_mission",
			"mission_id": String(mission.get("id", "")),
			"log_entry": { "text": text, "result": result, "day": game_state.day() },
		})
		print("[ARSENAL FRONT] mission completed: " + text)
