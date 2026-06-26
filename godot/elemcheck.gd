extends SceneTree
# 33 元素守恒 headless 验证:godot --headless --path godot --script res://elemcheck.gd
# 验:每个元素总量(溶解Σ+沉积Σ+俯冲池+岩石源)逐年守恒(库间只搬运);风化建起陆地溶解载量、有沉积成矿。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")

func _totals(w) -> Array:
	var t := []
	for e in Sim.NE:
		var s: float = w.subPoolE[e] + w.rockE[e]
		for k in Sim.SZ: s += w.disE[k * Sim.NE + e] + w.depE[k * Sim.NE + e]
		t.append(s)
	return t

func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var w = Sim.new()
	w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var t0 = _totals(w)
	var day := 0
	for step in 80 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	var t1 = _totals(w)
	var maxDrift := 0.0
	for e in Sim.NE:
		var d: float = abs(t1[e] - t0[e]) / max(1.0, abs(t0[e]))
		maxDrift = max(maxDrift, d)
	# 沉积成矿 + 陆地溶解载量
	var depSum := 0.0; var landDis := 0.0
	for k in Sim.SZ:
		var land: bool = w.Land[k] != 0
		for e in Sim.NE:
			depSum += w.depE[k * Sim.NE + e]
			if land: landDis += w.disE[k * Sim.NE + e]
	print("================ 33元素守恒验证 ================")
	print("元素总量最大相对漂移: " + str(maxDrift))
	print("沉积总量Σ %.1f   陆地溶解载量Σ %.1f" % [depSum, landDis])
	print("钠海水 %.0f(本底3000)  钙 %.1f  硅 %.2f" % [_seaAvg(w, 0), _seaAvg(w, 1), _seaAvg(w, 8)])
	var conserved: bool = maxDrift < 1e-6
	var active: bool = depSum > 1.0 and landDis > 1.0
	print("逐元素守恒: %s" % ("✅ 一克不差" if conserved else "❌ 漂了"))
	print("风化/沉积活跃: %s" % ("✅" if active else "❌"))
	# G1 逐格岩性异质:岩性多样 + 成矿在格间分异。
	# 注:成矿异质用 Cu(immobile 矿:喷口/砂矿富集)测——U 是地化最易迁移元素(易溶随河进海),
	#     不该当"成矿异质"代理(旧版用 U 在加 G3 河网后失效:U 全冲进海洋黑页岩)。
	var lithSet := {}
	var cuMax := 0.0; var cuMin := 1e9
	for k in Sim.SZ:
		lithSet[w.Lith[k]] = true
		if w.Land[k] != 0:
			var cu: float = w.depE[k * Sim.NE + 9]
			cuMax = max(cuMax, cu); cuMin = min(cuMin, cu)
	var hetero: bool = lithSet.size() >= 3 and cuMax > cuMin + 0.3
	print("G1 逐格岩性异质(岩性%d种 · 陆Cu沉积 %.2f~%.2f): %s" % [lithSet.size(), cuMin, cuMax, "✅" if hetero else "❌"])
	# 真铀地化(redox 成矿):U 氧化态可溶、还原态沉淀——海里 U 现在主要是沉淀态(黑页岩)而非永远溶解
	var uDis := 0.0; var uDep := 0.0
	for k in Sim.SZ:
		uDis += w.disE[k * Sim.NE + 23]; uDep += w.depE[k * Sim.NE + 23]
	var redoxU: bool = uDep > uDis * 5.0
	print("redox 铀成矿(U 沉淀%.1f ≫ 溶解%.2f→还原沉成黑页岩,非永溶): %s" % [uDep, uDis, "✅" if redoxU else "❌"])
	quit(0 if (conserved and active and hetero and redoxU) else 1)

func _seaAvg(w, e: int) -> float:
	var s := 0.0; var n := 0
	for k in Sim.SZ:
		if w.Land[k] == 0: s += w.disE[k * Sim.NE + e]; n += 1
	return s / n if n > 0 else 0.0
