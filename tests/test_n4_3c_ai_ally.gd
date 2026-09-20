extends SceneTree
## 自分が乗っていない味方機を AI が動かす仕組みの確認（ACVD の UNAC 方式）。
##
## 確かめること：
##  1. 味方機（予備機）には AI 乗員が座っていて、自分で敵を探して戦う
##  2. 味方 AI は敵陣営を狙い、敵 AI は自軍を狙う（同士討ちしない）
##  3. プレイヤーが味方機に乗り込むと、AI は席を譲る（操作はプレイヤーのものになる）
##  4. プレイヤーが別の機体へ移ると、置いていった機体の AI が操縦を再開する
##  5. 敵は自軍の機体を狙う（狙いは機体ごとに分かれる）
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n4_3c_ai_ally.gd

var field: Node
var robot: Robot
var spare: Robot
var input: PlayerInput
var pilot: Occupant
var ally_ai: AIPilot
var enemy_ai: AIPilot
var spare_seat: Seat
var frame := 0
var failed := false


func _initialize() -> void:
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	robot = field.get_node("Robot")
	robot.use_saved_loadout = false
	spare = field.get_node("SpareRobot")
	input = field.get_node("PlayerInput")
	pilot = field.get_node("Pilot")
	ally_ai = field.get_node("SpareRobot/AIPilot")
	enemy_ai = field.get_node("Enemies/Enemy1/AIPilot")
	spare_seat = field.get_node("SpareRobot/DriverSeat")


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			_report(spare.team == "player" and field.get_node("Enemies/Enemy1").team == "enemy",
				"味方機と敵機に陣営が設定されている")
			_report(spare_seat.occupant == ally_ai, "味方機には AI 乗員が座っている")
			var ally_target := ally_ai._current_target()
			_report(ally_target != null and (ally_target as Pilotable).team == "enemy",
				"味方 AI は敵を狙う (%s)" % [ally_target.name if ally_target != null else "なし"])
			var enemy_target := enemy_ai._current_target()
			_report(enemy_target != null and (enemy_target as Pilotable).team == "player",
				"敵は自軍機を狙う (%s)" % enemy_target.name)
		40:
			# 味方 AI が自分で動いているか（少し前に出ているはず）
			_report(spare.control["move_z"] != 0.0 or spare.control["fire"],
				"味方 AI が自分で動く・撃つ (前後 %.1f / 射撃 %s)" % [spare.control["move_z"], spare.control["fire"]])
			spare.global_position = robot.global_position + Vector3(20, 0, 0)
		45:
			# 3：AI が乗っている味方機に乗り込む
			_report(input.try_board_nearby(), "AI が乗っている味方機にも乗り込める")
			_report(spare_seat.occupant == pilot, "操縦席がプレイヤーのものになる")
			_report(spare_seat.ai_backup == ally_ai, "AI 乗員は席を譲って控えている")
			var enemy_target2 := enemy_ai._current_target()
			_report(enemy_target2 != null and (enemy_target2 as Pilotable).team == "player",
				"乗り換え後も敵は自軍機を狙う (%s)" % enemy_target2.name)
		50:
			# 4：元の機体へ戻る
			_report(input.try_board_nearby(), "元の機体に戻れる")
			_report(spare_seat.occupant == ally_ai, "置いていった機体は AI が操縦を再開する")
			_report(spare_seat.ai_backup == null, "控えの記録が消えている")
		80:
			_report(spare.control["move_z"] != 0.0 or spare.control["fire"],
				"AI に戻した味方機がまた自分で戦っている")
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
