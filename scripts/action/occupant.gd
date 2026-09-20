class_name Occupant
extends Node
## 「乗員」。操縦席に座って乗り物を動かす者（SPEC §0.3-2）。
## Phase 1 は見えない乗員が最初からロボットの操縦席に座っている（SPEC §0.7）。
## 将来は兵士がこの役を担い、乗り降りできるようにする。

## ゲーム開始時に座っている操縦席（空なら誰にも乗っていない状態で始まる）
@export var start_seat: Seat

## 座っている操縦席（座っていなければ null）
var seat: Seat = null


func _ready() -> void:
	if start_seat != null:
		start_seat.take_over(self)


## 操縦入力を受け取り、座っている席を通して乗り物へ渡す
func send_control(control: Dictionary) -> void:
	if seat != null:
		seat.relay_control(control)


## 今操縦している乗り物を返す（座っていなければ null）
func get_vehicle() -> Pilotable:
	if seat == null:
		return null
	return seat.get_vehicle()
