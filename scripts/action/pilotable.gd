class_name Pilotable
extends CharacterBody3D
## 「操縦可能な物」の共通土台（SPEC §0.3-1）。
## ロボット・兵士・戦車・航空機・艦艇はすべてこれを継承する。
## 操作は「操縦入力」(Dictionary) として受け取り、動き方は継承先が決める。

## この物を識別する文字列（保存・将来の通信用）
@export var pilotable_id: String = ""
## 耐久の最大値（0 になると撃破）
@export var max_hp: int = 300

## 今の耐久
var hp: int = 0

## 耐久が減った時に知らせる（残り耐久, 最大）
signal damaged(hp: int, max_hp: int)
## 撃破された時に知らせる
signal destroyed

## 直近に受け取った操縦入力。中身は JSON にそのまま書ける値だけにする
var control: Dictionary = empty_control()


## 何も操作していない状態の操縦入力を返す
static func empty_control() -> Dictionary:
	return {
		"move_x": 0.0,   # 左右の移動入力 (-1=左 〜 1=右)
		"move_z": 0.0,   # 前後の移動入力 (-1=前 〜 1=後ろ)
		"yaw": 0.0,      # 向きたい方向の水平角（ラジアン）
		"pitch": 0.0,    # 向きたい方向の上下角（ラジアン）
		"fire": false,   # 射撃ボタン
		"aim": {"x": 0.0, "y": 0.0, "z": 0.0},  # 狙っている地点（照準の先）
	}


## 操縦入力の "aim" を Vector3 にして返す
static func aim_point(ctrl: Dictionary) -> Vector3:
	var a: Dictionary = ctrl.get("aim", {})
	return Vector3(a.get("x", 0.0), a.get("y", 0.0), a.get("z", 0.0))


func _ready() -> void:
	hp = max_hp


## 弾などが当たった時に呼ばれる（Bullet から）
func take_hit(damage: int) -> void:
	if hp <= 0:
		return
	hp = maxi(hp - damage, 0)
	damaged.emit(hp, max_hp)
	if hp == 0:
		destroyed.emit()


## まだ動けるか
func is_alive() -> bool:
	return hp > 0


## 操縦席の乗員から操縦入力を受け取る（操縦席の「運転手席」からのみ呼ばれる）
func apply_control(new_control: Dictionary) -> void:
	control = new_control


## 自分が持っている操縦席の一覧を返す
func get_seats() -> Array[Seat]:
	var seats: Array[Seat] = []
	for child in get_children():
		if child is Seat:
			seats.append(child)
	return seats


## 保存用に現在の状態を JSON 互換の Dictionary にする
func to_dict() -> Dictionary:
	# まだ世界に置かれていない時は親からの位置を使う（global_position は使えない）
	var pos := global_position if is_inside_tree() else position
	return {
		"id": pilotable_id,
		"position": {"x": pos.x, "y": pos.y, "z": pos.z},
		"rotation_y": rotation.y,
		"hp": hp,
	}


## to_dict() で作った Dictionary から状態を戻す
func from_dict(data: Dictionary) -> void:
	pilotable_id = data.get("id", pilotable_id)
	var p: Dictionary = data.get("position", {})
	var loaded := Vector3(p.get("x", 0.0), p.get("y", 0.0), p.get("z", 0.0))
	if is_inside_tree():
		global_position = loaded
	else:
		position = loaded
	rotation.y = data.get("rotation_y", 0.0)
	hp = data.get("hp", max_hp)
