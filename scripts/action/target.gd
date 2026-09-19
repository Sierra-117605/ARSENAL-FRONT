class_name Target
extends StaticBody3D
## 動かない標的（SPEC §0.7）。弾が当たるたびに色が変わり、3 発目で壊れて消える。

## この標的を識別する文字列（保存用）
@export var target_id: String = ""
## 壊れるまでに必要な命中数
@export var max_hp: int = 3

## 残り耐久（命中するたびに減る）
var hp: int = 0

## 残り耐久ごとの色（満タン → 1 発目 → 2 発目）
const COLORS := {
	3: Color(0.9, 0.9, 0.85),
	2: Color(1.0, 0.65, 0.15),
	1: Color(0.85, 0.15, 0.1),
}

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
	material.albedo_color = COLORS.get(hp, COLORS[1])


## 保存用に現在の状態を JSON 互換の Dictionary にする
func to_dict() -> Dictionary:
	return {
		"id": target_id,
		"hp": hp,
		"position": {"x": global_position.x, "y": global_position.y, "z": global_position.z},
	}
