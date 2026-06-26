extends SceneTree
# 海相碳酸盐真 Ksp(逆行溶解度)headless 验证:godot --headless --path godot --script res://carbonatecheck.gd
# 验:① 逆行溶解度曲线(暖→Ksp小更易沉,冷→大,单调)② 热带海沉灰岩 ≫ 极地海(碳酸盐工厂)
# ③ 海相灰岩确实形成(洋碳酸盐沉积>0)④ Ca/碳酸盐 守恒(disE→depE,一克不差)。确定性零随机。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
const ChemS = preload("res://sim/Chem.gd")

func _tot(w, e: int) -> float:
	var s: float = w.subPoolE[e] + w.rockE[e]
	for k in Sim.SZ: s += w.disE[k * Sim.NE + e] + w.depE[k * Sim.NE + e]
	return s

func _initialize() -> void:
	print("================ 海相碳酸盐真 Ksp(逆行溶解度)验证 ================")

	# ① 逆行曲线:暖(30℃)<25℃(=1)<冷(5℃),单调降
	var f30: float = ChemS.ksp_caco3_factor(30.0)
	var f25: float = ChemS.ksp_caco3_factor(25.0)
	var f5: float = ChemS.ksp_caco3_factor(5.0)
	var curve_ok: bool = f30 < f25 and is_equal_approx(f25, 1.0) and f5 > f25 and f30 < f5
	print("① 逆行: 30℃Ksp×%.2f < 25℃×%.2f < 5℃×%.2f(暖更易沉)→ %s" % [f30, f25, f5, _t(curve_ok)])

	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var ca0: float = _tot(w, 1); var cb0: float = _tot(w, 7)
	var day := 0
	for s in 60 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1

	# ② 热带海 vs 极地海碳酸盐沉积(灰岩=depE 碳酸盐7)
	var warmK := -1; var coldK := -1; var warmT := -999.0; var coldT := 999.0
	for j in Sim.NLat:
		for i in Sim.NLon:
			var k: int = j * Sim.NLon + i
			if w.Land[k] != 0: continue
			var te: float = w.Teff(j, i)
			if te > warmT: warmT = te; warmK = k
			if te < coldT: coldT = te; coldK = k
	var warmCarb: float = w.depE[warmK * Sim.NE + 7]
	var coldCarb: float = w.depE[coldK * Sim.NE + 7]
	var spatial_ok: bool = warmCarb > coldCarb + 0.3
	print("② 工厂: 热带海%.1f℃沉灰岩%.2f ≫ 极地海%.1f℃沉灰岩%.2f → %s" % [warmT, warmCarb, coldT, coldCarb, _t(spatial_ok)])

	# ③ 海相灰岩总量>0(碳酸盐沉淀确实发生)
	var oceanCarb := 0.0
	for k in Sim.SZ:
		if w.Land[k] == 0: oceanCarb += w.depE[k * Sim.NE + 7]
	var formed_ok: bool = oceanCarb > 1.0
	print("③ 海相灰岩总量 %.1f(>0 确实形成)→ %s" % [oceanCarb, _t(formed_ok)])

	# ④ Ca + 碳酸盐 守恒(沉淀只是 disE→depE)
	var ca1: float = _tot(w, 1); var cb1: float = _tot(w, 7)
	var consCa: float = absf(ca1 - ca0) / maxf(1.0, ca0); var consCb: float = absf(cb1 - cb0) / maxf(1.0, cb0)
	var cons_ok: bool = consCa < 1e-6 and consCb < 1e-6
	print("④ 守恒: Ca 漂移 %s · 碳酸盐 漂移 %s → %s" % [str(consCa), str(consCb), _t(cons_ok)])

	var all_ok: bool = curve_ok and spatial_ok and formed_ok and cons_ok
	print("------------------------------------------------")
	print("① 逆行曲线%s ② 热带碳酸盐工厂%s ③ 灰岩形成%s ④ 守恒%s" % [_t(curve_ok), _t(spatial_ok), _t(formed_ok), _t(cons_ok)])
	print("海相碳酸盐真 Ksp: %s" % ("✅ 全过" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _t(b: bool) -> String: return "✅" if b else "❌"
