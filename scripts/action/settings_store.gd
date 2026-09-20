class_name SettingsStore
extends RefCounted
## 遊び方の設定をファイルに保存・読み込みする（今は航空機の操縦方式だけ）。
## 保存先は user://settings.json（Windows なら %APPDATA%\ArsenalFront）。

const PATH := "user://settings.json"

## 航空機の操縦方式（エースコンバットの呼び方に合わせている）
## エキスパート：機体を自由に回せる。360 度ロールも背面飛行もできる。自動で水平に戻らない
const EXPERT := "expert"
## ノーヴィス：傾きが左右 80 度までに制限され、手を離すと自動で水平に戻る
const NOVICE := "novice"


## 保存されている操縦方式を返す（無ければエキスパート）
static func flight_mode() -> String:
	var data := load_all()
	var mode := str(data.get("flight_mode", EXPERT))
	return mode if mode == NOVICE else EXPERT


## 操縦方式を保存する
static func save_flight_mode(mode: String) -> void:
	var data := load_all()
	data["flight_mode"] = NOVICE if mode == NOVICE else EXPERT
	save_all(data)


## 設定をまるごと読む
static func load_all() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return parsed if parsed is Dictionary else {}


## 設定をまるごと保存する
static func save_all(data: Dictionary) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("設定を保存できませんでした: " + PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))
