class_name MechDetail
extends RefCounted
## ロボットの形を作り込む（SPEC §0.18 / TODO N8-2）。
##
## やっていること：
##  1. 胴・頭・腰・肩・脚・足・背面ユニットの**形そのもの**を、箱から
##     「角を落とした八角柱（台形）」に差し替える（MeshShapes）
##  2. その上に装甲板・関節の軸・排気口などを重ねる
##
## 形の方針（SPEC §0.18）：角張った多層の装甲／細い腰と長く太い脚／
## 大きな背面の推進ユニット／関節と駆動部が外から見える／肩が大きく張り出す。
##
## 既存のノード名・当たり判定・部位ダメージの仕組みには触れない。
## 名前が "Dark" で始まる部品は機体色で塗り替えない（装甲の切れ目を見せるため）。

## 形は全機体で共通なので、一度作って使い回す
static var _shapes: Dictionary = {}


static func _shape(key: String, maker: Callable) -> ArrayMesh:
	if not _shapes.has(key):
		_shapes[key] = maker.call()
	return _shapes[key]


## 塗装した装甲（つや消し。縁にうっすら光が乗る）
static func painted_armor(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.12
	m.metallic_specular = 0.4
	m.roughness = 0.68
	m.rim_enabled = true
	m.rim = 0.45
	m.rim_tint = 0.35
	return m


## むき出しの金属（関節・砲身・排気口）
static func bare_metal() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.14, 0.145, 0.155)
	m.metallic = 0.85
	m.metallic_specular = 0.6
	m.roughness = 0.33
	m.rim_enabled = true
	m.rim = 0.5
	m.rim_tint = 0.2
	return m


