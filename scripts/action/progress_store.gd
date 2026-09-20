class_name ProgressStore
extends RefCounted
## 進行状況（開発済みパーツ・持っている設計図・資材）の保存と読み込み（SPEC §0.13 柱3）。
## 保存先は user://progress.json。

const PATH := "user://progress.json"
## 開発を始める前から使えるパーツ（各部位の標準品）
const STARTING_PARTS := [
	"head_standard", "body_standard", "arms_standard",
	"legs_standard", "gen_standard", "weapon_rifle",
]


## まっさらな進行状況
static func fresh() -> Dictionary:
	return {
		"unlocked": STARTING_PARTS.duplicate(),  # 使えるパーツ
		"blueprints": [],                        # 持っている設計図（未開発）
		"materials": 0,                          # 開発に使う資材
	}


## 読み込む（無ければ最初の状態）
static func load_progress() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return fresh()
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return fresh()
	var data: Dictionary = parsed
	var result := fresh()
	for key in ["unlocked", "blueprints"]:
		if data.get(key) is Array:
			result[key] = data[key]
	result["materials"] = int(data.get("materials", 0))
	# 標準パーツは必ず使えるようにしておく
	for part_id in STARTING_PARTS:
		if not result["unlocked"].has(part_id):
			result["unlocked"].append(part_id)
	return result


## 保存する
static func save_progress(progress: Dictionary) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("進行状況を保存できませんでした: " + PATH)
		return
	file.store_string(JSON.stringify(progress, "\t"))


## そのパーツが使えるか
static func is_unlocked(progress: Dictionary, part_id: String) -> bool:
	var part := RobotParts.find(part_id)
	if part.is_empty():
		return false
	if not bool(part.get("locked", false)):
		return true  # 最初から使えるパーツ
	return (progress.get("unlocked", []) as Array).has(part_id)


## 設計図を手に入れる（同じものは重ねて持たない）
static func add_blueprint(progress: Dictionary, part_id: String) -> bool:
	if is_unlocked(progress, part_id):
		return false
	var blueprints: Array = progress.get("blueprints", [])
	if blueprints.has(part_id):
		return false
	blueprints.append(part_id)
	progress["blueprints"] = blueprints
	return true


## 設計図を開発して使えるようにする。資材が足りなければ false
static func develop(progress: Dictionary, part_id: String) -> bool:
	var blueprints: Array = progress.get("blueprints", [])
	if not blueprints.has(part_id):
		return false
	var cost := int(RobotParts.find(part_id).get("develop_cost", 100))
	if int(progress.get("materials", 0)) < cost:
		return false
	progress["materials"] = int(progress["materials"]) - cost
	blueprints.erase(part_id)
	progress["blueprints"] = blueprints
	var unlocked: Array = progress.get("unlocked", [])
	unlocked.append(part_id)
	progress["unlocked"] = unlocked
	return true
