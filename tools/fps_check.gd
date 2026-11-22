extends SceneTree
## フレームレート（1 秒間に何枚描けるか）を測る道具（TODO N8 の確認用）。
##
## 戦場をふつうに動かし（AI も戦闘も動かす）、画面の更新速度の平均と最低を出す。
## 画面の同期（垂直同期）を切って測るので、60 を大きく超える値が出れば余裕がある。
##
## 使い方（--headless は付けない）：
##   Godot_v4.6.3-stable_win64_console.exe --path . --script res://tools/fps_check.gd -- --frames=600

const WIDTH := 1920
const HEIGHT := 1080

var frames_to_measure := 600
var warmup := 60  # 測り始める前に捨てるフレーム数（読み込み直後は遅いため）
var frame := 0
var samples: Array[float] = []
var mission_before := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			frames_to_measure = int(arg.substr(9))
	root.content_scale_size = Vector2i(WIDTH, HEIGHT)
	root.size = Vector2i(WIDTH, HEIGHT)
	DisplayServer.window_set_size(Vector2i(WIDTH, HEIGHT))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if FileAccess.file_exists(MissionData.CHOICE_PATH):
		mission_before = FileAccess.get_file_as_string(MissionData.CHOICE_PATH)
	MissionData.save_choice("sweep_plain", "normal")
	var field: Node = load("res://scenes/field_3d.tscn").instantiate()
	root.add_child(field)
	(field.get_node("Robot") as Robot).use_saved_loadout = false


func _process(_delta: float) -> bool:
	frame += 1
	if frame <= warmup:
		return false
	samples.append(Engine.get_frames_per_second())
	if frame >= warmup + frames_to_measure:
		_report()
		_restore_mission()
		return true
	return false


func _report() -> void:
	var total := 0.0
	var lowest := 99999.0
	for v in samples:
		total += v
		lowest = minf(lowest, v)
	# 最初の数十フレームは値が安定しないので、後半だけで最低値も出す
	var late_low := 99999.0
	for i in range(samples.size() / 2, samples.size()):
		late_low = minf(late_low, samples[i])
	print("FPS AVG: %.1f  MIN: %.1f  LATE_MIN: %.1f  (%d フレーム計測)" % [
		total / maxf(samples.size(), 1.0), lowest, late_low, samples.size()])


func _restore_mission() -> void:
	if mission_before != "":
		var f := FileAccess.open(MissionData.CHOICE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(mission_before)
	elif FileAccess.file_exists(MissionData.CHOICE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MissionData.CHOICE_PATH))
