class_name BossFortress
extends Node3D
## レールガン要塞（SPEC §0.8）。3 段階で戦う。
##   段階1：迎撃砲台をすべて壊す
##   段階2：発電施設を壊して防御を落とす
##   段階3：露出した砲身と中枢を壊せば勝利
## 一定時間ごとにレールガンが発射され、プレイヤーも狙われる（物陰に隠れる必要がある）。

## レールガンの発射間隔（秒）
@export var railgun_interval: float = 22.0
## 発射までの予兆の長さ（秒）
@export var warning_time: float = 4.0
## レールガンの威力（物陰にいなければこれだけ受ける）
@export var railgun_damage: int = 120

## 今の段階（1〜3）。すべて壊すと 4（撃破）
var stage: int = 1
## 次の発射までの残り時間
var railgun_timer: float = 0.0
## 予兆が出ているか
var warning: bool = false

## 段階が進んだ時に知らせる
signal stage_changed(stage: int)
## 要塞を破壊した時に知らせる
signal fortress_destroyed
## レールガンの予兆が始まった／発射した時に知らせる
signal railgun_warning
signal railgun_fired


func _ready() -> void:
	railgun_timer = railgun_interval
	for part in parts():
		part.destroyed.connect(_on_part_destroyed.bind(part))
	_activate_stage(1)


func _physics_process(delta: float) -> void:
	if stage > 3:
		return
	railgun_timer -= delta
	if not warning and railgun_timer <= warning_time:
		warning = true
		GameLog.write("ボス", "レールガンの発射予兆")
		railgun_warning.emit()
	if railgun_timer <= 0.0:
		_fire_railgun()
		railgun_timer = railgun_interval
		warning = false


## この要塞の部位をすべて返す
func parts() -> Array[BossPart]:
	var list: Array[BossPart] = []
	_collect_parts(self, list)
	return list


func _collect_parts(node: Node, list: Array[BossPart]) -> void:
	for child in node.get_children():
		if child is BossPart:
			list.append(child)
		_collect_parts(child, list)


## その段階の部位だけを返す
func parts_of_stage(target_stage: int) -> Array[BossPart]:
	var list: Array[BossPart] = []
	for part in parts():
		if part.stage == target_stage:
			list.append(part)
	return list


## その段階の部位が全部壊れたか
func stage_cleared(target_stage: int) -> bool:
	for part in parts_of_stage(target_stage):
		if part.is_alive():
			return false
	return true


## 今の段階の部位だけ攻撃を受け付けるようにする
func _activate_stage(new_stage: int) -> void:
	stage = new_stage
	for part in parts_of_stage(new_stage):
		part.activate()
	GameLog.write("ボス", "段階 %d：%s" % [new_stage, {
		1: "迎撃砲台を破壊せよ",
		2: "発電施設を破壊せよ",
		3: "砲身と中枢を破壊せよ",
	}.get(new_stage, "")])
	stage_changed.emit(new_stage)


func _on_part_destroyed(part: BossPart) -> void:
	GameLog.write("ボス", "%s を破壊" % part.part_label)
	if not stage_cleared(stage):
		return
	if stage >= 3:
		stage = 4
		GameLog.write("ボス", "要塞を撃破した")
		fortress_destroyed.emit()
		return
	# 次の段階へ（防御が落ちて、レールガンの間隔も縮まる）
	railgun_interval = maxf(railgun_interval - 5.0, 10.0)
	_activate_stage(stage + 1)


## レールガン発射：物陰に隠れていない自軍機に大ダメージ
func _fire_railgun() -> void:
	railgun_fired.emit()
	GameLog.write("ボス", "レールガン発射")
	var muzzle: Node3D = get_node_or_null("RailgunMuzzle")
	var from: Vector3 = muzzle.global_position if muzzle != null else global_position
	# 自分（要塞）の部位は遮蔽に数えない
	var ignore: Array[RID] = []
	for part in parts():
		ignore.append(part.get_rid())
	var base: CollisionObject3D = get_node_or_null("Base")
	if base != null:
		ignore.append(base.get_rid())
	for node in get_tree().get_nodes_in_group("team_player"):
		var target := node as Pilotable
		if target == null or not target.is_alive() or not target.visible:
			continue
		var aim := target.global_position + Vector3(0, 4, 0)
		var query := PhysicsRayQueryParameters3D.create(from, aim)
		query.exclude = ignore
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		# 間に何も無ければ直撃（物陰にいれば助かる）
		if hit.is_empty() or hit["collider"] == target:
			target.take_hit(railgun_damage)
			GameLog.write("ボス", "%s にレールガンが直撃（-%d）" % [target.name, railgun_damage])
