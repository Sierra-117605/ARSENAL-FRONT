class_name LoadoutStore
extends RefCounted
## 組み立ての構成をファイルに保存・読み込みする。
## 保存先は user://loadout.json（Windows なら %APPDATA%\ArsenalFront）。
## res:// は書き込めないので使わない（KNOWLEDGE 参照）。

const PATH := "user://loadout.json"


## 構成を保存する
static func save(loadout: Dictionary) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("構成を保存できませんでした: " + PATH)
		return
	file.store_string(JSON.stringify(loadout, "\t"))


## 保存した構成を読む（無ければ標準の構成）。機種は "machine_type" に入れて持ち歩く
static func load_saved() -> Dictionary:
	var fallback := RobotParts.default_loadout()
	fallback["machine_type"] = RobotParts.default_machine_id()
	if not FileAccess.file_exists(PATH):
		return fallback
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var fixed := RobotParts.sanitize(parsed)
		var machine := str(parsed.get("machine_type", RobotParts.default_machine_id()))
		fixed["machine_type"] = str(RobotParts.find_machine(machine).get("id", RobotParts.default_machine_id()))
		return fixed
	return fallback
