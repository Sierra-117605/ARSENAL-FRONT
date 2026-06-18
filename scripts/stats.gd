class_name Stats
extends RefCounted

# Phase 1 で扱う5項目ステータス。SPEC §2.1 の 8 項目のうち、機動/索敵/射程は
# 出撃モード実装時 (Phase 2 以降) に追加する予定。

const KEYS: Array[String] = [
	"soft_attack",
	"hard_attack",
	"piercing",
	"hp",
	"armor",
]

const LABELS: Dictionary = {
	"soft_attack": "対人攻撃",
	"hard_attack": "対装甲攻撃",
	"piercing": "貫通",
	"hp": "耐久",
	"armor": "装甲",
}

static func zero() -> Dictionary:
	var out: Dictionary = {}
	for k in KEYS:
		out[k] = 0
	return out

static func add(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = a.duplicate()
	for k in KEYS:
		out[k] = int(a.get(k, 0)) + int(b.get(k, 0))
	return out
