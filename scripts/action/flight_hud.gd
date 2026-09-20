extends Label
## 航空機に乗っている間だけ出る表示（速度・高度・操縦桿の位置）。
## 飛行機以外に乗っている時は消える。

## プレイヤーの乗員（今どの機体に乗っているかを調べる）
@export var occupant: Occupant
## 操縦入力を持っている PlayerInput（今は表示に使っていないが、設定用に残す）
@export var player_input: PlayerInput


func _process(_delta: float) -> void:
	var plane := _current_aircraft()
	if plane == null:
		visible = false
		return
	visible = true
	var state := "飛行中" if not plane.is_landed() else "地上"
	# 今どちらへ舵を入れているか（A/D と W/S の押し具合）
	var stick := "　操縦 %s%s" % [
		_arrow_x(float(plane.control.get("move_x", 0.0))),
		_arrow_y(-float(plane.control.get("move_z", 0.0)))]
	var mode := "エキスパート" if plane.is_expert() else "ノーヴィス"
	text = "速度 %3.0f m/秒　高度 %4.0f m　%s　%s%s" % [
		plane.speed, maxf(plane.global_position.y, 0.0), state, mode, stick]


## 今プレイヤーが乗っている航空機（乗っていなければ null）
func _current_aircraft() -> Aircraft:
	if occupant == null:
		return null
	var vehicle := occupant.get_vehicle()
	return vehicle as Aircraft


## 舵の左右を矢印で表す
func _arrow_x(value: float) -> String:
	if value < -0.15:
		return "←"
	if value > 0.15:
		return "→"
	return "・"


## 舵の上下を矢印で表す
func _arrow_y(value: float) -> String:
	if value > 0.15:
		return "↑"
	if value < -0.15:
		return "↓"
	return "・"
