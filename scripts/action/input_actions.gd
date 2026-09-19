class_name InputActions
extends RefCounted
## 操作キーの割り当て（SPEC §0.7：WASD で移動）。
## 起動時にキーを登録する。キーコンフィグ対応時はここを差し替える。

const MOVE_FORWARD := "move_forward"
const MOVE_BACK := "move_back"
const MOVE_LEFT := "move_left"
const MOVE_RIGHT := "move_right"

## 操作名 → キー（キーボード上の物理位置で指定するので配列が違っても同じ場所）
const KEYS := {
	MOVE_FORWARD: KEY_W,
	MOVE_BACK: KEY_S,
	MOVE_LEFT: KEY_A,
	MOVE_RIGHT: KEY_D,
}


## まだ登録されていない操作を登録する（何度呼んでも安全）
static func ensure_registered() -> void:
	for action in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEYS[action]
		InputMap.action_add_event(action, ev)
