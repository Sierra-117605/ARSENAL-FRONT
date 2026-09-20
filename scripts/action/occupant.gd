class_name Occupant
extends Node
## 「乗員」。操縦席に座って乗り物を動かす者（SPEC §0.3-2）。
## Phase 1 は見えない乗員が最初からロボットの操縦席に座っている（SPEC §0.7）。
## 将来は兵士がこの役を担い、乗り降りできるようにする。

## ゲーム開始時に座っている操縦席（空なら徒歩で始まる）
@export var start_seat: Seat
## この乗員の体（兵士）。席に座っていない間はこの体を動かす
@export var body: Pilotable

## 座っている操縦席（座っていなければ null）
var seat: Seat = null


func _ready() -> void:
	if start_seat != null:
		start_seat.take_over(self)
		# 最初から乗っている場合、体（兵士）は機体の中にいる扱いにする
		if body != null and body.has_method("enter_vehicle"):
			body.enter_vehicle()


## 操縦入力を受け取る。
## 席に座っていれば乗り物へ、座っていなければ自分の体（兵士）へ渡す。
func send_control(control: Dictionary) -> void:
	if seat != null:
		seat.relay_control(control)
	elif body != null:
		body.apply_control(control)


## 今操縦している乗り物を返す（座っていなければ null）
func get_vehicle() -> Pilotable:
	if seat == null:
		return null
	return seat.get_vehicle()


## 今プレイヤーが動かしている物（乗り物、または徒歩の体）
func get_controlled() -> Pilotable:
	var vehicle := get_vehicle()
	return vehicle if vehicle != null else body
