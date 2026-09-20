extends Control
## 戦闘中に任務の状況を出す表示（画面上の中央）。
## 任務名・残り時間・守る拠点／破壊目標の耐久・残りの敵数。
## 文字は英語ではなく日本語（テーマのフォントを使う）。

@export var battle: Battle


func _ready() -> void:
	if battle != null:
		# 任務名はテーマのフォントで出したいのでラベルを使う
		var label := Label.new()
		label.name = "MissionLabel"
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
		label.position = Vector2(24, 18)
		add_child(label)
		var status := Label.new()
		status.name = "StatusLabel"
		status.add_theme_font_size_override("font_size", 20)
		status.position = Vector2(24, 50)
		add_child(status)


func _process(_delta: float) -> void:
	if battle == null or not is_inside_tree():
		return
	var label: Label = get_node_or_null("MissionLabel")
	var status: Label = get_node_or_null("StatusLabel")
	if label == null or status == null:
		return
	label.text = "%s（%s）" % [battle.mission.get("name", ""), battle.mission.get("difficulty_name", "")]

	var parts: Array[String] = []
	if battle.time_left > 0.0:
		parts.append("残り %d 秒" % int(ceil(battle.time_left)))
	if battle.objective != null and is_instance_valid(battle.objective):
		var kind := "拠点" if str(battle.mission.get("type", "")) == "defend" else "目標"
		parts.append("%s 耐久 %d / %d" % [kind, battle.objective.hp, battle.objective.max_hp])
	# ボス戦では段階と残りの部位数を出す
	var boss: BossFortress = battle.boss
	if boss != null and is_instance_valid(boss):
		var stage_name: String = {
			1: "迎撃砲台", 2: "発電施設", 3: "砲身・中枢",
		}.get(boss.stage, "撃破")
		var alive := 0
		for part in boss.parts_of_stage(boss.stage):
			if part.is_alive():
				alive += 1
		parts.append("段階 %d：%s 残り %d" % [boss.stage, stage_name, alive])
		if boss.warning:
			parts.append("レールガン発射まもなく！物陰へ")
	parts.append("敵 残り %d 体" % battle.alive_enemy_count())
	status.text = "　／　".join(parts)
	# 残り時間が少ない・拠点が危ない時は赤くする
	var danger := battle.time_left > 0.0 and battle.time_left < 15.0
	if battle.boss != null and is_instance_valid(battle.boss):
		danger = danger or battle.boss.warning
	if battle.objective != null and is_instance_valid(battle.objective):
		danger = danger or float(battle.objective.hp) / float(maxi(battle.objective.max_hp, 1)) < 0.3
	status.add_theme_color_override("font_color", Color(1, 0.45, 0.4) if danger else Color(0.9, 0.92, 0.9))
