class_name Robot
extends Pilotable
## 二足歩行ロボット。操縦入力に従って歩く。
## Phase 1 の自機は多用途歩行機（全高 約 12m、SPEC §0.9）。

## 機種（SPEC §0.9 の機種区分。data/machine_types.json の id）
@export var machine_type: String = "multirole_walker"
## 全高（メートル）。機種で決まる。カメラが距離を合わせるのに使う
var height: float = 12.0
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
## true なら、ガレージで保存した「味方機」の構成を読み込んで使う
@export var use_ally_loadout: bool = false

## 照準できる距離（パーツで変わる。PlayerInput が使う）
var aim_range: float = 1500.0

## 腕の武器（Phase 1 は 1 種類）
@onready var weapon: Weapon = get_node_or_null("Weapon")
@onready var visual: Node3D = $Visual
@onready var leg_pivot_l: Node3D = $Visual/LegPivotL
@onready var leg_pivot_r: Node3D = $Visual/LegPivotR

## 部位ごとの耐久の割合（本体の耐久に対して）。壊れると効果が出る
const PART_HP_RATIO := {
	"head": 0.10,   # 頭：壊れると遠くを狙えなくなる
	"arm_left": 0.13,
	"arm_right": 0.13,  # 右腕：武器が付いている。壊れると撃てない
	"legs": 0.18,   # 脚：壊れるとほとんど歩けない
}
## 部位ごとの「本体へのダメージの通りやすさ」
## 頭は弱点、腕や脚は当てても本体には響きにくい（狙う場所を選ぶ意味を出す）
const PART_BODY_RATIO := {
	"head": 1.5,
	"arm_left": 0.4,
	"arm_right": 0.4,
	"legs": 0.5,
}
## 当たり判定の形ごとの部位名
const PART_SHAPES := {
	"HitHead": "head",
	"HitArmL": "arm_left",
	"HitArmR": "arm_right",
	"HitLegs": "legs",
}
## 脚が壊れた時の歩く速さの倍率
@export var broken_legs_speed_mul: float = 0.25
## 頭が壊れた時の照準距離の倍率
@export var broken_head_aim_mul: float = 0.35

## 部位が壊れる前の値（元に戻せるように覚えておく）
var _base_walk_speed: float = 10.0
var _base_aim_range: float = 1500.0

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
		var saved := LoadoutStore.load_saved()
		apply_loadout(saved, str(saved.get("machine_type", machine_type)))
	elif use_ally_loadout:
		var ally := LoadoutStore.load_ally()
		apply_loadout(ally, str(ally.get("machine_type", machine_type)))
	elif not loadout.is_empty():
		apply_loadout(loadout)
	else:
		# 構成の指定が無い機体（敵など）も、機種の大きさだけは反映する
		_apply_machine_shape(RobotParts.compute_stats(RobotParts.default_loadout(), machine_type))
	_apply_part_visuals()
	# どの機体でも部位ごとの耐久を用意する（本体の耐久が決まった後に行う）
	_reset_parts()
	super._ready()
	if body_color.a > 0.0:
		_repaint(visual)


## 組み立ての構成を機体の性能に反映する
func apply_loadout(new_loadout: Dictionary, new_machine: String = "") -> void:
	if new_machine != "":
		machine_type = new_machine
	loadout = RobotParts.sanitize(new_loadout, machine_type)
	var stats := RobotParts.compute_stats(loadout, machine_type)
	_apply_machine_shape(stats)
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
	_reset_parts()


## 部位ごとの耐久を、本体の耐久に合わせて組み直す
func _reset_parts() -> void:
	part_of_shape = PART_SHAPES
	part_body_ratio = PART_BODY_RATIO
	part_hp.clear()
	broken_parts.clear()
	for part in PART_HP_RATIO:
		part_hp[part] = int(round(float(max_hp) * float(PART_HP_RATIO[part])))
	_base_walk_speed = walk_speed
	_base_aim_range = aim_range


