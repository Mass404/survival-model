extends SceneTree
# #3 真热力学风化(Arrhenius)headless 验证:godot --headless --path godot --script res://weathercheck.gd
# 验:① Arrhenius 曲线真实(15℃处=1·+10℃≈2~2.6×真实Q10·冷指数变慢·单调)
# ② 模拟空间真实性:暖热带格风化因子 ≫ 冷极地格(温度驱动,真) ③ 碳恒温器仍自稳+总碳守恒。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
const ChemS = preload("res://sim/Chem.gd")

func _initialize() -> void:
	print("================ #3 真热力学风化(Arrhenius)验证 ================")

	# ① Arrhenius 曲线:归一15℃=1、Q10(25/15)∈[2.0,2.6]、冷(5℃)<1、单调升
	var a5: float = ChemS.arrhenius(5.0, ChemS.EA_SILICATE, 15.0)
	var a15: float = ChemS.arrhenius(15.0, ChemS.EA_SILICATE, 15.0)
	var a25: float = ChemS.arrhenius(25.0, ChemS.EA_SILICATE, 15.0)
	var q10: float = a25 / a15
	var curve_ok: bool = is_equal_approx(a15, 1.0) and q10 >= 2.0 and q10 <= 2.6 and a5 < a15 and a5 < a25
	print("① 曲线: 5℃=%.2f < 15℃=%.2f < 25℃=%.2f · Q10=%.2f(真实2~3)→ %s" % [a5, a15, a25, q10, _t(curve_ok)])

	# 建星球,推进出气候/化学
	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	for s in 30 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1

	# ② 空间真实性:最暖陆格风化因子 ≫ 最冷陆格(温度指数驱动)
	var warmK := -1; var coldK := -1; var warmT := -999.0; var coldT := 999.0
	for j in Sim.NLat:
		for i in Sim.NLon:
			var k: int = j * Sim.NLon + i
			if w.Land[k] == 0: continue
			var te: float = w.Teff(j, i)
			if te > warmT: warmT = te; warmK = k
			if te < coldT: coldT = te; coldK = k
	var fWarm: float = ChemS.arrhenius(warmT, ChemS.EA_SILICATE, 15.0)
	var fCold: float = ChemS.arrhenius(coldT, ChemS.EA_SILICATE, 15.0)
	var spatial_ok: bool = fWarm > fCold * 1.5 and warmT > coldT
	print("② 空间: 最暖陆 %.1f℃→风化×%.2f  ≫  最冷陆 %.1f℃→风化×%.3f(比 %.1f×)→ %s" % [
		warmT, fWarm, coldT, fCold, fWarm / max(1e-6, fCold), _t(spatial_ok)])

	# ③ 恒温器自稳 + 总碳守恒(再推 60 年,CO₂ 落在宜居带 0.3~10,总碳相对守恒)
	var c0: float = w.globalCO2 + w.ocnC + w.fosC + w.rockC + w.organicC + w.bioC
	for s in 60 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	var c1: float = w.globalCO2 + w.ocnC + w.fosC + w.rockC + w.organicC + w.bioC
	var cons: float = absf(c1 - c0) / maxf(1.0, absf(c0))
	var stable_ok: bool = w.globalCO2 > 0.3 and w.globalCO2 < 10.0 and cons < 1e-6 and _fin(w.globalCO2)
	print("③ 恒温器: CO₂ 自稳 %.2f(宜居带0.3~10) · 总碳相对漂移 %s → %s" % [w.globalCO2, str(cons), _t(stable_ok)])

	var all_ok: bool = curve_ok and spatial_ok and stable_ok
	print("------------------------------------------------")
	print("① Arrhenius曲线%s ② 空间温度驱动%s ③ 恒温器自稳+守恒%s" % [_t(curve_ok), _t(spatial_ok), _t(stable_ok)])
	print("真热力学风化: %s" % ("✅ 全过" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _fin(x: float) -> bool: return not (is_nan(x) or is_inf(x))
func _t(b: bool) -> String: return "✅" if b else "❌"
