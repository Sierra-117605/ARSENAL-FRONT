class_name RobotParts
extends RefCounted
## ロボットのパーツ一覧（data/robot_parts.json）を読み、選んだ構成から機体の性能を計算する。
## 数値を変えたい時は JSON だけ直せばよい（スクリプトを触らない）。

const DATA_PATH := "res://data/robot_parts.json"

static var _data: Dictionary = {}


## JSON を読み込む（最初の 1 回だけ実際に読む）
static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(DATA_PATH)
		var parsed: Variant = JSON.parse_string(text)
		_data = parsed if parsed is Dictionary else {}
	return _data


## スロットの並び（頭・胴・腕・脚・発電機・武器）
static func slots() -> Array:
	return data().get("slots", [])


## スロットの日本語名
static func slot_name(slot: String) -> String:
	return data().get("slot_names", {}).get(slot, slot)


## そのスロットに付けられるパーツの一覧
static func parts_for(slot: String) -> Array:
	var list: Array = []
	for part in data().get("parts", []):
		if part.get("slot", "") == slot:
			list.append(part)
	return list


## id からパーツを探す（無ければ空）
static func find(part_id: String) -> Dictionary:
	for part in data().get("parts", []):
		if part.get("id", "") == part_id:
			return part
	return {}


## 各スロットの先頭のパーツを選んだ、標準の構成
static func default_loadout() -> Dictionary:
	var loadout := {}
	for slot in slots():
		var list := parts_for(slot)
		if not list.is_empty():
			loadout[slot] = list[0].get("id", "")
	return loadout


## 構成に抜けや知らない id があれば、標準のパーツで埋める
static func sanitize(loadout: Dictionary) -> Dictionary:
	var fixed := default_loadout()
	for slot in slots():
		var part_id: String = str(loadout.get(slot, ""))
		var part := find(part_id)
		if not part.is_empty() and part.get("slot", "") == slot:
			fixed[slot] = part_id
	return fixed


## 構成から機体の性能をまとめて計算する
static func compute_stats(loadout: Dictionary) -> Dictionary:
	var fixed := sanitize(loadout)
	var stats := {
		"max_hp": 0,          # 耐久
		"walk_speed": 10.0,   # 歩く速さ（メートル/秒）
		"damage": 10,         # 弾 1 発の威力
		"fire_interval": 0.25,# 次の弾までの間隔（秒）
		"bullet_speed": 300.0,# 弾の速さ
		"aim_range": 1500.0,  # 照準できる距離
		"spread": 1.2,        # 弾のばらつき（小さいほど正確）
	}
	var speed_mul := 1.0
	var damage_mul := 1.0
	var fire_rate_mul := 1.0
	for slot in slots():
		var part := find(str(fixed.get(slot, "")))
		var part_stats: Dictionary = part.get("stats", {})
		stats["max_hp"] += int(part_stats.get("max_hp", 0))
		if part_stats.has("walk_speed"):
			stats["walk_speed"] = float(part_stats["walk_speed"])
		if part_stats.has("damage"):
			stats["damage"] = int(part_stats["damage"])
		if part_stats.has("fire_interval"):
			stats["fire_interval"] = float(part_stats["fire_interval"])
		if part_stats.has("bullet_speed"):
			stats["bullet_speed"] = float(part_stats["bullet_speed"])
		if part_stats.has("aim_range"):
			stats["aim_range"] = float(part_stats["aim_range"])
		if part_stats.has("spread"):
			stats["spread"] = float(part_stats["spread"])
		speed_mul *= float(part_stats.get("speed_mul", 1.0))
		damage_mul *= float(part_stats.get("damage_mul", 1.0))
		fire_rate_mul *= float(part_stats.get("fire_rate_mul", 1.0))
	# 倍率をかける（胴の重さで速度、腕で火力、発電機で連射）
	stats["walk_speed"] = float(stats["walk_speed"]) * speed_mul
	stats["damage"] = int(round(float(stats["damage"]) * damage_mul))
	stats["fire_interval"] = float(stats["fire_interval"]) / maxf(fire_rate_mul, 0.01)
	return stats
