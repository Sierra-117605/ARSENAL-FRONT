class_name Pilotable
extends CharacterBody3D
## 「操縦可能な物」の共通土台（SPEC §0.3-1）。
## ロボット・兵士・戦車・航空機・艦艇はすべてこれを継承する。
## 操作は「操縦入力」(Dictionary) として受け取り、動き方は継承先が決める。

## この物を識別する文字列（保存・将来の通信用）
@export var pilotable_id: String = ""
## 耐久の最大値（0 になると撃破）
@export var max_hp: int = 300
## 陣営（"player" = 自軍 / "enemy" = 敵軍）。狙う相手を決めるのに使う
@export var team: String = "player"

## 今の耐久
var hp: int = 0

## 耐久が減った時に知らせる（残り耐久, 最大）
signal damaged(hp: int, max_hp: int)
## 撃破された時に知らせる
signal destroyed
## 部位が壊れた時に知らせる（部位名）
signal part_broken(part: String)

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
	add_to_group("pilotable")  # 乗り換え先を探すときに使う
	add_to_group("team_" + team)  # 陣営ごとの検索用


## 当たり判定の形（shape）ごとの部位名。継承先で設定する（例：{"HitArmR": "arm_right"}）
var part_of_shape: Dictionary = {}
## 部位ごとの「本体へのダメージの通りやすさ」。継承先で設定する
var part_body_ratio: Dictionary = {}
## 部位ごとの残り耐久
var part_hp: Dictionary = {}
## 壊れた部位の一覧
var broken_parts: Array[String] = []


## 当たった場所（shape 番号）から部位名を調べる
func part_name_for_shape(shape_index: int) -> String:
	if shape_index < 0:
		return ""
	var owner_id := shape_find_owner(shape_index)
	var node := shape_owner_get_owner(owner_id)
	if node == null:
		return ""
	return str(part_of_shape.get(node.name, ""))


## 弾が当たった：当たった部位の耐久を減らし、本体の耐久も減らす。
## 本体への効き方は部位ごとに違う（頭は弱点、腕や脚は本体に響きにくい）。
func take_hit_at_shape(damage: int, shape_index: int) -> void:
	var part := part_name_for_shape(shape_index)
	if part != "" and part_hp.has(part) and not broken_parts.has(part):
		part_hp[part] = maxi(int(part_hp[part]) - damage, 0)
		if int(part_hp[part]) == 0:
			broken_parts.append(part)
			_on_part_broken(part)
			part_broken.emit(part)
	var ratio := float(part_body_ratio.get(part, 1.0))
	take_hit(maxi(int(round(float(damage) * ratio)), 1))


## 部位が壊れた時の処理（継承先で中身を書く）
func _on_part_broken(_part: String) -> void:
	pass


## その部位が壊れているか
func is_part_broken(part: String) -> bool:
	return broken_parts.has(part)


## 弾などが当たった時に呼ばれる（Bullet から）
func take_hit(damage: int) -> void:
	if hp <= 0:
		return
	hp = maxi(hp - damage, 0)
	damaged.emit(hp, max_hp)
	Sounds.play_at(self, Sounds.HIT, global_position)
	if hp == 0:
		Sounds.play_at(self, Sounds.DESTROY, global_position)
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
		"broken_parts": broken_parts.duplicate(),
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