## 部位が壊れた時：武器が使えなくなる／歩けなくなる／遠くを狙えなくなる
func _on_part_broken(part: String) -> void:
	match part:
		"arm_right":
			if weapon != null:
				weapon.disabled = true
		"legs":
			walk_speed = _base_walk_speed * broken_legs_speed_mul
		"head":
			aim_range = _base_aim_range * broken_head_aim_mul
	# 壊れた部位を黒く焦がす
	_mark_broken_visual(part)


## 壊れた部位の見た目を変える
const BROKEN_VISUAL := {
	"head": ["Head"],
	"arm_left": ["ShoulderL", "ArmL"],
	"arm_right": ["ShoulderR", "ArmR", "Barrel"],
	"legs": ["LegPivotL", "LegPivotR", "RearLegPivotL", "RearLegPivotR"],
}


func _mark_broken_visual(part: String) -> void:
	if visual == null:
		return
	for node_name in BROKEN_VISUAL.get(part, []):
		var node: Node3D = visual.get_node_or_null(node_name)
		if node != null:
			_tint(node, Color(0.12, 0.1, 0.1))


## 機種に応じて機体の大きさ・脚の数・当たり判定・部品の位置を変える
## （仮の機体は全高 4m で作ってあるので、機種の全高に合わせて倍率をかける）
const BASE_HEIGHT := 4.0
const BASE_SEAT_Y := 3.0
const BASE_WEAPON_POS := Vector3(1.3, 1.75, -1.45)
## 部位ごとの当たり判定の位置（全高 4m のときの値）
const BASE_PART_POS := {
	"HitHead": Vector3(0, 3.9, -0.1),
	"HitArmL": Vector3(-1.3, 2.7, 0),
	"HitArmR": Vector3(1.3, 2.7, 0),
	"HitLegs": Vector3(0, 1.0, 0),
}


func _base_part_position(node_name: String) -> Vector3:
	return BASE_PART_POS.get(node_name, Vector3.ZERO)


func _apply_machine_shape(stats: Dictionary) -> void:
	height = float(stats.get("height", 12.0))
	var factor := height / BASE_HEIGHT
	if visual != null:
		visual.scale = Vector3.ONE * factor
	# 当たり判定（カプセル）も同じ倍率にする
	var collision: CollisionShape3D = get_node_or_null("Collision")
	if collision != null and collision.shape is CapsuleShape3D:
		var shape: CapsuleShape3D = collision.shape.duplicate()
		shape.radius = 1.0 * factor
		shape.height = BASE_HEIGHT * factor
		collision.shape = shape
		collision.position = Vector3(0, BASE_HEIGHT * 0.5 * factor, 0)
	# 部位ごとの当たり判定も同じ倍率にする
	for node_name in PART_SHAPES:
		var hit: CollisionShape3D = get_node_or_null(node_name)
		if hit == null:
			continue
		hit.scale = Vector3.ONE * factor
		hit.position = _base_part_position(node_name) * factor
	# 操縦席と銃口の位置
	var seat: Node3D = get_node_or_null("DriverSeat")
	if seat != null:
		seat.position = Vector3(0, BASE_SEAT_Y * factor, 0)
	var w: Node3D = get_node_or_null("Weapon")
	if w != null:
		w.position = BASE_WEAPON_POS * factor
	# 四脚なら後脚を出す
	var quad := str(stats.get("legs", "biped")) == "quad"
	for node_name in ["RearLegPivotL", "RearLegPivotR"]:
		var leg: Node3D = visual.get_node_or_null(node_name) if visual != null else null
		if leg != null:
			leg.visible = quad


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
	# 四脚のときは後脚を前脚と逆に振る
	var rear_l: Node3D = visual.get_node_or_null("RearLegPivotL")
	var rear_r: Node3D = visual.get_node_or_null("RearLegPivotR")
	if rear_l != null and rear_l.visible:
		rear_l.rotation.x = -swing
		rear_r.rotation.x = swing
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
