class_name MechDetail
extends RefCounted
## ロボットの見た目を細かく作り込む（TODO N8-2）。
##
## 画像やモデルのファイルは使わず、箱と円柱だけを**計算で並べて**装甲板・肩当て・
## 膝当て・排気口などを足す。既存の部品（Torso・Head・ShoulderL/R・ArmPivotR・
## LegPivotL/R・BackPack・Barrel）の**子として**足すので、
##  - 部位が壊れた時の色替え（BROKEN_VISUAL）
##  - パーツごとの大きさ変更（VISUAL_PARTS）
##  - 当たり判定・銃口の位置
## には一切触らない。
##
## 名前が "Dark" で始まる部品は、機体色で塗り替える処理の対象外にして、
## 濃い色のままにする（敵機でも装甲の切れ目が見えるように）。

## 装甲の継ぎ目などに使う濃い金属色
static func dark_metal() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.135, 0.14)
	m.metallic = 0.65
	m.roughness = 0.42
	return m


## 機体の主な装甲に使う色（機体色で塗り替えられる前提の下地）
static func plate_metal() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.29, 0.33, 0.25)
	m.metallic = 0.4
	m.roughness = 0.55
	return m


## 光るセンサー類
static func sensor_glow() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.45, 0.15)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.12)
	m.emission_energy_multiplier = 2.2
	return m


## 箱の部品を 1 つ足す
static func _box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3,
		material: StandardMaterial3D, rot_x: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = pos
	if rot_x != 0.0:
		node.rotation.x = deg_to_rad(rot_x)
	node.material_override = material
	parent.add_child(node)
	return node


## 円柱の部品を 1 つ足す（横倒しにもできる）
static func _tube(parent: Node3D, node_name: String, radius: float, height: float,
		pos: Vector3, material: StandardMaterial3D, lay_down: bool = false) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = pos
	if lay_down:
		node.rotation.x = deg_to_rad(90.0)
	node.material_override = material
	parent.add_child(node)
	return node


