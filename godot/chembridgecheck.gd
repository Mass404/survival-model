extends SceneTree
# #2 物种↔33元素桥 headless 验证:godot --headless --path godot --script res://chembridgecheck.gd
# 验:① 33 槽映射完整(每元素在 AW 内,槽数==World.NE) ② 含氧阴离子组式量对真实值
# ③ 全行星化学(disE+depE+rockE+subPoolE)按原子记账,在深时间演化中各基础元素原子守恒。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
const ChemS = preload("res://sim/Chem.gd")

# 全行星 33 槽总量(所有格 disE+depE + 全局 rockE+subPoolE)→ 长度 33 的数组
func _planet_slots(w) -> Array:
	var v := []; v.resize(Sim.NE); v.fill(0.0)
	for k in Sim.SZ:
		var base: int = k * Sim.NE
		for e in Sim.NE: v[e] = float(v[e]) + float(w.disE[base + e]) + float(w.depE[base + e])
	for e in Sim.NE: v[e] = float(v[e]) + float(w.rockE[e]) + float(w.subPoolE[e])
	return v

func _initialize() -> void:
	print("================ #2 物种↔33元素桥 验证 ================")

	# ① 映射完整:槽数==NE,每个组成元素都在原子量表内
	var size_ok: bool = ChemS.E2COMP.size() == Sim.NE
	var elem_ok := true
	for i in ChemS.E2COMP.size():
		for el in ChemS.E2COMP[i]:
			if not ChemS.AW.has(el): elem_ok = false; print("  ✗ 槽%d 元素 %s 不在 AW" % [i, el])
	print("① 映射: 槽数 %d(==NE %d:%s) · 元素齐备%s" % [ChemS.E2COMP.size(), Sim.NE, _t(size_ok), _t(elem_ok)])

	# ② 含氧阴离子组式量对真实值:碳酸盐CO₃60.01 · 硫酸盐SO₄96.06 · 硝NO₃62.00 · 硅SiO₂60.08 · 钙40.08
	var mm_ok: bool = (
		absf(ChemS.slot_molar_mass(7) - 60.01) < 0.1 and
		absf(ChemS.slot_molar_mass(6) - 96.06) < 0.1 and
		absf(ChemS.slot_molar_mass(18) - 62.00) < 0.1 and
		absf(ChemS.slot_molar_mass(8) - 60.08) < 0.1 and
		absf(ChemS.slot_molar_mass(1) - 40.078) < 0.05)
	print("② 式量: CO₃%.2f · SO₄%.2f · NO₃%.2f · SiO₂%.2f · Ca%.2f → %s" % [
		ChemS.slot_molar_mass(7), ChemS.slot_molar_mass(6), ChemS.slot_molar_mass(18), ChemS.slot_molar_mass(8), ChemS.slot_molar_mass(1), _t(mm_ok)])

	# ③ 全行星原子记账守恒:演化前后,各基础元素总原子数相对漂移<1e-9
	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var a0: Dictionary = ChemS.slots_to_atoms(_planet_slots(w))
	var day := 0
	for s in 15 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	var a1: Dictionary = ChemS.slots_to_atoms(_planet_slots(w))
	var cons_ok := true; var worst := 0.0; var worstEl := ""
	for el in a0:
		var v0: float = float(a0[el]); var v1: float = float(a1.get(el, 0.0))
		var rel: float = absf(v1 - v0) / max(1.0, absf(v0))
		if rel > worst: worst = rel; worstEl = el
		if rel > 1e-9: cons_ok = false
	print("③ 全行星原子守恒(15年演化): 最大相对漂移 %s(元素 %s) → %s" % [str(worst), worstEl, _t(cons_ok)])
	print("   例: 钙原子 %.1f→%.1f · 硅 %.1f→%.1f · 铁 %.1f→%.1f" % [
		float(a0.get("Ca", 0.0)), float(a1.get("Ca", 0.0)), float(a0.get("Si", 0.0)), float(a1.get("Si", 0.0)), float(a0.get("Fe", 0.0)), float(a1.get("Fe", 0.0))])

	var all_ok: bool = size_ok and elem_ok and mm_ok and cons_ok
	print("------------------------------------------------")
	print("① 映射完整%s ② 式量真实%s ③ 全行星原子守恒%s" % [_t(size_ok and elem_ok), _t(mm_ok), _t(cons_ok)])
	print("物种↔33元素桥: %s" % ("✅ 全过" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _t(b: bool) -> String: return "✅" if b else "❌"
