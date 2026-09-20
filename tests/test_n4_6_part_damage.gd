extends SceneTree
## 部位ダメージの確認（差別化の柱・案3。SPEC §0.13）。
##
## 確かめること：
##  1. 機体に部位ごとの耐久がある（頭・左腕・右腕・脚）
##  2. 当たった場所に応じて、その部位の耐久が減る
##  3. 右腕を壊すと武器が使えなくなる（撃てない）
##  4. 脚を壊すと歩く速さが大きく落ちる
##  5. 頭を壊すと遠くを狙えなくなる
##  6. 腕・脚に当てても本体へのダメージは小さい（頭は逆に大きい＝弱点）
##  7. 部位が壊れても、本体の耐久が残っていれば機体は動き続ける
##  8. 壊れた部位は保存データに残る
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n4_6_part_damage.gd

var field: Node
var robot: Robot
var enemy: Robot
var frame := 0
var failed := false
var broken_events: Array[String] = []


func _initialize() -> void:
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	robot = field.get_node("Robot")
	robot.use_saved_loadout = false
	enemy = field.get_node("Enemies/Enemy1")
	enemy.part_broken.connect(func(part: String): broken_events.append(part))


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			_report(enemy.part_hp.size() == 4, "部位が 4 つある (%s)" % [enemy.part_hp.keys()])
			_report(int(enemy.part_hp["arm_right"]) > 0 and int(enemy.part_hp["legs"]) > 0,
				"部位ごとの耐久：右腕 %d / 脚 %d / 頭 %d（本体 %d）" %
				[enemy.part_hp["arm_right"], enemy.part_hp["legs"], enemy.part_hp["head"], enemy.max_hp])
			# 2：右腕（HitArmR）に当てる
			var shape_index := _shape_index_of(enemy, "HitArmR")
			_report(shape_index >= 0, "右腕の当たり判定が見つかる")
			var before: int = enemy.part_hp["arm_right"]
			enemy.take_hit_at_shape(10, shape_index)
			_report(int(enemy.part_hp["arm_right"]) == before - 10,
				"当てた部位の耐久が減る (%d → %d)" % [before, enemy.part_hp["arm_right"]])
		15:
			# 3：右腕を壊す
			var shape_index := _shape_index_of(enemy, "HitArmR")
			_break_part(enemy, "arm_right", shape_index)
			_report(enemy.is_part_broken("arm_right"), "右腕が壊れた")
			_report(broken_events.has("arm_right"), "壊れたことが通知される")
			var weapon: Weapon = enemy.get_node("Weapon")
			_report(weapon.disabled, "右腕が壊れると武器が使えない")
			_report(not weapon.try_fire(robot.global_position, enemy), "実際に撃てない")
			_report(enemy.is_alive(), "部位が壊れても機体はまだ動く (本体 %d / %d)" % [enemy.hp, enemy.max_hp])
			_report(enemy.hp > enemy.max_hp - 40,
				"腕に当てても本体へのダメージは小さい (本体 %d / %d)" % [enemy.hp, enemy.max_hp])
		20:
			# 4：脚を壊す
			var speed_before := enemy.walk_speed
			var shape_index := _shape_index_of(enemy, "HitLegs")
			_break_part(enemy, "legs", shape_index)
			_report(enemy.is_part_broken("legs"), "脚が壊れた")
			_report(enemy.walk_speed < speed_before * 0.5,
				"脚が壊れると大きく減速する (%.1f → %.1f m/秒)" % [speed_before, enemy.walk_speed])
		25:
			# 5：頭を壊す
			var aim_before := enemy.aim_range
			var shape_index := _shape_index_of(enemy, "HitHead")
			_break_part(enemy, "head", shape_index)
			_report(enemy.is_part_broken("head"), "頭が壊れた")
			_report(enemy.aim_range < aim_before * 0.5,
				"頭が壊れると照準距離が落ちる (%.0f → %.0f m)" % [aim_before, enemy.aim_range])
		30:
			var text := JSON.stringify(enemy.to_dict())
			_report(text.contains("broken_parts") and text.contains("arm_right"),
				"壊れた部位が保存データに残る")
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


## その部位が壊れるまで、必要な回数だけ当てる
func _break_part(body: Pilotable, part: String, shape_index: int) -> void:
	var guard := 0
	while not body.is_part_broken(part) and guard < 50:
		body.take_hit_at_shape(10, shape_index)
		guard += 1


## 名前から当たり判定の番号を調べる
func _shape_index_of(body: CollisionObject3D, node_name: String) -> int:
	for owner_id in body.get_shape_owners():
		var node := body.shape_owner_get_owner(owner_id)
		if node != null and node.name == node_name:
			return body.shape_owner_get_shape_index(owner_id, 0)
	return -1


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
