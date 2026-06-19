class_name Missions
extends RefCounted

# Phase 1 任務システム (殲滅のみ・3 難易度)。
# SPEC §2.5 の Phase 1 暫定確定に基づく。
# 敵設計は ENEMY_DESIGNS に固定 (プレイヤーの保存済み設計とは別管理)。

# --- 敵設計カタログ (プレイヤーは編集不可) -----------------------------
const ENEMY_DESIGNS: Dictionary = {
	"enemy_scout": {
		"id": "enemy_scout",
		"name": "敵 偵察車",
		"category": "scout",
		"slots": {
			"hull": "hull_light",
			"main_armament": "gun_30mm_auto",
			"turret": "turret_rws",
			"engine": "engine_high",
			"armor": "armor_light",
			"suspension": "suspension_high_speed",
		},
		"modules": [],
	},
	"enemy_atgm": {
		"id": "enemy_atgm",
		"name": "敵 ATGM 車両",
		"category": "atgm",
		"slots": {
			"hull": "hull_medium",
			"main_armament": "launcher_atgm",
			"turret": "turret_rotary",
			"engine": "engine_standard",
			"armor": "armor_medium",
			"suspension": "suspension_standard",
		},
		"modules": [],
	},
	"enemy_mbt": {
		"id": "enemy_mbt",
		"name": "敵 主力戦車",
		"category": "mbt",
		"slots": {
			"hull": "hull_medium",
			"main_armament": "gun_120mm_smooth",
			"turret": "turret_rotary",
			"engine": "engine_standard",
			"armor": "armor_heavy",
			"suspension": "suspension_standard",
		},
		"modules": [],
	},
}

# --- 任務テンプレ (SPEC §2.5 の暫定表) --------------------------------
const TEMPLATES: Array[Dictionary] = [
	{
		"type": "annihilation",
		"difficulty": "easy",
		"name": "偵察部隊の撃破",
		"enemy_design_ids": ["enemy_scout"],
		"duration_days": 1,
		"reward_funds": 100,
		"reward_materials": 50,
	},
	{
		"type": "annihilation",
		"difficulty": "medium",
		"name": "中隊規模の殲滅",
		"enemy_design_ids": ["enemy_scout", "enemy_atgm"],
		"duration_days": 2,
		"reward_funds": 250,
		"reward_materials": 120,
	},
	{
		"type": "annihilation",
		"difficulty": "hard",
		"name": "重戦力の殲滅",
		"enemy_design_ids": ["enemy_mbt", "enemy_atgm"],
		"duration_days": 3,
		"reward_funds": 500,
		"reward_materials": 250,
	},
]

# 新規任務インスタンスを 1 件生成 (テンプレからランダムに抽選)。
# id にはユニークな識別子を渡す。
static func generate_one(id: String) -> Dictionary:
	var t: Dictionary = TEMPLATES[randi() % TEMPLATES.size()]
	var m: Dictionary = t.duplicate(true)
	m["id"] = id
	return m

# 任務をプレイヤーユニット 1 機 vs 敵チームで解決する。
# 戻り値は Combat.run の結果 Dictionary。
static func resolve(mission: Dictionary, player_unit: Dictionary, catalog: PartsCatalog) -> Dictionary:
	var enemies: Array = []
	var idx: int = 0
	for enemy_did in mission.get("enemy_design_ids", []):
		idx += 1
		var enemy_design: Dictionary = ENEMY_DESIGNS.get(String(enemy_did), {})
		if enemy_design.is_empty():
			continue
		enemies.append(Combat.make_instance(enemy_design, "blue", "e_%d" % idx, catalog))
	# プレイヤーユニットは在庫のものをそのまま使う (side=red にして敵対関係に)
	var player_copy: Dictionary = player_unit.duplicate(true)
	player_copy["side"] = "red"
	# HP は満タンに戻す (出撃時の状態)
	player_copy["hp"] = int(player_copy.get("hp_max", player_copy.get("hp", 0)))
	player_copy["alive"] = true
	return Combat.run([player_copy], enemies)

# 難易度ラベル
static func difficulty_label(d: String) -> String:
	match d:
		"easy": return "易"
		"medium": return "中"
		"hard": return "難"
	return d
