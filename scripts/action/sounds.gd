class_name Sounds
extends Node
## 音の再生役。3D 空間の音（遠いと小さく聞こえる）と、画面全体の音を鳴らす。
## 素材は tools/make_sounds.py で合成した自作の WAV（assets/audio/）。

const SHOT := "shot"
const IMPACT := "impact"
const HIT := "hit"
const DESTROY := "destroy"
const STEP := "step"
const VICTORY := "victory"
const DEFEAT := "defeat"
const ALARM := "alarm"
const RAILGUN := "railgun"

const FILES := {
	SHOT: "res://assets/audio/shot.wav",
	IMPACT: "res://assets/audio/impact.wav",
	HIT: "res://assets/audio/hit.wav",
	DESTROY: "res://assets/audio/destroy.wav",
	STEP: "res://assets/audio/step.wav",
	VICTORY: "res://assets/audio/victory.wav",
	DEFEAT: "res://assets/audio/defeat.wav",
	ALARM: "res://assets/audio/alarm.wav",
	RAILGUN: "res://assets/audio/railgun.wav",
}

## 音ごとの大きさ（デシベル。0 が元の大きさ、マイナスで小さくなる）
const VOLUMES := {
	SHOT: -6.0,
	IMPACT: -10.0,
	HIT: -3.0,
	DESTROY: 0.0,
	STEP: -14.0,
	VICTORY: -4.0,
	DEFEAT: -4.0,
	ALARM: -2.0,
	RAILGUN: 2.0,
}

## 読み込んだ音（名前 → 音データ）
static var _cache: Dictionary = {}


## 音データを取り出す（最初の 1 回だけ読み込む）
static func stream(name: String) -> AudioStream:
	if not _cache.has(name):
		_cache[name] = load(FILES.get(name, ""))
	return _cache[name]


## 3D 空間のその場所で鳴らす（遠いと小さく聞こえる）
static func play_at(world: Node, name: String, position: Vector3, pitch: float = 1.0) -> void:
	var sound := stream(name)
	if sound == null or world == null or not world.is_inside_tree():
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = sound
	player.volume_db = VOLUMES.get(name, 0.0)
	player.pitch_scale = pitch
	player.max_distance = 400.0
	player.unit_size = 30.0
	# 鳴らす部品は場面の一番上に置く（鳴っている途中で機体が消えても音が切れないように）
	_scene_root(world).add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()


## 画面全体で鳴らす（勝敗など、場所に関係ない音）
static func play_ui(world: Node, name: String) -> void:
	var sound := stream(name)
	if sound == null or world == null or not world.is_inside_tree():
		return
	var player := AudioStreamPlayer.new()
	player.stream = sound
	player.volume_db = VOLUMES.get(name, 0.0)
	_scene_root(world).add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## 音を置く場所（場面の一番上。テスト中など場面が無ければツリーの根）
static func _scene_root(world: Node) -> Node:
	var tree := world.get_tree()
	if tree == null:
		return world
	if tree.current_scene != null:
		return tree.current_scene
	return tree.root
