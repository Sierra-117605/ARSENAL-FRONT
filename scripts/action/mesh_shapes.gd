class_name MeshShapes
extends RefCounted
## 機体の装甲の「形」を計算で作る土台（SPEC §0.18 / TODO N8-2）。
##
## 3D モデルのファイルは使わない。ここで作るのは次の 1 種類だけで、
## 寸法と角の落とし方を変えるだけで、胴・肩・脚・頭などを作り分ける。
##
##   八角柱（はっかくちゅう）：箱の縦の角 4 本を斜めに落とした形。
##   上面と底面の大きさを別々に指定できるので、台形（上すぼまり・下すぼまり）にもできる。
##
## 角を落とすと、平らな面と斜めの面の境目に影の線が出る。
## これが「角張った多層装甲」に見える一番の近道（箱のままだと影の線が 1 本しか出ない）。

## 八角柱を作る
## bottom_w/bottom_d：底面の幅と奥行き、top_w/top_d：上面の幅と奥行き
## height：高さ、cut：角を落とす量（メートル）、lean_z：上面を前後にずらす量
static func angled_block(bottom_w: float, bottom_d: float, top_w: float, top_d: float,
		height: float, cut: float, lean_z: float = 0.0) -> ArrayMesh:
	var bottom := _octagon(bottom_w, bottom_d, cut, -height * 0.5, 0.0)
	var top := _octagon(top_w, top_d, cut, height * 0.5, lean_z)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	# 側面（8 枚）
	for i in 8:
		var j := (i + 1) % 8
		_quad(verts, normals, bottom[i], bottom[j], top[j], top[i])
	# 上面と底面（八角形を扇形に分ける）
	for i in range(1, 7):
		_tri(verts, normals, top[0], top[i], top[i + 1])
		_tri(verts, normals, bottom[0], bottom[i + 1], bottom[i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## くさび形（片側が薄くなる板）。肩の張り出しや脛当てに使う
static func wedge(width: float, thick_front: float, thick_back: float, depth: float) -> ArrayMesh:
	var hw := width * 0.5
	var hd := depth * 0.5
	var f := thick_front * 0.5
	var b := thick_back * 0.5
	var p := [
		Vector3(-hw, -b, hd), Vector3(hw, -b, hd), Vector3(hw, b, hd), Vector3(-hw, b, hd),
		Vector3(-hw, -f, -hd), Vector3(hw, -f, -hd), Vector3(hw, f, -hd), Vector3(-hw, f, -hd),
	]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	_quad(verts, normals, p[0], p[1], p[2], p[3])  # 後ろ
	_quad(verts, normals, p[5], p[4], p[7], p[6])  # 前
	_quad(verts, normals, p[4], p[5], p[1], p[0])  # 下
	_quad(verts, normals, p[3], p[2], p[6], p[7])  # 上
	_quad(verts, normals, p[4], p[0], p[3], p[7])  # 左
	_quad(verts, normals, p[1], p[5], p[6], p[2])  # 右
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 角を落とした八角形の頂点を返す（時計回り）
static func _octagon(width: float, depth: float, cut: float, y: float, offset_z: float) -> Array:
	var hw := width * 0.5
	var hd := depth * 0.5
	var c := minf(cut, minf(hw, hd) * 0.9)
	return [
		Vector3(-hw + c, y, hd + offset_z), Vector3(hw - c, y, hd + offset_z),
		Vector3(hw, y, hd - c + offset_z), Vector3(hw, y, -hd + c + offset_z),
		Vector3(hw - c, y, -hd + offset_z), Vector3(-hw + c, y, -hd + offset_z),
		Vector3(-hw, y, -hd + c + offset_z), Vector3(-hw, y, hd - c + offset_z),
	]


## 四角形を 2 枚の三角形として足す（面ごとに向きを計算＝角がはっきり出る）
static func _quad(verts: PackedVector3Array, normals: PackedVector3Array,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(verts, normals, a, b, c)
	_tri(verts, normals, a, c, d)


## 三角形を 1 枚足す
static func _tri(verts: PackedVector3Array, normals: PackedVector3Array,
		a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length() < 0.000001:
		return
	n = n.normalized()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	normals.append(n)
	normals.append(n)
	normals.append(n)
