extends SceneTree
## N4-1 の自動確認：射撃・被弾・撃破・足音・勝敗で音が鳴るか調べる。
## 「鳴っているか」は、音を鳴らす部品（AudioStreamPlayer）が増えたかで判定する。
## 実行：Godot_console.exe --headless --path . --script res://tests/test_n4_1_sounds.gd

var field: Node
var robot: Robot
var enemy: Robot
var frame := 0
var failed := false
var before := 0


func _initialize() -> void:
	field = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	robot = field.get_node("Robot")
	# テストでは保存した構成を読まない（シーンの標準設定のまま使う）
	robot.use_saved_loadout = false
	enemy = field.get_node("Enemies/Enemy1")


## 今ある「音を鳴らす部品」の数（種類を指定すると、その音だけ数える）
func _players(kind: String = "") -> int:
	return _count(root, kind)


func _count(node: Node, kind: String) -> int:
	var count := 0
	var wanted: AudioStream = Sounds.stream(kind) if kind != "" else null
	for child in node.get_children():
		if child is AudioStreamPlayer3D or child is AudioStreamPlayer:
			if wanted == null or child.stream == wanted:
				count += 1
		count += _count(child, kind)
	return count


func _physics_process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			_report(Sounds.stream(Sounds.SHOT) != null, "音のファイルが読み込める")
			before = _players(Sounds.SHOT)
			robot.weapon.try_fire(robot.global_position + Vector3(0, 6, -100), robot)
		12:
			_report(_players(Sounds.SHOT) > before, "撃つと発砲音が鳴る")
			before = _players(Sounds.HIT)
			robot.take_hit(10)
		14:
			_report(_players(Sounds.HIT) > before, "被弾すると音が鳴る")
			before = _players(Sounds.DESTROY)
			enemy.take_hit(1000)
		16:
			_report(_players(Sounds.DESTROY) > before, "撃破されると音が鳴る")
			before = _players(Sounds.STEP)
			# 歩かせて足音を確かめる
			Input.action_press("move_forward")
		70:
			Input.action_release("move_forward")
			_report(_players(Sounds.STEP) > before, "歩くと足音が鳴る")
			print("RESULT: ", "FAIL" if failed else "PASS")
			return true
	return false


func _report(ok: bool, msg: String) -> void:
	print("[", "OK" if ok else "NG", "] ", msg)
	if not ok:
		failed = true
