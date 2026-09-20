extends SceneTree
# 指定した構成で戦闘画面を開き、画像を保存する（見た目確認用）
var n := 0
var path := ""
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lo := {}
	for a in args:
		if a.begins_with("--shot="):
			path = a.substr(7)
		elif a.contains("="):
			var kv := a.split("=")
			lo[kv[0]] = kv[1]
	LoadoutStore.save(lo)
	root.add_child(load("res://scenes/field_3d.tscn").instantiate())
func _physics_process(_d: float) -> bool:
	n += 1
	if n == 20:
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		return true
	return false
