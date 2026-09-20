class_name BossPart
extends Pilotable
## ボス（レールガン要塞）の部位（SPEC §0.8）。
## 迎撃砲台・発電施設・砲身・中枢など、壊せる部分それぞれがこれになる。

## この部位が属する段階（1=迎撃砲台 / 2=発電施設 / 3=砲身・中枢）
@export var stage: int = 1
## 画面に出す部位名
@export var part_label: String = ""
## 壊れる前の色
@export var intact_color: Color = Color(0.45, 0.45, 0.42)
## 壊れた後の色
@export var broken_color: Color = Color(0.12, 0.1, 0.1)
## この部位が撃ってくるか（迎撃砲台は撃つ、発電施設は撃たない）
@export var can_shoot: bool = false
## 撃つ間隔（秒）
@export var fire_interval: float = 2.4
## 有効射程（メートル）
@export var fire_range: float = 260.0

@onready var weapon: Weapon = get_node_or_null("Weapon")
var material: StandardMaterial3D
## まだ自分の段階が来ていない間は無敵（順番に壊させるため）
var active: bool = false


func _ready() -> void:
	super._ready()
	# 壊れたら当たり判定を消す（残骸が盾になって奥の部位を守ってしまわないように）
	destroyed.connect(_on_destroyed)
	material = StandardMaterial3D.new()
	var mesh: MeshInstance3D = get_node_or_null("Mesh")
	if mesh != null:
		mesh.material_override = material
	_update_color()
	damaged.connect(func(_hp, _max): _update_color())
	if weapon != null:
		weapon.fire_interval = fire_interval


func _physics_process(_delta: float) -> void:
	# 迎撃砲台は、射程内の自軍機を撃つ
	if not can_shoot or not is_alive() or weapon == null:
		return
	var prey := _nearest_target()
	if prey == null:
		return
	var distance := global_position.distance_to(prey.global_position)
	if distance <= fire_range:
		weapon.try_fire(prey.global_position + Vector3(0, 4, 0), self)


## いちばん近い自軍機（プレイヤー側）を探す
func _nearest_target() -> Pilotable:
	var nearest: Pilotable = null
	var nearest_distance := INF
	for node in get_tree().get_nodes_in_group("team_player"):
		var other := node as Pilotable
		if other == null or not other.is_alive() or not other.visible:
			continue
		var distance := global_position.distance_to(other.global_position)
		if distance < nearest_distance:
			nearest = other
			nearest_distance = distance
	return nearest


## その段階になるまでは攻撃を受け付けない（装甲に覆われている扱い）
func take_hit(damage: int) -> void:
	if not active:
		return
	super.take_hit(damage)


func take_hit_at_shape(damage: int, shape_index: int) -> void:
	if not active:
		return
	super.take_hit_at_shape(damage, shape_index)


## 壊れた時：見た目は残すが、弾は通り抜けるようにする
func _on_destroyed() -> void:
	for owner_id in get_shape_owners():
		shape_owner_set_disabled(owner_id, true)
	_update_color()


## 段階が来たら攻撃を受け付けるようにする
func activate() -> void:
	active = true
	_update_color()


func _update_color() -> void:
	if material == null:
		return
	if not is_alive():
		material.albedo_color = broken_color
		return
	if not active:
		# まだ攻撃できない部位は暗く表示する
		material.albedo_color = intact_color.darkened(0.45)
		return
	var ratio := float(hp) / float(maxi(max_hp, 1))
	material.albedo_color = Color(0.85, 0.3, 0.25).lerp(intact_color, ratio)


## 建物なので操縦入力は無視する
func apply_control(_new_control: Dictionary) -> void:
	pass
