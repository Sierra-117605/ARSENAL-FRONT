class_name SaveIO
extends RefCounted

# 設計データなどプレイヤー固有のデータを保存・読込する。
# 保存先は user:// (Godot 標準のユーザーデータ領域)。
# Windows では %APPDATA%\Godot\app_userdata\<project_name>\ に置かれる。
# (res:// 配下はエクスポートしたゲームで読み取り専用になるため使えない)

const DESIGNS_PATH: String = "user://designs.json"

# --- 設計の読込 ----------------------------------------------------
# ファイルが無い、壊れている、配列じゃない場合は空配列を返す。
static func load_designs() -> Array:
	if not FileAccess.file_exists(DESIGNS_PATH):
		return []
	var f: FileAccess = FileAccess.open(DESIGNS_PATH, FileAccess.READ)
	if f == null:
		push_warning("[SaveIO] designs.json を読めません: " + DESIGNS_PATH)
		return []
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Array):
		push_warning("[SaveIO] designs.json の中身が配列ではありません")
		return []
	return parsed

# --- 設計の保存 ----------------------------------------------------
# 返り値: 保存に成功したか
static func save_designs(designs: Array) -> bool:
	var f: FileAccess = FileAccess.open(DESIGNS_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[SaveIO] designs.json を書き込めません: " + DESIGNS_PATH)
		return false
	# 人間にも読める形式で保存 (Phase 1 ではデバッグしやすさ優先)
	f.store_string(JSON.stringify(designs, "  "))
	f.close()
	return true

# 絶対パスを返す (デバッグ表示用)
static func get_designs_absolute_path() -> String:
	return ProjectSettings.globalize_path(DESIGNS_PATH)
