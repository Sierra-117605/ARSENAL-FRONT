class_name AIPilot
extends Occupant
## コンピュータが動かす乗員。人の代わりに操縦席に座り、相手を追って撃つ。
## プレイヤー側と同じ「乗員 → 操縦席 → 乗り物」の道を通るので、
## 同じ機体をプレイヤーが操縦することもできる（将来の乗り換え・味方 AI に流用できる）。

## 追いかける相手
@export var chase_target: Node3D
## この距離を保とうとする（メートル）
@export var preferred_distance: float = 55.0
## この距離まで近づくと撃ち始める（メートル）
@export var fire_range: float = 90.0
## 相手のどのくらいの高さを狙うか（足元からの高さ）
@export var aim_height: float = 6.0
## 撃つ間隔（秒）。プレイヤーより遅くしてある
@export var fire_interval: float = 2.0
## 保つ距離の許容幅（この幅の中では前後に動かない）
@export var distance_margin: float = 8.0
## 狙いのブレ（メートル）。0 だと百発百中で厳しすぎる
@export var aim_spread: float = 4.0


func _ready() -> void:
	super._ready()
	var vehicle := get_vehicle()
	if vehicle != null and vehicle.has_method("get") and vehicle.get("weapon") != null:
		vehicle.weapon.fire_interval = fire_interval


func _physics_process(_delta: float) -> void:
	var vehicle := get_vehicle()
	if vehicle == null:
		return
	var control := Pilotable.empty_control()
	# 自分か相手が倒れていたら何もしない
	if not vehicle.is_alive() or chase_target == null or not _target_alive():
		send_control(control)
		return

	var to_target: Vector3 = chase_target.global_position - vehicle.global_position
	var flat := Vector2(to_target.x, to_target.z)
	var distance := flat.length()
	# 相手の方を向く
	control["yaw"] = atan2(-to_target.x, -to_target.z)
	# 遠ければ近づき、近すぎれば下がる
	if distance > preferred_distance + distance_margin:
		control["move_z"] = -1.0
	elif distance < preferred_distance - distance_margin:
		control["move_z"] = 1.0
	# 射程に入ったら撃つ
	if distance <= fire_range:
		control["fire"] = true
		var aim: Vector3 = chase_target.global_position + Vector3(0.0, aim_height, 0.0) + _spread()
		control["aim"] = {"x": aim.x, "y": aim.y, "z": aim.z}
	send_control(control)


## 狙いのブレを作る
func _spread() -> Vector3:
	return Vector3(randf_range(-aim_spread, aim_spread), randf_range(-aim_spread, aim_spread),
		randf_range(-aim_spread, aim_spread))


## 追いかける相手がまだ生きているか
func _target_alive() -> bool:
	if chase_target is Pilotable:
		return (chase_target as Pilotable).is_alive()
	return true
