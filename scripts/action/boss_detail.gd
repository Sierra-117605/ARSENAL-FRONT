class_name BossDetail
extends RefCounted
## ボス（レールガン要塞）の見た目を作り込む（TODO N8-2）。
##
## 画像やモデルのファイルは使わず、箱と円柱を計算で並べる。
## 当たり判定（Collision）と部位の仕組み（stage・part_label）には触らず、
## 見た目のノード（Mesh）の**子**として足すだけ。
##
## 部位ごとに形を変えて、遠くからでも「どこが砲台で、どこが砲身か」が分かるようにする。

## 要塞の装甲色
static func armor(tone: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30 * tone, 0.30 * tone, 0.28 * tone)
	m.metallic = 0.45
	m.roughness = 0.6
	return m


## 影になる溝・機械部
static func dark() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.1, 0.11)
	m.metallic = 0.7
	m.roughness = 0.4
	return m


## 光る部分（発電施設の炉心・中枢の目）
static func glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 3.0
	return m


static func _box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3,
		material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = pos
	node.material_override = material
	parent.add_child(node)
	return node


static func _tube(parent: Node3D, node_name: String, radius: float, height: float,
		pos: Vector3, material: StandardMaterial3D, axis: String = "y") -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = pos
	if axis == "z":
		node.rotation.x = deg_to_rad(90.0)
	elif axis == "x":
		node.rotation.z = deg_to_rad(90.0)
	node.material_override = material
	parent.add_child(node)
	return node


## 部位 1 つを作り込む。kind は "turret" / "generator" / "core" / "barrel"
static func add_part_details(mesh_node: Node3D, kind: String) -> void:
	if mesh_node == null or mesh_node.has_meta("detailed"):
		return
	mesh_node.set_meta("detailed", true)
	var plate := armor()
	var d := dark()
	match kind:
		"turret":
			# 迎撃砲台：台座 → 旋回部 → 2 連装の砲
			_box(mesh_node, "TurretRing", Vector3(11.0, 1.6, 11.0), Vector3(0, -4.6, 0), d)
			_box(mesh_node, "TurretHouse", Vector3(8.4, 4.2, 9.0), Vector3(0, 3.4, -0.6), plate)
			_box(mesh_node, "TurretVisor", Vector3(6.4, 1.2, 0.6), Vector3(0, 3.6, 4.4), glow(Color(0.95, 0.35, 0.2)))
			_tube(mesh_node, "GunL", 0.9, 9.0, Vector3(-1.8, 2.6, 6.0), d, "z")
			_tube(mesh_node, "GunR", 0.9, 9.0, Vector3(1.8, 2.6, 6.0), d, "z")
			_box(mesh_node, "TurretBrace", Vector3(10.0, 1.0, 1.4), Vector3(0, 0.6, 3.0), d)
		"generator":
			# 発電施設：冷却塔と配管、中央に光る炉心
			_tube(mesh_node, "TowerL", 2.6, 9.0, Vector3(-2.8, 7.0, 0.5), plate)
			_tube(mesh_node, "TowerR", 2.6, 9.0, Vector3(2.8, 7.0, 0.5), plate)
			_tube(mesh_node, "TowerCapL", 3.0, 1.2, Vector3(-2.8, 11.6, 0.5), d)
			_tube(mesh_node, "TowerCapR", 3.0, 1.2, Vector3(2.8, 11.6, 0.5), d)
			_box(mesh_node, "CoreGlow", Vector3(5.0, 3.0, 0.8), Vector3(0, 1.0, 5.2), glow(Color(0.3, 0.8, 1.0)))
			_tube(mesh_node, "PipeTop", 0.8, 9.0, Vector3(0, 9.0, 0.5), d, "x")
			_box(mesh_node, "GenBase", Vector3(11.5, 2.2, 11.5), Vector3(0, -4.2, 0), d)
		"core":
			# 中枢：段重ねの掩体。正面に光る帯
			_box(mesh_node, "CoreStep1", Vector3(11.5, 2.0, 11.5), Vector3(0, -4.0, 0), d)
			_box(mesh_node, "CoreStep2", Vector3(9.0, 3.0, 9.4), Vector3(0, 3.6, 0), plate)
			_box(mesh_node, "CoreSlit", Vector3(7.0, 1.4, 0.7), Vector3(0, 1.6, 5.2), glow(Color(1.0, 0.3, 0.2)))
			_box(mesh_node, "CoreFinL", Vector3(0.9, 6.0, 7.0), Vector3(-5.4, 1.0, 0.5), d)
			_box(mesh_node, "CoreFinR", Vector3(0.9, 6.0, 7.0), Vector3(5.4, 1.0, 0.5), d)
			_tube(mesh_node, "CoreMast", 0.5, 7.0, Vector3(0, 8.5, 2.0), d)
		"barrel":
			# レールガン砲身：上下のレール・補強帯・砲口
			_box(mesh_node, "RailTop", Vector3(3.6, 1.0, 10.6), Vector3(0, 5.4, 0), d)
			_box(mesh_node, "RailBottom", Vector3(3.6, 1.0, 10.6), Vector3(0, -5.4, 0), d)
			_box(mesh_node, "RailSideL", Vector3(0.9, 7.0, 10.6), Vector3(-5.2, 0, 0), plate)
			_box(mesh_node, "RailSideR", Vector3(0.9, 7.0, 10.6), Vector3(5.2, 0, 0), plate)
			for i in 3:
				var z := -3.6 + float(i) * 3.6
				_box(mesh_node, "Band%d" % i, Vector3(12.0, 12.0, 0.26), Vector3(0, 0, z), d)
			_box(mesh_node, "MuzzleGlow", Vector3(5.0, 5.0, 0.5), Vector3(0, 0, 5.3), glow(Color(0.45, 0.75, 1.0)))


