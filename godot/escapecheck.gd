extends SceneTree
# 大气逃逸 headless 验证:godot --headless --path godot --script res://escapecheck.gd
# 验:① 地球(强磁场)逃逸=0、大气稳 ② 贫金属(无发电机→磁场塌)→太阳风剥大气→CO₂/N₂ 流失→死星
# ③ 总碳(含逃逸到太空池)守恒。接 R4 金属丰度 + R5 磁层。确定性零随机。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")

func _run(metal: float, years: int) -> Dictionary:
	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g
	w.metallicity = metal
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var c0: float = w.globalCO2 + w.ocnC + w.fosC + w.rockC + w.organicC + w.bioC + w.escapedC
	var day := 0
	for s in years * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	var c1: float = w.globalCO2 + w.ocnC + w.fosC + w.rockC + w.organicC + w.bioC + w.escapedC
	return {"co2": w.globalCO2, "escC": w.escapedC, "escN": w.escapedN, "atmN2": w.atmN2,
		"shield": w.mag_shield(), "drift": absf(c1 - c0) / maxf(1.0, c0)}

func _initialize() -> void:
	print("================ 大气逃逸(太阳风剥离)验证 ================")
	var earth := _run(1.0, 60)
	var dead := _run(0.05, 60)
	print("地球(metal1.0 屏蔽%.2f): CO₂%.2f · 逃逸碳%.4f · 总碳漂移%s" % [earth["shield"], earth["co2"], earth["escC"], str(earth["drift"])])
	print("贫金属(metal0.05 屏蔽%.2f): CO₂%.2f · 逃逸碳%.2f · 逃逸氮%.1f · 总碳漂移%s" % [dead["shield"], dead["co2"], dead["escC"], dead["escN"], str(dead["drift"])])

	# ① 地球强场→零逃逸、大气稳
	var earth_ok: bool = earth["shield"] >= 1.0 and earth["escC"] < 1e-9 and earth["co2"] > 0.5
	# ② 死星:场塌→太阳风剥大气。CO₂ 被火山(rockC 库)持续补给缓冲,但无大储库的 N₂ 崩塌(像火星)+ 碳氮持续 bleed 到太空
	var dead_ok: bool = dead["shield"] < 0.2 and dead["escC"] > 1.0 and dead["escN"] > 1.0 and dead["atmN2"] < earth["atmN2"] * 0.3
	# ③ 总碳(含逃逸池)守恒(两种世界都<1e-6)
	var cons_ok: bool = earth["drift"] < 1e-6 and dead["drift"] < 1e-6

	var all_ok: bool = earth_ok and dead_ok and cons_ok
	print("------------------------------------------------")
	print("① 地球零逃逸大气稳%s ② 贫金属死星(大气被剥)%s ③ 含逃逸池守恒%s" % [_t(earth_ok), _t(dead_ok), _t(cons_ok)])
	print("大气逃逸: %s" % ("✅ 全过" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _t(b: bool) -> String: return "✅" if b else "❌"
