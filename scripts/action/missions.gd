class_name MissionData
extends RefCounted
## 任務一覧（data/missions.json）を読む（SPEC §0.14）。
## 選んだ任務と難易度は user://mission.json に覚えておき、戦場がそれを読んで組み立てる。

const DATA_PATH := "res://data/missions.json"
const CHOICE_PATH := "user://mission.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(DATA_PATH)
		var parsed: Variant = JSON.parse_string(text)
		_data = parsed if parsed is Dictionary else {}
	return _data


## 任務の一覧
static func all() -> Array:
	return data().get("missions", [])


## id から任務を探す（無ければ最初の任務）
static func find(mission_id: String) -> Dictionary:
	for mission in all():
		if mission.get("id", "") == mission_id:
			return mission
	var list := all()
	return list[0] if not list.is_empty() else {}


## 難易度の並び（易・中・難）
static func difficulty_keys() -> Array:
	return ["easy", "normal", "hard"]


## 任務＋難易度の設定をまとめて返す
static func setup(mission_id: String, difficulty: String) -> Dictionary:
	var mission := find(mission_id)
	var levels: Dictionary = mission.get("difficulties", {})
	var level: Dictionary = levels.get(difficulty, levels.get("normal", {}))
	return {
		"id": str(mission.get("id", "")),
		"name": str(mission.get("name", "")),
		"type": str(mission.get("type", "annihilate")),
		"desc": str(mission.get("desc", "")),
		"difficulty": difficulty,
		"difficulty_name": str(level.get("name", difficulty)),
		"objective_hp": int(mission.get("objective_hp", 0)),
		"enemy_count": int(level.get("enemy_count", 3)),
		"enemy_hp": int(level.get("enemy_hp", 180)),
		"enemy_fire_interval": float(level.get("enemy_fire_interval", 2.6)),
		"time_limit": float(level.get("time_limit", 0.0)),
		"materials": int(level.get("materials", 300)),
		"rare": int(level.get("rare", 1)),
		"railgun_interval": float(level.get("railgun_interval", 22.0)),
		"railgun_damage": int(level.get("railgun_damage", 120)),
	}


## 選んだ任務を覚えておく
static func save_choice(mission_id: String, difficulty: String) -> void:
	var file := FileAccess.open(CHOICE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"mission": mission_id, "difficulty": difficulty}))


## 覚えておいた任務を読む（無ければ最初の任務の「中」）
static func load_choice() -> Dictionary:
	var fallback := {"mission": str(find("").get("id", "")), "difficulty": "normal"}
	if not FileAccess.file_exists(CHOICE_PATH):
		return fallback
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHOICE_PATH))
	if not (parsed is Dictionary):
		return fallback
	var choice: Dictionary = parsed
	return {
		"mission": str(choice.get("mission", fallback["mission"])),
		"difficulty": str(choice.get("difficulty", "normal")),
	}


## 今選ばれている任務の設定
static func current_setup() -> Dictionary:
	var choice := load_choice()
	return setup(str(choice["mission"]), str(choice["difficulty"]))
