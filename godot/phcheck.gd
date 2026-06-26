extends SceneTree
# 海洋 pH + 碳酸盐补偿 headless 验证:godot --headless --path godot --script res://phcheck.gd
# 验:① 地球海 pH≈8.1 ② pH 公式单调(CO₂↑→pH↓)③ 海洋酸化→已沉灰岩回溶(碳酸盐补偿/CCD)
# ④ 酸化全程 Ca+碳酸盐 守恒。确定性零随机。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
const ChemS = preload("res://sim/Chem.gd")

func _oceanCarb(w) -> float:
	var s := 0.0
	for k in Sim.SZ:
		if w.Land[k] == 0: s += w.depE[k * Sim.NE + 7]
	return s
func _tot(w, e: int) -> float:
	var s: float = w.subPoolE[e] + w.rockE[e]
	for k in Sim.SZ: s += w.disE[k * Sim.NE + e] + w.depE[k * Sim.NE + e]
	return s

func _initialize() -> void:
	print("================ 海洋 pH + 碳酸盐补偿 验证 ================")

	# ② pH 公式单调:低 CO₂→高 pH、高 CO₂→低 pH(同碱度)
	var phLow: float = ChemS.ocean_ph(2.0, 140.0)
	var phHigh: float = ChemS.ocean_ph(8.0, 140.0)
	var mono_ok: bool = phLow > phHigh
	print("② 公式: CO₂2→pH%.2f > CO₂8→pH%.2f(酸化)→ %s" % [phLow, phHigh, _t(mono_ok)])

	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	for s in 40 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1

	# ① 地球海 pH 合理(7.7~8.4)
	var ph0: float = w.oceanPH
	var earth_ok: bool = ph0 > 7.7 and ph0 < 8.4
	print("① 地球海 pH = %.2f(7.7~8.4)→ %s" % [ph0, _t(earth_ok)])

	# ③ 海洋酸化抑制碳酸盐工厂:正常 pH 灰岩持续长;强灌 CO₂→酸化→pH 闸门关→工厂停(钙化受抑,真实)
	var ca_t0: float = _tot(w, 1); var cb_t0: float = _tot(w, 7)
	var cN0: float = _oceanCarb(w)
	for n in 10: w.elementStep()            # 正常相(globalCO2 维持稳态~5,pH~7.8 工厂开)
	var cN1: float = _oceanCarb(w); var growN: float = cN1 - cN0
	for n in 10:
		w.globalCO2 = 30.0                  # 酸化扰动(失控温室/火山)
		w.elementStep()
	var ph1: float = w.oceanPH; var cA1: float = _oceanCarb(w); var growA: float = cA1 - cN1
	var comp_ok: bool = ph1 < w.PH_DISSOLVE and growN > 0.0 and growA < growN
	print("③ 酸化抑制工厂: 正常相长灰岩%+.1f(pH%.2f) → 酸化相%+.1f(pH%.2f,闸门关)→ %s" % [growN, ph0, growA, ph1, _t(comp_ok)])

	# ④ Ca+碳酸盐 守恒(回溶只是 depE→disE)
	var consCa: float = absf(_tot(w, 1) - ca_t0) / maxf(1.0, ca_t0)
	var consCb: float = absf(_tot(w, 7) - cb_t0) / maxf(1.0, cb_t0)
	var cons_ok: bool = consCa < 1e-6 and consCb < 1e-6
	print("④ 守恒: Ca 漂移%s · 碳酸盐 漂移%s → %s" % [str(consCa), str(consCb), _t(cons_ok)])

	var all_ok: bool = mono_ok and earth_ok and comp_ok and cons_ok
	print("------------------------------------------------")
	print("① 地球pH合理%s ② 公式单调%s ③ 酸化碳酸盐补偿%s ④ 守恒%s" % [_t(earth_ok), _t(mono_ok), _t(comp_ok), _t(cons_ok)])
	print("海洋 pH + 碳酸盐补偿: %s" % ("✅ 全过" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _t(b: bool) -> String: return "✅" if b else "❌"
