extends Label
## 航空機に乗っている間だけ出る表示（速度・高度・操縦桿の位置）。
## 飛行機以外に乗っている時は消える。

## プレイヤーの乗員（今どの機体に乗っているかを調べる）
@export var occupant: Occupant
## 操縦入力を持っている PlayerInput（操縦桿の傾き具合を見る）
@export var player_input: PlayerInput


func _process(_delta: float) -> void:
	var plane := _current_aircraft()
	if plane == null:
		visible = false
		return
	visible = true
	var state := "飛行中" if not plane.is_landed() else "地上"
	var stick := ""
	if player_input != null:
		stick = "　操縦桿 %s%s" % [_arrow_x(player_input.stick.x), _arrow_y(player_input.stick.y)]
	text = "速度 %3.0f m/秒　高度 %4.0f m　%s%s" % [
		plane.speed, maxf(plane.global_position.y, 0.0), state, stick]


## 今プレイヤーが乗っている航空機（乗っていなければ null）
func _current_aircraft() -> Aircraft:
	if occupant == null:
		return null
	var vehicle := occupant.get_vehicle()
	return vehicle as Aircraft


## 操縦桿の左右の傾きを矢印で表す
func _arrow_x(value: float) -> String:
	if value < -0.15:
		return "←"
	if value > 0.15:
		return "→"
	return "・"


## 操縦桿の上下の傾きを矢印で表す
func _arrow_y(value: float) -> String:
	if value > 0.15:
		return "↑"
	if value < -0.15:
		return "↓"
	return "・"
