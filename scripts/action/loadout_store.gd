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


## 保存した構成を読む（無ければ標準の構成）
static func load_saved() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return RobotParts.default_loadout()
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return RobotParts.sanitize(parsed)
	return RobotParts.default_loadout()
