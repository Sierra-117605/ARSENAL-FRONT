extends Control

# Phase 1 の起点シーン。
# 今は T2/T6 の検証として、3 つの戦車設計を表示しつつ
# 3 通りの 1v1 自動戦闘を実行して結果ログを画面に出す。
# 全体は Control + アンカーでウィンドウサイズに追従する。

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

# Phase 1 戦闘デモ: 3 つの 1v1 で区分の特徴がどう出るか確認する。
const BATTLES: Array[Dictionary] = [
	{ "label": "MBT vs ATGM",     "red": ["design_mbt_alpha"],   "blue": ["design_atgm_gamma"] },
	{ "label": "MBT vs Scout",    "red": ["design_mbt_alpha"],   "blue": ["design_scout_beta"] },
	{ "label": "ATGM vs Scout",   "red": ["design_atgm_gamma"],  "blue": ["design_scout_beta"] },
]

@onready var output_label: Label = $Layout/VBox/OutputScroll/Output

func _ready() -> void:
	print("[ARSENAL FRONT] boot ok")
	var win_size: Vector2i = DisplayServer.window_get_size()
	var viewport_size: Vector2 = get_viewport_rect().size
	print("[ARSENAL FRONT] window=%dx%d  viewport=%dx%d" % [win_size.x, win_size.y, int(viewport_size.x), int(viewport_size.y)])

	var catalog: PartsCatalog = PartsCatalog.new()
	var loaded: int = catalog.load_all()
	print("[ARSENAL FRONT] parts loaded: %d" % loaded)

	var design_by_id: Dictionary = {}
	for d in DEMO_UNITS:
		design_by_id[String(d.get("id", ""))] = d

	var sections: Array[String] = []

	# --- 設計セクション ---
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

	# --- 戦闘実行 ---
	var battle_results: Array = []
	var n: int = 0
	for battle in BATTLES:
		n += 1
		var red_units: Array = _build_team(battle.get("red", []), "red", n, design_by_id, catalog)
		var blue_units: Array = _build_team(battle.get("blue", []), "blue", n, design_by_id, catalog)
		var result: Dictionary = Combat.run(red_units, blue_units)
		battle_results.append({
			"label": String(battle.get("label", "")),
			"result": result,
			"n": n,
		})

	# --- 戦闘サマリ ---
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

	# --- 戦闘詳細ログ ---
	sections.append("")
	sections.append("===== 戦闘詳細ログ =====")
	for br in battle_results:
		var res: Dictionary = br.get("result", {})
		sections.append("")
		sections.append("--- 戦闘 #%d: %s ---" % [int(br.get("n", 0)), String(br.get("label", ""))])
		sections.append(Combat.format_log(res.get("log", [])))

	var output_text: String = "\n".join(sections)
	print("--- demo output ---")
	print(output_text)
	if output_label:
		output_label.text = output_text

func _build_team(design_ids: Array, side: String, battle_n: int, design_by_id: Dictionary, catalog: PartsCatalog) -> Array:
	var units: Array = []
	var idx: int = 0
	for did in design_ids:
		idx += 1
		var design: Dictionary = design_by_id.get(String(did), {})
		if design.is_empty():
			push_warning("[main] 未知の設計ID: " + String(did))
			continue
		var instance_id: String = "%s%d_%d" % [side.substr(0, 1).to_upper(), battle_n, idx]
		units.append(Combat.make_instance(design, side, instance_id, catalog))
	return units
