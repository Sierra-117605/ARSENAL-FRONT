class_name GameState
extends RefCounted

# 司令官モードのゲーム全体状態。
# docs/DATA_STRUCTURE.md の方針:
#   - state は JSON 互換型のみで構成
#   - 更新は apply(event) を経由 (後の P2P 同期に備える)
#
# Phase 1 では資源 = 資金 + 素材 の 2 種類 (SPEC §2.4)。
# 任務 (§2.5) は次イテレーションで追加予定。

const SAVE_PATH: String = "user://gamestate.json"

# 状態本体 (Dictionary)
var state: Dictionary = {}

# 適用されたイベントのログ (デバッグ・将来の同期用)
var event_log: Array = []

func _init() -> void:
	state = default_state()

static func default_state() -> Dictionary:
	return {
		"day": 1,
		"funds": 1000,
		"materials": 500,
		"inventory": [],  # 製造済みユニット (Combat.make_instance 形式) の配列
	}

# --- イベント適用 (状態更新の唯一の入り口) ----------------------------

func apply(event: Dictionary) -> void:
	event_log.append(event)
	var t: String = String(event.get("type", ""))
	match t:
		"advance_day":
			state["day"] = int(state.get("day", 0)) + int(event.get("days", 1))
		"add_funds":
			state["funds"] = int(state.get("funds", 0)) + int(event.get("delta", 0))
		"add_materials":
			state["materials"] = int(state.get("materials", 0)) + int(event.get("delta", 0))
		"produce_unit":
			var inv: Array = state.get("inventory", [])
			var unit: Dictionary = event.get("unit", {})
			inv.append(unit)
			state["inventory"] = inv
		"remove_unit":
			var inv2: Array = state.get("inventory", [])
			var unit_id: String = String(event.get("unit_id", ""))
			for i in inv2.size():
				if String((inv2[i] as Dictionary).get("id", "")) == unit_id:
					inv2.remove_at(i)
					break
			state["inventory"] = inv2
		_:
			push_warning("[GameState] 未知のイベント type: " + t)

# --- 便利アクセサ ------------------------------------------------------

func day() -> int:
	return int(state.get("day", 0))

func funds() -> int:
	return int(state.get("funds", 0))

func materials() -> int:
	return int(state.get("materials", 0))

func inventory() -> Array:
	return state.get("inventory", [])

# 重量 → 製造コスト (SPEC §2.4 暫定式)
static func production_cost_for(weight: int) -> Dictionary:
	return {
		"funds": weight * 10,
		"materials": weight * 5,
	}

func can_afford(cost: Dictionary) -> bool:
	return funds() >= int(cost.get("funds", 0)) and materials() >= int(cost.get("materials", 0))

# --- セーブ / ロード ---------------------------------------------------

func save_to(path: String = SAVE_PATH) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[GameState] gamestate.json を書き込めません: " + path)
		return false
	f.store_string(JSON.stringify(state, "  "))
	f.close()
	return true

func load_from(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		# 欠けているキーは default で補完 (将来の互換性のため)
		var d: Dictionary = default_state()
		for k in d.keys():
			if not (parsed as Dictionary).has(k):
				(parsed as Dictionary)[k] = d[k]
		state = parsed
		return true
	push_warning("[GameState] gamestate.json の中身が辞書ではありません")
	return false

static func get_save_absolute_path() -> String:
	return ProjectSettings.globalize_path(SAVE_PATH)
