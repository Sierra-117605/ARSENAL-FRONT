extends SceneTree
## 乗り換えに合わせた勝敗・敵の狙いの確認。
##
## 確かめること：
##  1. 予備機に乗り換えた後、置いてきた元の機体が壊されてもゲームオーバーにならない
##  2. 敵は自軍の機体（生きているもの）を狙い、壊れた機体には構わない
##  3. 今乗っている機体が壊れたら「撃破（負け）」になる
##
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n4_3b_switch_rules.gd

var field: Node
var battle: Battle
var robot: Robot
var spare: Robot
var input: PlayerInput
var enemy_pilot: AIPilot
var frame := 0
var failed := false


func _initialize() -> void:
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	battle = field
	robot = field.get_node("Robot")
	robot.use_saved_loadout = false
	spare = field.get_node("SpareRobot")
	input = field.get_node("PlayerInput")
	enemy_pilot = field.get_node("Enemies/Enemy1/AIPilot")


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			var first_target := enemy_pilot._current_target()
			_report(first_target != null and (first_target as Pilotable).team == "player",
				"敵は自軍のいずれかを狙う (%s)" % first_target.name)
			spare.global_position = robot.global_position + Vector3(20, 0, 0)
		15:
			_report(input.try_board_nearby(), "予備機に乗り換えた")
			var target_after := enemy_pilot._current_target()
			_report(target_after != null and (target_after as Pilotable).team == "player",
				"乗り換え後も敵は自軍のいずれかを狙う (%s)" % target_after.name)
		20:
			# 1：置いてきた元の機体を壊す
			robot.take_hit(10000)
		25:
			_report(not robot.is_alive(), "置いてきた機体は壊れた")
			_report(battle.outcome == "", "乗り捨てた機体が壊れてもゲームオーバーにならない")
			var target_now := enemy_pilot._current_target()
			_report(target_now != null and (target_now as Pilotable).is_alive(),
				"敵は生きている自軍機を狙い続ける (%s)" % target_now.name)
		30:
			# 3：今乗っている機体を壊す
			spare.take_hit(10000)
		35:
			_report(battle.outcome == "lose", "今乗っている機体が壊れたら撃破（結果 %s）" % battle.outcome)
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
