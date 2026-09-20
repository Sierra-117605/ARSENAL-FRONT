extends Label
## ヘリコプターに乗っている間だけ出る表示（高度・上昇下降・速さ）。
## それ以外に乗っている時は消える。

## プレイヤーの乗員（今どの機体に乗っているかを調べる）
@export var occupant: Occupant
## 操縦入力を持っている PlayerInput（設定用に残す）
@export var player_input: PlayerInput


func _process(_delta: float) -> void:
	var heli := _current_helicopter()
	if heli == null:
		visible = false
		return
	visible = true
	var lift := float(heli.control.get("lift", 0.0))
	var updown := "上昇 ↑" if lift > 0.1 else ("下降 ↓" if lift < -0.1 else "ホバリング")
	var state := updown if not heli.is_landed() else "着陸中"
	var speed := Vector2(heli.velocity.x, heli.velocity.z).length()
	text = "高度 %4.0f m　速度 %3.0f m/秒　%s" % [
		maxf(heli.global_position.y, 0.0), speed, state]


## 今プレイヤーが乗っているヘリ（乗っていなければ null）
func _current_helicopter() -> Helicopter:
	if occupant == null:
		return null
	return occupant.get_vehicle() as Helicopter
