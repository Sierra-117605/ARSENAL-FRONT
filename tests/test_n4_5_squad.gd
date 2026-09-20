extends SceneTree
## 部隊としての振る舞いの確認（乗り換え後の自機と、敵の狙いの分かれ方）。
##
## 確かめること：
##  1. 自機にも AI 乗員が控えていて、プレイヤーが座っている間は AI が操作しない
##  2. 味方機に乗り換えると、置いていった自機を AI が動かして戦い始める
##  3. 敵は自機だけを狙わず、いちばん近い自軍機を狙う（味方機にも交戦する）
##  4. 乗り換えても勝敗判定は「今乗っている機体」のまま
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n4_5_squad.gd

var field: Node
var battle: Battle
var robot: Robot
var spare: Robot
var input: PlayerInput
var pilot: Occupant
var robot_ai: AIPilot
var robot_seat: Seat
var enemies: Array = []
var frame := 0
var failed := false
var robot_pos_at_switch := Vector3.ZERO


func _initialize() -> void:
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	battle = field
	robot = field.get_node("Robot")
	robot.use_saved_loadout = false
	spare = field.get_node("SpareRobot")
	input = field.get_node("PlayerInput")
	pilot = field.get_node("Pilot")
	robot_ai = field.get_node("Robot/AIPilot")
	robot_seat = field.get_node("Robot/DriverSeat")
	enemies = field.get_node("Enemies").get_children()


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			_report(robot_seat.occupant == pilot, "自機の操縦席にはプレイヤーが座っている")
			_report(robot_seat.ai_backup == robot_ai, "自機にも AI 乗員が控えている")
			_report(robot.control["move_z"] == 0.0 and not robot.control["fire"],
				"プレイヤーが乗っている間、AI は勝手に動かさない")
		20:
			# 3：敵の狙いが分かれているか（自機だけに集中していないか）
			var targets := []
			for enemy in enemies:
				var ai: AIPilot = enemy.get_node("AIPilot")
				var t := ai._current_target()
				targets.append(t.name if t != null else "なし")
			var unique := {}
			for t in targets:
				unique[t] = true
			_report(unique.size() >= 2, "敵の狙いが分かれている（全員が同じ相手に群がらない）狙い：%s" % [targets])
			# 味方機を近くへ寄せて乗り換える
			spare.global_position = robot.global_position + Vector3(20, 0, 0)
		25:
			_report(input.try_board_nearby(), "味方機に乗り換えた")
			_report(robot_seat.occupant == robot_ai, "降りた自機は AI が操縦を引き継ぐ")
			robot_pos_at_switch = robot.global_position
		90:
			var moved := robot.global_position.distance_to(robot_pos_at_switch)
			_report(moved > 2.0 or robot.control["fire"],
				"降りた自機が AI で動く・撃つ (移動 %.1fm / 射撃 %s)" % [moved, robot.control["fire"]])
			_report(battle.outcome == "", "まだ決着はついていない")
			# 4：今乗っている機体を壊すと負け
			spare.take_hit(100000)
		95:
			_report(battle.outcome == "lose", "今乗っている機体が壊れたら撃破 (%s)" % battle.outcome)
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
