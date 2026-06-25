extends SceneTree
# 全球深化(G系列)headless 验证:godot --headless --path godot --script res://gcheck.gd
# G2 逐格土壤水/地下水:土壤湿度随气候空间分异 + 地下水积累 + 径流(供河网)。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")

func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	for step in 40 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	var sMin := 9.0; var sMax := -9.0
	var gwMax := 0.0; var roCells := 0; var landN := 0
	for k in Sim.SZ:
		if w.Land[k] == 0: continue
		landN += 1
		sMin = min(sMin, w.Soil[k]); sMax = max(sMax, w.Soil[k])
		gwMax = max(gwMax, w.GW[k])
		if w.Runoff[k] > 0.0: roCells += 1
	print("================ G2 全球土壤水文验证 ================")
	print("陆格 %d · 土壤湿度 %.2f~%.2f(跨度 %.2f) · 地下水峰 %.1f · 有径流格 %d" % [landN, sMin, sMax, sMax - sMin, gwMax, roCells])
	var spatial: bool = (sMax - sMin) > 0.3
	var gw_ok: bool = gwMax > 0.5    # 地下水作为旱季储备持续存在(像缓冲,不一定增长)
	var ro_ok: bool = roCells > landN / 3
	print("土壤湿度气候分异: %s" % ("✅" if spatial else "❌"))
	print("地下水积累: %s" % ("✅" if gw_ok else "❌"))
	print("径流(供河网): %s" % ("✅" if ro_ok else "❌"))

	# G3 河网下游富集:低高程(河口/下游)溶解载量 > 高高程(源头),河网把溶质往下游搬
	var pairs := []
	for k in Sim.SZ:
		if w.Land[k] == 0: continue
		var load := 0.0
		for e in Sim.NE: load += w.disE[k * Sim.NE + e]
		pairs.append([w.Elev[k], load])
	pairs.sort_custom(func(a, b): return a[0] < b[0])
	var n := pairs.size()
	var third: int = max(1, n / 3)
	var lowLoad := 0.0; var highLoad := 0.0
	for x in third: lowLoad += pairs[x][1]
	for x in range(n - third, n): highLoad += pairs[x][1]
	lowLoad /= third; highLoad /= third
	var river_ok: bool = lowLoad > highLoad * 1.2
	print("G3 河网(下游低地溶解载量 %.1f > 源头高地 %.1f): %s" % [lowLoad, highLoad, "✅" if river_ok else "❌"])

	# G4 逐格雪/冰川:极区/高山积雪成冰(赤道无),真冰量驱动海平面
	var polarSnow := 0.0; var eqSnow := 0.0
	for j in Sim.NLat:
		var lat: float = abs(w.latof(j))
		for i in Sim.NLon:
			var s: float = w.Snow[j * Sim.NLon + i] + w.Glacier[j * Sim.NLon + i]
			if lat > 55.0: polarSnow += s
			elif lat < 30.0: eqSnow += s
	var seaM: float = abs(w.seaOffset * 2000.0)
	var g4ok: bool = polarSnow > 10.0 and polarSnow > eqSnow + 10.0 and w.iceVol > 0.0 and seaM < 300.0
	print("G4 雪冰(极区冰%.0f ≫ 赤道%.0f · 总冰量%.0f · 海平面%+.0fm): %s" % [polarSnow, eqSnow, w.iceVol, w.seaOffset * 2000.0, "✅" if g4ok else "❌"])
	quit(0 if (spatial and gw_ok and ro_ok and river_ok and g4ok) else 1)
