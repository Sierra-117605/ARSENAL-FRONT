extends Control

# Phase 1 メイン画面 (タブ切り替え)。
# - アセンブル: 6 固定スロットを OptionButton で選び、ステータスをリアルタイム更新
# - 戦闘デモ: 既存の 3 通り 1v1 自動戦闘ログを表示

# --- 戦闘デモ用の固定設計と対戦カード ---
const DEMO_UNITS: Array[Dictionary] = [
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

const BATTLES: Array[Dictionary] = [
	{ "label": "MBT vs ATGM",   "red": ["design_mbt_alpha"],  "blue": ["design_atgm_gamma"] },
	{ "label": "MBT vs Scout",  "red": ["design_mbt_alpha"],  "blue": ["design_scout_beta"] },
	{ "label": "ATGM vs Scout", "red": ["design_atgm_gamma"], "blue": ["design_scout_beta"] },
]

# --- アセンブル画面の状態 ---
var catalog: PartsCatalog = null
var editing_design: Dictionary = {}
var slot_dropdowns: Dictionary = {}   # slot_name -> OptionButton
var stat_value_labels: Dictionary = {} # stat_key -> Label
var weight_value_label: Label = null

@onready var tabs: TabContainer = $Layout/VBox/Tabs
@onready var name_edit: LineEdit = $Layout/VBox/Tabs/AssembleTab/HBox/LeftPanel/NameRow/NameEdit
@onready var slots_container: VBoxContainer = $Layout/VBox/Tabs/AssembleTab/HBox/LeftPanel/SlotsContainer
@onready var stats_container: VBoxContainer = $Layout/VBox/Tabs/AssembleTab/HBox/RightPanel/StatsContainer
@onready var battle_output: Label = $Layout/VBox/Tabs/BattleTab/Scroll/Output

func _ready() -> void:
	print("[ARSENAL FRONT] boot ok")
	var win_size: Vector2i = DisplayServer.window_get_size()
	var viewport_size: Vector2 = get_viewport_rect().size
	print("[ARSENAL FRONT] window=%dx%d  viewport=%dx%d" % [win_size.x, win_size.y, int(viewport_size.x), int(viewport_size.y)])

	catalog = PartsCatalog.new()
	var loaded: int = catalog.load_all()
	print("[ARSENAL FRONT] parts loaded: %d" % loaded)

	tabs.set_tab_title(0, "アセンブル")
	tabs.set_tab_title(1, "戦闘デモ")

	_setup_assembler()
	_run_battles_and_display()

# === アセンブル画面 (T5-A) ===

func _setup_assembler() -> void:
	# 初期は MBT alpha をベースに編集開始 (DEMO_UNITS[0] のコピー)
	editing_design = (DEMO_UNITS[0] as Dictionary).duplicate(true)
	name_edit.text = String(editing_design.get("name", "新規設計"))
	name_edit.text_changed.connect(_on_design_name_changed)

	for slot in Unit.FIXED_SLOTS:
		_build_slot_row(String(slot))

	for key in Stats.KEYS:
		_build_stat_row(String(key))
	_build_weight_row()

	_refresh_stats()

func _build_slot_row(slot: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label: Label = Label.new()
	label.text = "%s :" % slot
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)

	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var part_ids: Array = catalog.parts_by_slot.get(slot, [])
	for i in part_ids.size():
		var pid: String = String(part_ids[i])
		var pname: String = String(catalog.get_part(pid).get("name", pid))
		option.add_item(pname, i)
		option.set_item_metadata(i, pid)
	var current_pid: String = String((editing_design.get("slots", {}) as Dictionary).get(slot, ""))
	for i in option.item_count:
		if String(option.get_item_metadata(i)) == current_pid:
			option.select(i)
			break
	option.item_selected.connect(_on_part_selected.bind(slot, option))
	slot_dropdowns[slot] = option
	row.add_child(option)
	slots_container.add_child(row)

func _build_stat_row(key: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = "%s :" % String(Stats.LABELS.get(key, key))
	label.custom_minimum_size = Vector2(160, 0)
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
	label.custom_minimum_size = Vector2(160, 0)
	row.add_child(label)
	weight_value_label = Label.new()
	weight_value_label.text = "0"
	row.add_child(weight_value_label)
	stats_container.add_child(row)

func _on_part_selected(index: int, slot: String, option: OptionButton) -> void:
	var pid: String = String(option.get_item_metadata(index))
	if not editing_design.has("slots"):
		editing_design["slots"] = {}
	(editing_design["slots"] as Dictionary)[slot] = pid
	_refresh_stats()

func _on_design_name_changed(new_name: String) -> void:
	editing_design["name"] = new_name

func _refresh_stats() -> void:
	var stats: Dictionary = Unit.compute_stats(editing_design, catalog)
	for key in Stats.KEYS:
		var k: String = String(key)
		if stat_value_labels.has(k):
			(stat_value_labels[k] as Label).text = str(int(stats.get(k, 0)))
	if weight_value_label != null:
		weight_value_label.text = str(Unit.total_weight(editing_design, catalog))

# === 戦闘デモ画面 (既存の T6) ===

func _run_battles_and_display() -> void:
	var design_by_id: Dictionary = {}
	for d in DEMO_UNITS:
		design_by_id[String(d.get("id", ""))] = d

	var sections: Array[String] = []
	sections.append("===== 設計 (3区分) =====")
	for design in DEMO_UNITS:
		var stats: Dictionary = Unit.compute_stats(design, catalog)
		var stat_pairs: Array[String] = []
		for k in Stats.KEYS:
			stat_pairs.append("%s=%d" % [Stats.LABELS[k], int(stats[k])])
		sections.append("  [%s] %s  →  %s" % [
			String(design.get("category", "")),
			String(design.get("name", "")),
			"  ".join(stat_pairs),
		])

	var battle_results: Array = []
	var n: int = 0
	for battle in BATTLES:
		n += 1
		var red_units: Array = _build_team(battle.get("red", []), "red", n, design_by_id)
		var blue_units: Array = _build_team(battle.get("blue", []), "blue", n, design_by_id)
		var result: Dictionary = Combat.run(red_units, blue_units)
		battle_results.append({ "label": String(battle.get("label", "")), "result": result, "n": n })

	sections.append("")
	sections.append("===== 戦闘サマリ =====")
	for br in battle_results:
		var res: Dictionary = br.get("result", {})
		sections.append("  #%d  %s  →  %s  (%d ラウンド)" % [
			int(br.get("n", 0)),
			String(br.get("label", "")),
			Combat.winner_label(String(res.get("winner", ""))),
			int(res.get("round", 0)),
		])

	sections.append("")
	sections.append("===== 戦闘詳細ログ =====")
	for br in battle_results:
		var res: Dictionary = br.get("result", {})
		sections.append("")
		sections.append("--- 戦闘 #%d: %s ---" % [int(br.get("n", 0)), String(br.get("label", ""))])
		sections.append(Combat.format_log(res.get("log", [])))

	battle_output.text = "\n".join(sections)

func _build_team(design_ids: Array, side: String, battle_n: int, design_by_id: Dictionary) -> Array:
	var units: Array = []
	var idx: int = 0
	for did in design_ids:
		idx += 1
		var design: Dictionary = design_by_id.get(String(did), {})
		if design.is_empty():
			continue
		var instance_id: String = "%s%d_%d" % [side.substr(0, 1).to_upper(), battle_n, idx]
		units.append(Combat.make_instance(design, side, instance_id, catalog))
	return units
