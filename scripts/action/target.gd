class_name Target
extends StaticBody3D
## 動かない標的（SPEC §0.7）。弾が当たるたびに色が変わり、3 発目で壊れて消える。

## この標的を識別する文字列（保存用）
@export var target_id: String = ""
## 耐久（弾 1 発 = 10。3 発で壊れる）
@export var max_hp: int = 30

## 残り耐久（命中するたびに減る）
var hp: int = 0

## 残り耐久の割合ごとの色（多い → 中くらい → 少ない）
const COLOR_FULL := Color(0.9, 0.9, 0.85)
const COLOR_HALF := Color(1.0, 0.65, 0.15)
const COLOR_LOW := Color(0.85, 0.15, 0.1)

var material: StandardMaterial3D


func _ready() -> void:
	hp = max_hp
	# 標的ごとに色を変えられるよう、自分専用の見た目の設定を作る
	material = StandardMaterial3D.new()
	var mesh: MeshInstance3D = $Mesh
	mesh.material_override = material
	_update_color()


## 弾が当たった時に呼ばれる
func take_hit(damage: int) -> void:
	if hp <= 0:
		return
	hp = maxi(hp - damage, 0)
	_update_color()
	if hp == 0:
		queue_free()  # 壊れて消える


func _update_color() -> void:
	var ratio := float(hp) / float(maxi(max_hp, 1))
	if ratio > 0.7:
		material.albedo_color = COLOR_FULL
	elif ratio > 0.35:
		material.albedo_color = COLOR_HALF
	else:
		material.albedo_color = COLOR_LOW


## 保存用に現在の状態を JSON 互換の Dictionary にする
func to_dict() -> Dictionary:
	return {
		"id": target_id,
		"hp": hp,
		"position": {"x": global_position.x, "y": global_position.y, "z": global_position.z},
	}
