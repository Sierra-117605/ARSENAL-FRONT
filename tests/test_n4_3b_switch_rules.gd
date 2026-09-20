extends SceneTree
## 乗り換えに合わせた勝敗・敵の狙いの確認。
##
## 確かめること：
##  1. 予備機に乗り換えた後、置いてきた元の機体が壊されてもゲームオーバーにならない
##  2. 敵は「今プレイヤーが乗っている機体」を狙う（乗り換えに追従する）
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
			_report(enemy_pilot._current_target() == robot, "最初は敵がプレイヤー機を狙う")
			spare.global_position = robot.global_position + Vector3(20, 0, 0)
		15:
			_report(input.try_board_nearby(), "予備機に乗り換えた")
			_report(enemy_pilot._current_target() == spare, "敵の狙いが乗り換え先に変わる")
		20:
			# 1：置いてきた元の機体を壊す
			robot.take_hit(10000)
		25:
			_report(not robot.is_alive(), "置いてきた機体は壊れた")
			_report(battle.outcome == "", "乗り捨てた機体が壊れてもゲームオーバーにならない")
			_report(enemy_pilot._current_target() == spare, "敵は今の機体を狙い続ける")
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
