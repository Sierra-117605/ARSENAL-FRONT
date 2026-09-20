class_name Robot
extends Pilotable
## 二足歩行ロボット。操縦入力に従って歩く。
## Phase 1 の自機は多用途歩行機（全高 約 12m、SPEC §0.9）。

## 機種（SPEC §0.9 の機種区分。保存用の文字列）
@export var machine_type: String = "multirole_walker"
## 歩く速さ（メートル/秒）
@export var walk_speed: float = 10.0
## 歩き出し・止まりの滑らかさ（大きいほどキビキビ）
@export var acceleration: float = 40.0

## 重力の強さ（プロジェクト設定の値を使う）
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

## 脚の振り幅（度）。仮の歩き用（本番モデルに差し替える時に作り直す）
@export var step_swing_deg: float = 22.0
## 1 メートル進むごとに進む歩調の量（大きいほど脚を速く振る）
@export var step_rate: float = 0.09
## 歩調に合わせて機体が上下に揺れる量（メートル）
@export var body_bob: float = 0.25
## 機体の色を塗り替える（透明のままなら元の色。敵機を赤くするのに使う）
@export var body_color: Color = Color(0, 0, 0, 0)
## 組み立ての構成（頭・胴・腕・脚・発電機・武器のパーツ id）。空なら標準の構成
@export var loadout: Dictionary = {}
## true なら、ガレージで保存した構成を読み込んで使う（プレイヤー機に付ける）
@export var use_saved_loadout: bool = false

## 照準できる距離（パーツで変わる。PlayerInput が使う）
var aim_range: float = 1500.0

## 腕の武器（Phase 1 は 1 種類）
@onready var weapon: Weapon = get_node_or_null("Weapon")
@onready var visual: Node3D = $Visual
@onready var leg_pivot_l: Node3D = $Visual/LegPivotL
@onready var leg_pivot_r: Node3D = $Visual/LegPivotR

## 歩調の進み具合（0〜1 で 1 歩分）
var step_phase: float = 0.0
## 見た目の揺れの強さ（止まると 0 に戻る）
var step_amount: float = 0.0
## 前のフレームの歩調（足音を鳴らす切り替わりを見るため）
var _last_step_half: int = 0


func _ready() -> void:
	# 組み立ての構成が指定されている時だけ性能を入れ替える。
	# 指定が無い機体（敵など）は、シーンで設定した耐久・速さをそのまま使う
	if use_saved_loadout:
		loadout = LoadoutStore.load_saved()
		apply_loadout(loadout)
	elif not loadout.is_empty():
		apply_loadout(loadout)
	_apply_part_visuals()
	super._ready()
	if body_color.a > 0.0:
		_repaint(visual)


## 組み立ての構成を機体の性能に反映する
func apply_loadout(new_loadout: Dictionary) -> void:
	loadout = RobotParts.sanitize(new_loadout)
	var stats := RobotParts.compute_stats(loadout)
	max_hp = int(stats["max_hp"])
	hp = max_hp
	walk_speed = float(stats["walk_speed"])
	aim_range = float(stats["aim_range"])
	var w: Weapon = get_node_or_null("Weapon")
	if w != null:
		w.damage = int(stats["damage"])
		w.fire_interval = float(stats["fire_interval"])
		w.bullet_speed = float(stats["bullet_speed"])
		w.spread = float(stats["spread"])
	_apply_part_visuals()


## パーツごとの見た目（大きさ・色）を機体に反映する
## スロット → 変化させる部品の名前
const VISUAL_PARTS := {
	"head": ["Head"],
	"body": ["Torso"],
	"arms": ["ShoulderL", "ShoulderR", "ArmL", "ArmR"],
	"legs": ["LegPivotL", "LegPivotR"],
	"generator": ["BackPack"],
	"weapon": ["Barrel"],
}


func _apply_part_visuals() -> void:
	if visual == null:
		return
	for slot in VISUAL_PARTS:
		var part := RobotParts.find(str(loadout.get(slot, "")))
		var look: Dictionary = part.get("visual", {})
		if look.is_empty():
			continue
		var scale_value := float(look.get("scale", 1.0))
		var rgb: Array = look.get("color", [])
		for node_name in VISUAL_PARTS[slot]:
			var node: Node3D = visual.get_node_or_null(node_name)
			if node == null:
				continue
			node.scale = Vector3.ONE * scale_value
			if rgb.size() == 3 and body_color.a <= 0.0:
				_tint(node, Color(rgb[0], rgb[1], rgb[2]))


## 部品（とその子）の色を変える
func _tint(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.7
		mat.metallic = 0.3
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_tint(child, color)


## 機体の見た目を指定の色で塗り替える（目玉の発光部分はそのまま）
func _repaint(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.name != "Visor":
			var mat := StandardMaterial3D.new()
			mat.albedo_color = body_color
			mat.roughness = 0.7
			mat.metallic = 0.3
			(child as MeshInstance3D).material_override = mat
		_repaint(child)


func _physics_process(delta: float) -> void:
	# 壊れていたら操作を受け付けない（その場で止まる）
	if not is_alive():
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		_update_step_motion(delta)
		return
	# 機体をカメラの向き（操縦入力の yaw）に合わせる（SPEC §0.7）
	rotation.y = control["yaw"]
	# 入力を機体の向き基準の方向に直す（前 = 機体の正面）
	var input_dir := Vector3(control["move_x"], 0.0, control["move_z"])
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	var target := global_transform.basis * input_dir * walk_speed

	# 水平方向は目標速度へ徐々に近づける
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	# 地面にいなければ落ちる
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()

	# 射撃ボタンが押されていれば、照準の先へ撃つ
	if control["fire"] and weapon != null:
		weapon.try_fire(Pilotable.aim_point(control), self)

	_update_step_motion(delta)


## 仮の歩き：脚を前後に振り、歩調に合わせて機体を上下に揺らす
func _update_step_motion(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	# 実際に進んだ距離に応じて歩調を進める（速いほど脚が速く動く）
	step_phase = fposmod(step_phase + speed * step_rate * delta, 1.0)
	# 止まっている時は揺れを 0 に戻す
	var wanted := clampf(speed / maxf(walk_speed, 0.01), 0.0, 1.0)
	step_amount = move_toward(step_amount, wanted, 4.0 * delta)

	# 足が地面に着くたび（1 周に 2 回）に足音を鳴らす
	var half := int(step_phase * 2.0)
	if half != _last_step_half and step_amount > 0.3:
		Sounds.play_at(self, Sounds.STEP, global_position)
	_last_step_half = half

	var swing := sin(step_phase * TAU) * deg_to_rad(step_swing_deg) * step_amount
	leg_pivot_l.rotation.x = swing
	leg_pivot_r.rotation.x = -swing
	# 1 歩で 2 回沈むので 2 倍の速さで上下させる
	visual.position.y = -absf(sin(step_phase * TAU)) * body_bob * step_amount


## 保存用の状態に機種を加える
func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["machine_type"] = machine_type
	data["loadout"] = loadout
	return data


## 保存した状態から機種も戻す
func from_dict(data: Dictionary) -> void:
	super.from_dict(data)
	machine_type = data.get("machine_type", machine_type)
	if data.has("loadout"):
		apply_loadout(data["loadout"])
