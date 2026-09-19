class_name Seat
extends Marker3D
## 「操縦席」。乗り物（Pilotable）の子として置く（SPEC §0.3-2）。
## 乗員が座ると、その乗員の操縦入力が乗り物に届く。

## true なら運転手席（この席の乗員が乗り物を動かす）
@export var is_driver: bool = true

## 今座っている乗員（空席なら null）
var occupant: Occupant = null


## この席が付いている乗り物を返す
func get_vehicle() -> Pilotable:
	return get_parent() as Pilotable


## 乗員を座らせる。すでに誰か座っていたら false
func sit(new_occupant: Occupant) -> bool:
	if occupant != null:
		return false
	occupant = new_occupant
	new_occupant.seat = self
	return true


## 乗員を降ろす（Phase 1 では使わない。乗り降り追加時のための入口）
func leave() -> void:
	if occupant != null:
		occupant.seat = null
	occupant = null
	var vehicle := get_vehicle()
	if is_driver and vehicle != null:
		vehicle.apply_control(Pilotable.empty_control())


## 乗員からの操縦入力を乗り物へ渡す（運転手席のみ）
func relay_control(control: Dictionary) -> void:
	var vehicle := get_vehicle()
	if is_driver and vehicle != null:
		vehicle.apply_control(control)
