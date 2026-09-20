class_name GameLog
extends RefCounted
## 遊んだ内容を記録する。出力は Godot のログファイルに残る：
##   C:\Users\<ユーザー名>\AppData\Roaming\ArsenalFront\logs\godot.log
## 開発者が遊んだ後、このファイルを読めば何が起きたか分かる（不具合の調査に使う）。

## 記録を残すか（切りたい時は false）
static var enabled: bool = true


## 1 行記録する。経過時間（秒）と分類を頭に付ける
static func write(category: String, message: String) -> void:
	if not enabled:
		return
	var seconds := float(Time.get_ticks_msec()) / 1000.0
	print("[%7.2fs][%s] %s" % [seconds, category, message])


## 構成をまとめて 1 行にする
static func loadout_text(loadout: Dictionary, machine_id: String) -> String:
	var machine := RobotParts.find_machine(machine_id)
	var parts: Array[String] = []
	for slot in RobotParts.slots():
		var part := RobotParts.find(str(loadout.get(slot, "")))
		parts.append(str(part.get("name", "?")))
	return "%s ／ %s" % [machine.get("name", machine_id), " + ".join(parts)]
