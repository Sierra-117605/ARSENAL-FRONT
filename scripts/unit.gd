class_name Unit
extends RefCounted

# ユニット (戦車設計) は素朴な Dictionary。
# docs/DATA_STRUCTURE.md の方針通り、JSON 化できる型 (int/String/Array/Dictionary) だけで構成する。
#
# {
#   "id": "design_001",
#   "name": "Type-1 MBT",
#   "category": "mbt",
#   "slots": { "hull": "hull_medium", "main_armament": "gun_120mm_smooth", ... },
#   "modules": ["mod_radio", "mod_smoke_launcher"]
# }

const FIXED_SLOTS: Array[String] = [
	"hull",
	"main_armament",
	"turret",
	"engine",
	"armor",
	"suspension",
]

static func compute_stats(unit: Dictionary, catalog: PartsCatalog) -> Dictionary:
	var totals: Dictionary = Stats.zero()
	var slots: Dictionary = unit.get("slots", {})
	for slot in FIXED_SLOTS:
		var part_id: String = String(slots.get(slot, ""))
		if part_id == "":
			continue
		var part: Dictionary = catalog.get_part(part_id)
		var part_stats: Dictionary = part.get("stats", {})
		totals = Stats.add(totals, part_stats)
	var modules: Array = unit.get("modules", [])
	for mod_id in modules:
		var m: Dictionary = catalog.get_part(String(mod_id))
		var m_stats: Dictionary = m.get("stats", {})
		totals = Stats.add(totals, m_stats)
	return totals

static func total_weight(unit: Dictionary, catalog: PartsCatalog) -> int:
	var w: int = 0
	var slots: Dictionary = unit.get("slots", {})
	for slot in FIXED_SLOTS:
		var part_id: String = String(slots.get(slot, ""))
		if part_id == "":
			continue
		w += int(catalog.get_part(part_id).get("weight", 0))
	for mod_id in unit.get("modules", []):
		w += int(catalog.get_part(String(mod_id)).get("weight", 0))
	return w

static func describe(unit: Dictionary, catalog: PartsCatalog) -> String:
	var lines: Array[String] = []
	lines.append("[%s] %s  (区分: %s)" % [unit.get("id", ""), unit.get("name", ""), unit.get("category", "")])
	var slots: Dictionary = unit.get("slots", {})
	for slot in FIXED_SLOTS:
		var pid: String = String(slots.get(slot, ""))
		var pname: String
		if pid == "":
			pname = "(未装着)"
		else:
			pname = String(catalog.get_part(pid).get("name", pid))
		lines.append("    %-14s : %s" % [slot, pname])
	var modules: Array = unit.get("modules", [])
	if modules.size() > 0:
		var names: Array[String] = []
		for mid in modules:
			names.append(String(catalog.get_part(String(mid)).get("name", String(mid))))
		lines.append("    %-14s : %s" % ["modules", ", ".join(names)])
	return "\n".join(lines)
