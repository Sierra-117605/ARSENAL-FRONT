class_name Combat
extends RefCounted

# Phase 1 自動戦闘 (ターン制シミュレーション)。
# SPEC §2.3 B/C を最小実装: 機動/索敵/射程は Phase 2 で追加 (現状はリストの順)。
# SPEC §2.2 のダメージ計算: 装甲量で対人/対装甲を切替、貫通 vs 装甲でフル/減衰。
#
# データはすべて Dictionary + JSON 互換型 (docs/DATA_STRUCTURE.md 方針)。

# --- バランス係数 (仮値、後で調整) ------------------------------------
const ARMOR_THRESHOLD: int = 25          # 装甲がこの値以上なら対装甲攻撃を選択
const SOFT_DAMAGE_RATIO: float = 0.5     # 対人攻撃の実ダメージ係数
const HARD_DAMAGE_RATIO: float = 0.4     # 対装甲攻撃の実ダメージ係数
const PIERCING_FAIL_PENALTY: float = 0.25 # 貫通失敗時のさらなる減衰
const MAX_ROUNDS: int = 30               # 決着がつかない場合の打ち切り

# --- 戦闘インスタンス生成 ---------------------------------------------
# 設計 (DEMO_UNITS の要素) と陣営から、戦闘で使える状態付きユニットを作る。
static func make_instance(design: Dictionary, side: String, instance_id: String, catalog: PartsCatalog) -> Dictionary:
	var stats: Dictionary = Unit.compute_stats(design, catalog)
	return {
		"id": instance_id,
		"design_id": String(design.get("id", "")),
		"name": String(design.get("name", "")),
		"category": String(design.get("category", "")),
		"side": side,
		"hp": int(stats.get("hp", 0)),
		"hp_max": int(stats.get("hp", 0)),
		"stats": stats,
		"alive": true,
	}

# --- 戦闘実行 --------------------------------------------------------
static func run(red_units: Array, blue_units: Array) -> Dictionary:
	var roster: Array = []
	for u in red_units:
		roster.append(u.duplicate(true))
	for u in blue_units:
		roster.append(u.duplicate(true))
	var log: Array = []
	var round_num: int = 0
	var winner: String = "draw_timeout"

	while round_num < MAX_ROUNDS:
		round_num += 1
		log.append({"type": "round_start", "round": round_num})
		for unit in roster:
			if not bool(unit.get("alive", false)):
				continue
			var target: Dictionary = _pick_target(roster, String(unit.get("side", "")))
			if target.is_empty():
				break
			_attack(unit, target, log, round_num)
		var red_alive: int = _count_alive(roster, "red")
		var blue_alive: int = _count_alive(roster, "blue")
		if red_alive == 0 and blue_alive == 0:
			winner = "draw"
			break
		if red_alive == 0:
			winner = "blue"
			break
		if blue_alive == 0:
			winner = "red"
			break

	log.append({"type": "battle_end", "round": round_num, "winner": winner})
	return {"log": log, "winner": winner, "round": round_num, "final_units": roster}

# --- 目標選択 (今は単純に「先に見つかった生存敵」) -----------------------
static func _pick_target(roster: Array, side: String) -> Dictionary:
	for u in roster:
		if bool(u.get("alive", false)) and String(u.get("side", "")) != side:
			return u
	return {}

static func _count_alive(roster: Array, side: String) -> int:
	var count: int = 0
	for u in roster:
		if bool(u.get("alive", false)) and String(u.get("side", "")) == side:
			count += 1
	return count

# --- 攻撃解決 (SPEC §2.2) --------------------------------------------
static func _attack(attacker: Dictionary, target: Dictionary, log: Array, round_num: int) -> void:
	var atk: Dictionary = attacker.get("stats", {})
	var tgt: Dictionary = target.get("stats", {})
	var target_armor: int = int(tgt.get("armor", 0))

	var use_hard: bool = target_armor >= ARMOR_THRESHOLD
	var attack_value: int
	var damage_type: String
	var ratio: float
	if use_hard:
		damage_type = "hard"
		attack_value = int(atk.get("hard_attack", 0))
		ratio = HARD_DAMAGE_RATIO
	else:
		damage_type = "soft"
		attack_value = int(atk.get("soft_attack", 0))
		ratio = SOFT_DAMAGE_RATIO

	var pierced: bool = int(atk.get("piercing", 0)) >= target_armor
	var damage_f: float = float(attack_value) * ratio
	if not pierced:
		damage_f = damage_f * PIERCING_FAIL_PENALTY
	var damage: int = int(roundi(damage_f))
	var before_hp: int = int(target.get("hp", 0))
	var after_hp: int = max(0, before_hp - damage)
	target["hp"] = after_hp
	var destroyed: bool = after_hp <= 0
	if destroyed:
		target["alive"] = false

	log.append({
		"type": "attack",
		"round": round_num,
		"attacker_id": String(attacker.get("id", "")),
		"attacker_name": String(attacker.get("name", "")),
		"attacker_side": String(attacker.get("side", "")),
		"target_id": String(target.get("id", "")),
		"target_name": String(target.get("name", "")),
		"target_side": String(target.get("side", "")),
		"target_hp_max": int(target.get("hp_max", 0)),
		"damage_type": damage_type,
		"attack_value": attack_value,
		"pierced": pierced,
		"damage": damage,
		"before_hp": before_hp,
		"after_hp": after_hp,
		"destroyed": destroyed,
	})

# --- ログを人間可読な文字列にする -------------------------------------
static func format_log(log: Array) -> String:
	var lines: Array[String] = []
	for ev in log:
		var t: String = String(ev.get("type", ""))
		if t == "round_start":
			lines.append("--- Round %d ---" % int(ev.get("round", 0)))
		elif t == "attack":
			var side_a: String = side_label(String(ev.get("attacker_side", "")))
			var side_t: String = side_label(String(ev.get("target_side", "")))
			var dmg_type: String = "対装甲" if String(ev.get("damage_type", "")) == "hard" else "対人  "
			var pierce: String = "貫通◎" if bool(ev.get("pierced", false)) else "貫通×"
			var line: String = "  %s(%s) → %s(%s)  %s%d  %s  →  %dダメ  残HP %d/%d" % [
				String(ev.get("attacker_name", "")), side_a,
				String(ev.get("target_name", "")), side_t,
				dmg_type, int(ev.get("attack_value", 0)),
				pierce,
				int(ev.get("damage", 0)),
				int(ev.get("after_hp", 0)),
				int(ev.get("target_hp_max", 0)),
			]
			if bool(ev.get("destroyed", false)):
				line += "  ★撃破"
			lines.append(line)
		elif t == "battle_end":
			lines.append("=== 決着: %s (%d ラウンド) ===" % [winner_label(String(ev.get("winner", ""))), int(ev.get("round", 0))])
	return "\n".join(lines)

static func side_label(side: String) -> String:
	if side == "red":
		return "赤"
	if side == "blue":
		return "青"
	return side

static func winner_label(w: String) -> String:
	if w == "red":
		return "赤チーム勝利"
	if w == "blue":
		return "青チーム勝利"
	if w == "draw":
		return "相打ち"
	return "決着なし(タイムアウト)"
