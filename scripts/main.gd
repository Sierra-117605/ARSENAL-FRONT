extends Control

# Phase 1 の起点シーン。
# 今は T2 系の検証として、3 つの戦車設計 (MBT / 偵察 / ATGM) の
# 5 項目ステータスを画面に表示する。
# 全体は Control + アンカーでウィンドウサイズに追従する (Node2D 絶対座標は使わない)。

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

@onready var output_label: Label = $Layout/VBox/OutputScroll/Output

func _ready() -> void:
	print("[ARSENAL FRONT] boot ok")
	# 画面サイズ診断用 (出力ログで実際のサイズを確認する)
	var win_size: Vector2i = DisplayServer.window_get_size()
	var viewport_size: Vector2 = get_viewport_rect().size
	print("[ARSENAL FRONT] window=%dx%d  viewport=%dx%d" % [win_size.x, win_size.y, int(viewport_size.x), int(viewport_size.y)])
	var catalog: PartsCatalog = PartsCatalog.new()
	var loaded: int = catalog.load_all()
	print("[ARSENAL FRONT] parts loaded: %d" % loaded)

	var blocks: Array[String] = []
	for design in DEMO_UNITS:
		var stats: Dictionary = Unit.compute_stats(design, catalog)
		var weight: int = Unit.total_weight(design, catalog)
		var stat_pairs: Array[String] = []
		for k in Stats.KEYS:
			stat_pairs.append("%s=%d" % [Stats.LABELS[k], int(stats[k])])
		var block: String = "%s\n    ステータス      : %s\n    重量合計         : %d" % [
			Unit.describe(design, catalog),
			"  /  ".join(stat_pairs),
			weight,
		]
		blocks.append(block)

	var output_text: String = "\n\n".join(blocks)
	print("--- demo units ---")
	print(output_text)
	if output_label:
		output_label.text = output_text
