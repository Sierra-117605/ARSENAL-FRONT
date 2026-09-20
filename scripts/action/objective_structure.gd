class_name ObjectiveStructure
extends Pilotable
## 任務の対象になる建物（守る拠点／壊す目標）。SPEC §0.14。
## 動かないが、耐久を持ち撃たれる点は機体と同じ扱い（Pilotable を継承）。

## 残り耐久の割合で色を変える（見ただけで状態が分かるように）
@export var full_color: Color = Color(0.55, 0.6, 0.55)
@export var low_color: Color = Color(0.7, 0.25, 0.2)

var material: StandardMaterial3D


func _ready() -> void:
	super._ready()
	material = StandardMaterial3D.new()
	var mesh: MeshInstance3D = $Mesh
	mesh.material_override = material
	damaged.connect(func(_hp, _max): _update_color())
	_update_color()


func _update_color() -> void:
	var ratio := float(hp) / float(maxi(max_hp, 1))
	material.albedo_color = low_color.lerp(full_color, ratio)


## 建物は動かない（操縦入力は無視する）
func apply_control(_new_control: Dictionary) -> void:
	pass
