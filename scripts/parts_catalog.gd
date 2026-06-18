class_name PartsCatalog
extends RefCounted

# data/parts/*.json を読み込み、id をキーに引けるようにする。
# SPEC §3 / docs/DATA_STRUCTURE.md: パーツ数値はコードに直書きせず JSON から読む。

const SLOT_FILES: Dictionary = {
	"hull": "res://data/parts/hull.json",
	"main_armament": "res://data/parts/main_armament.json",
	"turret": "res://data/parts/turret.json",
	"engine": "res://data/parts/engine.json",
	"armor": "res://data/parts/armor.json",
	"suspension": "res://data/parts/suspension.json",
	"module": "res://data/parts/modules.json",
}

var parts_by_id: Dictionary = {}
var parts_by_slot: Dictionary = {}

func load_all() -> int:
	parts_by_id.clear()
	parts_by_slot.clear()
	for slot in SLOT_FILES:
		var path: String = SLOT_FILES[slot]
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			push_error("[PartsCatalog] パーツファイルを開けません: " + path)
			continue
		var json_text: String = f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(json_text)
		if not (parsed is Array):
			push_error("[PartsCatalog] パーツファイルは配列である必要があります: " + path)
			continue
		var ids: Array = []
		for entry in parsed:
			if not (entry is Dictionary):
				push_error("[PartsCatalog] パーツ項目が辞書ではありません: " + path)
				continue
			var id: String = String(entry.get("id", ""))
			if id == "":
				push_error("[PartsCatalog] id が空のパーツがあります: " + path)
				continue
			parts_by_id[id] = entry
			ids.append(id)
		parts_by_slot[slot] = ids
	return parts_by_id.size()

func get_part(id: String) -> Dictionary:
	var v: Variant = parts_by_id.get(id, null)
	if v is Dictionary:
		return v
	return {}