## ロボットの見た目に装甲を足す。visual は Robot の "Visual" ノード
static func add_details(visual: Node3D) -> void:
	if visual == null or visual.has_meta("detailed"):
		return
	visual.set_meta("detailed", true)
	var dark := dark_metal()
	var plate := plate_metal()
	var glow := sensor_glow()

	# --- 胴体：胸の傾斜装甲・襟・脇の排気口・腰の機械部
	var torso := visual.get_node_or_null("Torso") as Node3D
	if torso != null:
		_box(torso, "ChestPlate", Vector3(1.5, 0.78, 0.22), Vector3(0, 0.12, -0.66), plate, -12.0)
		_box(torso, "DarkChestVent", Vector3(0.9, 0.16, 0.1), Vector3(0, -0.42, -0.69), dark)
		_box(torso, "CollarL", Vector3(0.45, 0.3, 0.5), Vector3(-0.72, 0.62, -0.18), plate)
		_box(torso, "CollarR", Vector3(0.45, 0.3, 0.5), Vector3(0.72, 0.62, -0.18), plate)
		_box(torso, "DarkSideVentL", Vector3(0.12, 0.62, 0.72), Vector3(-1.0, -0.12, 0.08), dark)
		_box(torso, "DarkSideVentR", Vector3(0.12, 0.62, 0.72), Vector3(1.0, -0.12, 0.08), dark)
		_box(torso, "DarkWaist", Vector3(1.25, 0.34, 1.05), Vector3(0, -0.78, 0), dark)

	# --- 腰：前と横のスカート装甲（歩くと脚が覗く）
	var hip := visual.get_node_or_null("Hip") as Node3D
	if hip != null:
		_box(hip, "SkirtFront", Vector3(1.25, 0.62, 0.14), Vector3(0, -0.28, -0.46), plate, -8.0)
		_box(hip, "SkirtBack", Vector3(1.25, 0.5, 0.14), Vector3(0, -0.28, 0.46), plate, 8.0)
		_box(hip, "SkirtSideL", Vector3(0.16, 0.66, 0.7), Vector3(-0.86, -0.26, 0), plate)
		_box(hip, "SkirtSideR", Vector3(0.16, 0.66, 0.7), Vector3(0.86, -0.26, 0), plate)

	# --- 頭：とさか・頬当て・側面センサー
	var head := visual.get_node_or_null("Head") as Node3D
	if head != null:
		_box(head, "Crest", Vector3(0.2, 0.26, 0.52), Vector3(0, 0.3, 0.04), plate)
		_box(head, "DarkCheekL", Vector3(0.1, 0.28, 0.5), Vector3(-0.36, -0.06, 0.02), dark)
		_box(head, "DarkCheekR", Vector3(0.1, 0.28, 0.5), Vector3(0.36, -0.06, 0.02), dark)
		_tube(head, "Antenna", 0.025, 0.7, Vector3(-0.3, 0.52, 0.22), dark)
		_box(head, "SensorEye", Vector3(0.12, 0.08, 0.04), Vector3(0.26, 0.06, -0.41), glow)

	# --- 肩：肩当て（上に張り出す）と下側の縁
	for side: float in [-1.0, 1.0]:
		var node_name := "ShoulderL" if side < 0.0 else "ShoulderR"
		var shoulder := visual.get_node_or_null(node_name) as Node3D
		if shoulder == null:
			continue
		_box(shoulder, "Pauldron", Vector3(0.82, 0.4, 0.95), Vector3(side * 0.1, 0.3, 0), plate, 0.0)
		_box(shoulder, "PauldronLip", Vector3(0.72, 0.22, 0.85), Vector3(side * 0.16, 0.02, 0), plate)
		_box(shoulder, "DarkShoulderJoint", Vector3(0.3, 0.42, 0.42), Vector3(side * -0.3, -0.1, 0), dark)

	# --- 肘・膝の関節（外から見える軸）
	# （肩と腕のつなぎ目に太い軸を見せて、組み立て式の機械らしさを出す）

	# --- 左腕：前腕の装甲とマニピュレータ
	var arm_l := visual.get_node_or_null("ArmL") as Node3D
	if arm_l != null:
		_box(arm_l, "ForearmPlate", Vector3(0.5, 0.7, 0.52), Vector3(-0.1, -0.28, -0.06), plate)
		_box(arm_l, "DarkHand", Vector3(0.34, 0.3, 0.4), Vector3(0, -0.78, -0.08), dark)
		_tube(arm_l, "DarkElbowL", 0.19, 0.62, Vector3(0, -0.12, 0.0), dark, true)
		_box(arm_l, "ArmPlateThin", Vector3(0.14, 0.9, 0.44), Vector3(0.3, -0.3, 0.0), plate)

	# --- 右腕（狙う方向へ回る側）：前腕装甲・弾倉・銃口の制退器
	var arm_pivot := visual.get_node_or_null("ArmPivotR") as Node3D
	if arm_pivot != null:
		_box(arm_pivot, "ForearmPlateR", Vector3(0.52, 0.72, 0.56), Vector3(0.08, -0.5, -0.1), plate)
		_box(arm_pivot, "DarkMagazine", Vector3(0.3, 0.5, 0.34), Vector3(0.34, -1.05, 0.12), dark)
		_tube(arm_pivot, "DarkElbowR", 0.19, 0.62, Vector3(0, -0.14, 0.0), dark, true)
		_box(arm_pivot, "ArmPlateThinR", Vector3(0.14, 0.9, 0.46), Vector3(-0.3, -0.5, 0.0), plate)
	var barrel := visual.get_node_or_null("ArmPivotR/Barrel") as Node3D
	if barrel != null:
		# 砲身は横倒しの円柱なので、その子は砲身の「長さ方向」が Y 軸になる
		_tube(barrel, "DarkBrake1", 0.13, 0.1, Vector3(0, 0.62, 0), dark)
		_tube(barrel, "DarkBrake2", 0.12, 0.08, Vector3(0, 0.44, 0), dark)
		_tube(barrel, "DarkBarrelBase", 0.17, 0.26, Vector3(0, -0.6, 0), dark)

	# --- 脚：太もも装甲・膝当て・すね当て・つま先
	for side: float in [-1.0, 1.0]:
		var pivot_name := "LegPivotL" if side < 0.0 else "LegPivotR"
		var pivot := visual.get_node_or_null(pivot_name) as Node3D
		if pivot == null:
			continue
		var leg := pivot.get_node_or_null("LegL" if side < 0.0 else "LegR") as Node3D
		if leg != null:
			_box(leg, "ThighPlate", Vector3(0.78, 0.72, 0.2), Vector3(0, 0.38, -0.46), plate, -6.0)
			_box(leg, "DarkKnee", Vector3(0.62, 0.3, 0.3), Vector3(0, -0.18, -0.5), dark)
			_tube(leg, "DarkKneeAxis", 0.22, 0.86, Vector3(0, -0.18, -0.06), dark, false)
			_box(leg, "ThighPlateThin", Vector3(0.2, 0.6, 0.5), Vector3(side * 0.42, 0.42, -0.1), plate)
			_box(leg, "ShinPlate", Vector3(0.7, 0.66, 0.18), Vector3(0, -0.56, -0.44), plate, 5.0)
			_box(leg, "DarkLegPiston", Vector3(0.14, 1.1, 0.14), Vector3(side * 0.42, -0.1, 0.36), dark)
		var foot := pivot.get_node_or_null("FootL" if side < 0.0 else "FootR") as Node3D
		if foot != null:
			_box(foot, "Toe", Vector3(0.85, 0.2, 0.38), Vector3(0, 0.02, -0.72), plate)
			_box(foot, "DarkHeel", Vector3(0.6, 0.22, 0.3), Vector3(0, 0.0, 0.62), dark)

	# --- 背中の装置：排気口と放熱板
	var pack := visual.get_node_or_null("BackPack") as Node3D
	if pack != null:
		_tube(pack, "DarkExhaustL", 0.17, 0.5, Vector3(-0.42, 0.2, 0.42), dark, true)
		_tube(pack, "DarkExhaustR", 0.17, 0.5, Vector3(0.42, 0.2, 0.42), dark, true)
		_box(pack, "DarkRadiator", Vector3(1.1, 0.5, 0.12), Vector3(0, -0.2, 0.36), dark)
		_box(pack, "PackTop", Vector3(1.2, 0.16, 0.5), Vector3(0, 0.6, 0), plate)