## 計器・センサーの光
static func sensor_glow(color: Color = Color(1.0, 0.45, 0.12)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.4
	return m


static func _box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3,
		material: StandardMaterial3D, rot_x: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _attach(parent, node_name, mesh, pos, material, rot_x)


static func _tube(parent: Node3D, node_name: String, radius: float, height: float,
		pos: Vector3, material: StandardMaterial3D, lay_down: bool = false) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	return _attach(parent, node_name, mesh, pos, material, 90.0 if lay_down else 0.0)


static func _attach(parent: Node3D, node_name: String, mesh: Mesh, pos: Vector3,
		material: StandardMaterial3D, rot_x: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = pos
	if rot_x != 0.0:
		node.rotation.x = deg_to_rad(rot_x)
	node.material_override = material
	parent.add_child(node)
	return node


## 既にある部品の「形」だけを差し替える（名前・位置・親子関係はそのまま）
static func _reshape(visual: Node3D, node_path: String, mesh: Mesh) -> void:
	var node := visual.get_node_or_null(node_path) as MeshInstance3D
	if node != null:
		node.mesh = mesh


## ロボットの見た目を作り込む。visual は Robot の "Visual" ノード
static func add_details(visual: Node3D) -> void:
	if visual == null or visual.has_meta("detailed"):
		return
	visual.set_meta("detailed", true)
	var dark := bare_metal()
	var plate := painted_armor(Color(0.3, 0.335, 0.26))
	var glow := sensor_glow()

	_reshape_body(visual)

	# --- 胴体：胸の傾斜装甲・襟・脇の排気口・腰の機械部
	var torso := visual.get_node_or_null("Torso") as Node3D
	if torso != null:
		_attach(torso, "ChestPlate", _shape("chest", func(): return MeshShapes.angled_block(
			1.45, 0.3, 1.15, 0.22, 0.8, 0.16, -0.06)), Vector3(0, 0.12, -0.6), plate, -10.0)
		_box(torso, "DarkChestVent", Vector3(0.85, 0.14, 0.1), Vector3(0, -0.4, -0.66), dark)
		_attach(torso, "CollarL", _shape("collar", func(): return MeshShapes.wedge(
			0.5, 0.18, 0.42, 0.52)), Vector3(-0.76, 0.6, -0.12), plate)
		_attach(torso, "CollarR", _shape("collar", func(): return MeshShapes.wedge(
			0.5, 0.18, 0.42, 0.52)), Vector3(0.76, 0.6, -0.12), plate)
		_box(torso, "DarkSideVentL", Vector3(0.1, 0.56, 0.66), Vector3(-0.96, -0.1, 0.06), dark)
		_box(torso, "DarkSideVentR", Vector3(0.1, 0.56, 0.66), Vector3(0.96, -0.1, 0.06), dark)
		_box(torso, "DarkWaistJoint", Vector3(1.0, 0.3, 0.85), Vector3(0, -0.76, 0), dark)
		_box(torso, "SensorPod", Vector3(0.16, 0.1, 0.06), Vector3(-0.5, 0.3, -0.62), glow)

	# --- 腰：前後と左右のスカート装甲（細い腰を強調する）
	var hip := visual.get_node_or_null("Hip") as Node3D
	if hip != null:
		_attach(hip, "SkirtFront", _shape("skirt_f", func(): return MeshShapes.wedge(
			1.15, 0.1, 0.3, 0.6)), Vector3(0, -0.3, -0.42), plate, -14.0)
		_attach(hip, "SkirtBack", _shape("skirt_b", func(): return MeshShapes.wedge(
			1.15, 0.1, 0.26, 0.5)), Vector3(0, -0.3, 0.42), plate, 14.0)
		_attach(hip, "SkirtSideL", _shape("skirt_s", func(): return MeshShapes.angled_block(
			0.18, 0.66, 0.14, 0.5, 0.66, 0.08)), Vector3(-0.84, -0.3, 0), plate)
		_attach(hip, "SkirtSideR", _shape("skirt_s", func(): return MeshShapes.angled_block(
			0.18, 0.66, 0.14, 0.5, 0.66, 0.08)), Vector3(0.84, -0.3, 0), plate)

	# --- 頭：とさか・頬当て・アンテナ・単眼センサー
	var head := visual.get_node_or_null("Head") as Node3D
	if head != null:
		_attach(head, "Crest", _shape("crest", func(): return MeshShapes.wedge(
			0.22, 0.08, 0.3, 0.5)), Vector3(0, 0.3, 0.02), plate)
		_box(head, "DarkCheekL", Vector3(0.09, 0.26, 0.46), Vector3(-0.33, -0.06, 0.02), dark)
		_box(head, "DarkCheekR", Vector3(0.09, 0.26, 0.46), Vector3(0.33, -0.06, 0.02), dark)
		_tube(head, "DarkAntenna", 0.022, 0.66, Vector3(-0.27, 0.5, 0.2), dark)
		_box(head, "SensorEye", Vector3(0.14, 0.07, 0.04), Vector3(0.22, 0.04, -0.38), glow)

	# --- 肩：外へ張り出す肩当て（上に厚く、外へ向かって薄くなる）
	for side: float in [-1.0, 1.0]:
		var node_name := "ShoulderL" if side < 0.0 else "ShoulderR"
		var shoulder := visual.get_node_or_null(node_name) as Node3D
		if shoulder == null:
			continue
		_attach(shoulder, "Pauldron", _shape("pauldron", func(): return MeshShapes.angled_block(
			0.95, 1.05, 0.66, 0.78, 0.5, 0.2)), Vector3(side * 0.16, 0.34, 0), plate)
		_attach(shoulder, "PauldronSkirt", _shape("pauldron_s", func(): return MeshShapes.wedge(
			0.9, 0.12, 0.34, 0.95)), Vector3(side * 0.24, -0.06, 0), plate)
		_tube(shoulder, "DarkShoulderAxis", 0.18, 0.72, Vector3(side * -0.2, 0.08, 0), dark, false)
		_box(shoulder, "DarkShoulderBlock", Vector3(0.26, 0.4, 0.4), Vector3(side * -0.34, -0.06, 0), dark)

	# --- 左腕：前腕装甲・肘の軸・手
	var arm_l := visual.get_node_or_null("ArmL") as Node3D
	if arm_l != null:
		_attach(arm_l, "ForearmPlate", _shape("forearm", func(): return MeshShapes.angled_block(
			0.52, 0.56, 0.44, 0.46, 0.78, 0.12)), Vector3(-0.08, -0.3, -0.04), plate)
		_tube(arm_l, "DarkElbow", 0.19, 0.6, Vector3(0, 0.3, 0), dark, true)
		_box(arm_l, "DarkHand", Vector3(0.32, 0.28, 0.38), Vector3(0, -0.8, -0.06), dark)

	# --- 右腕（狙う方向へ回る側）：前腕装甲・弾倉・肘の軸
	var arm_pivot := visual.get_node_or_null("ArmPivotR") as Node3D
	if arm_pivot != null:
		_attach(arm_pivot, "ForearmPlateR", _shape("forearm", func(): return MeshShapes.angled_block(
			0.52, 0.56, 0.44, 0.46, 0.78, 0.12)), Vector3(0.06, -0.5, -0.08), plate)
		_box(arm_pivot, "DarkMagazine", Vector3(0.28, 0.46, 0.32), Vector3(0.32, -1.0, 0.1), dark)
		_tube(arm_pivot, "DarkElbowR", 0.19, 0.6, Vector3(0, -0.1, 0), dark, true)
	var barrel := visual.get_node_or_null("ArmPivotR/Barrel") as Node3D
	if barrel != null:
		_tube(barrel, "DarkBrake1", 0.13, 0.1, Vector3(0, 0.62, 0), dark)
		_tube(barrel, "DarkBrake2", 0.12, 0.08, Vector3(0, 0.44, 0), dark)
		_tube(barrel, "DarkBarrelBase", 0.17, 0.26, Vector3(0, -0.6, 0), dark)

	# --- 脚：太もも装甲・膝の軸・すね当て・動力シリンダー・つま先
	for side: float in [-1.0, 1.0]:
		var pivot := visual.get_node_or_null("LegPivotL" if side < 0.0 else "LegPivotR") as Node3D
		if pivot == null:
			continue
		var leg := pivot.get_node_or_null("LegL" if side < 0.0 else "LegR") as Node3D
		if leg != null:
			_attach(leg, "ThighPlate", _shape("thigh", func(): return MeshShapes.angled_block(
				0.76, 0.3, 0.6, 0.24, 0.78, 0.12)), Vector3(0, 0.4, -0.42), plate, -7.0)
			_tube(leg, "DarkKneeAxis", 0.21, 0.82, Vector3(0, -0.14, -0.04), dark, false)
			_attach(leg, "ShinPlate", _shape("shin", func(): return MeshShapes.wedge(
				0.68, 0.14, 0.36, 0.78)), Vector3(0, -0.56, -0.4), plate, 6.0)
			_tube(leg, "DarkPiston", 0.07, 1.0, Vector3(side * 0.4, -0.1, 0.34), dark)
			_box(leg, "DarkThighJoint", Vector3(0.5, 0.26, 0.5), Vector3(0, 0.84, 0), dark)
		var foot := pivot.get_node_or_null("FootL" if side < 0.0 else "FootR") as Node3D
		if foot != null:
			_attach(foot, "Toe", _shape("toe", func(): return MeshShapes.angled_block(
				0.82, 0.4, 0.66, 0.3, 0.2, 0.1)), Vector3(0, 0.02, -0.7), plate)
			_box(foot, "DarkHeel", Vector3(0.58, 0.2, 0.28), Vector3(0, 0, 0.6), dark)

	# --- 背面ユニット：大きな推進器と放熱板（輪郭を後ろ側で大きく見せる）
	var pack := visual.get_node_or_null("BackPack") as Node3D
	if pack != null:
		_tube(pack, "DarkThrusterL", 0.24, 0.66, Vector3(-0.46, 0.1, 0.5), dark, true)
		_tube(pack, "DarkThrusterR", 0.24, 0.66, Vector3(0.46, 0.1, 0.5), dark, true)
		_box(pack, "ThrusterGlowL", Vector3(0.3, 0.3, 0.08), Vector3(-0.46, 0.1, 0.84), sensor_glow(Color(0.45, 0.7, 1.0)))
		_box(pack, "ThrusterGlowR", Vector3(0.3, 0.3, 0.08), Vector3(0.46, 0.1, 0.84), sensor_glow(Color(0.45, 0.7, 1.0)))
		_attach(pack, "RadiatorFinL", _shape("fin", func(): return MeshShapes.wedge(
			0.1, 0.5, 0.9, 0.5)), Vector3(-0.78, 0.3, 0.1), plate)
		_attach(pack, "RadiatorFinR", _shape("fin", func(): return MeshShapes.wedge(
			0.1, 0.5, 0.9, 0.5)), Vector3(0.78, 0.3, 0.1), plate)
		_box(pack, "DarkRadiator", Vector3(1.0, 0.44, 0.1), Vector3(0, -0.3, 0.32), dark)


## 主要な部品の形を、箱から「角を落とした台形」に差し替える
static func _reshape_body(visual: Node3D) -> void:
	# 胸は上が広く、腰に向かって細くなる
	_reshape(visual, "Torso", _shape("torso", func(): return MeshShapes.angled_block(
		1.5, 1.05, 2.05, 1.35, 1.4, 0.3, -0.05)))
	_reshape(visual, "Hip", _shape("hip", func(): return MeshShapes.angled_block(
		1.5, 0.95, 1.25, 0.82, 0.5, 0.2)))
	_reshape(visual, "Head", _shape("head", func(): return MeshShapes.angled_block(
		0.68, 0.8, 0.5, 0.62, 0.5, 0.14, -0.04)))
	for node_name in ["ShoulderL", "ShoulderR"]:
		_reshape(visual, node_name, _shape("shoulder", func(): return MeshShapes.angled_block(
			0.62, 0.84, 0.56, 0.72, 0.6, 0.16)))
	# 脚は上が太く、足首に向かって細くなる
	for path in ["LegPivotL/LegL", "LegPivotR/LegR", "RearLegPivotL/RearLegL", "RearLegPivotR/RearLegR"]:
		_reshape(visual, path, _shape("leg", func(): return MeshShapes.angled_block(
			0.8, 0.88, 0.6, 0.68, 1.8, 0.18)))
	for path in ["LegPivotL/FootL", "LegPivotR/FootR", "RearLegPivotL/RearFootL", "RearLegPivotR/RearFootR"]:
		_reshape(visual, path, _shape("foot", func(): return MeshShapes.angled_block(
			0.96, 1.36, 0.8, 1.16, 0.3, 0.14)))
	# 背面ユニットは大きく張り出させる
	_reshape(visual, "BackPack", _shape("pack", func(): return MeshShapes.angled_block(
		1.5, 0.8, 1.2, 0.56, 1.25, 0.22)))