## 要塞の土台を作り込む（外壁・銃眼・搬入路・鉄塔）
static func add_base_details(base_mesh: Node3D) -> void:
	if base_mesh == null or base_mesh.has_meta("detailed"):
		return
	base_mesh.set_meta("detailed", true)
	var plate := armor()
	var plate_dark := armor(0.75)
	var d := dark()
	# 外周の壁（土台の上面 y=6 のあたり。土台は 190×12×120）
	_box(base_mesh, "WallFront", Vector3(190.0, 5.0, 4.0), Vector3(0, 8.5, 58.0), plate)
	_box(base_mesh, "WallLeft", Vector3(4.0, 5.0, 120.0), Vector3(-93.0, 8.5, 0), plate)
	_box(base_mesh, "WallRight", Vector3(4.0, 5.0, 120.0), Vector3(93.0, 8.5, 0), plate)
	# 正面の壁の銃眼（等間隔の切れ目）
	for i in 9:
		var x := -80.0 + float(i) * 20.0
		_box(base_mesh, "Embrasure%d" % i, Vector3(6.0, 2.2, 5.0), Vector3(x, 9.6, 58.0), d)
	# 土台の段差（手前が低く、奥が高い要塞らしい積み方）
	_box(base_mesh, "Terrace", Vector3(150.0, 4.0, 46.0), Vector3(0, 8.0, -28.0), plate_dark)
	_box(base_mesh, "TerraceEdge", Vector3(150.0, 1.2, 2.0), Vector3(0, 10.4, -5.0), d)
	# 搬入路（手前中央のスロープ）
	_box(base_mesh, "Ramp", Vector3(26.0, 1.0, 26.0), Vector3(0, 6.2, 46.0), plate_dark)
	# 鉄塔とアンテナ
	for side: float in [-1.0, 1.0]:
		var x := side * 70.0
		_tube(base_mesh, "Mast%s" % ("L" if side < 0.0 else "R"), 1.0, 26.0, Vector3(x, 19.0, -44.0), d)
		_box(base_mesh, "MastTop%s" % ("L" if side < 0.0 else "R"), Vector3(5.0, 1.2, 5.0),
			Vector3(x, 31.5, -44.0), d)
		_box(base_mesh, "Light%s" % ("L" if side < 0.0 else "R"), Vector3(1.4, 1.4, 1.4),
			Vector3(x, 32.6, -44.0), glow(Color(1.0, 0.25, 0.15)))
