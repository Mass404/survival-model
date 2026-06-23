extends SceneTree
# 冰川性海平面 headless 验证:godot --headless --path godot --script res://slcheck.gd
# 注入 geo,跑数十年,看 海平面偏移 + 陆格数 随冰期一呼一吸(确定性、守恒)。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")

func _land(w) -> int:
	var c := 0
	for k in Sim.SZ:
		if w.Land[k] != 0: c += 1
	return c

func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var w = Sim.new()
	w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	var minL := 9999; var maxL := 0
	var minSea := 9.0; var maxSea := -9.0
	for step in 42 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0:
			w.stepGeo()
			var lc := _land(w)
			var slm: float = w.seaOffset * 2000.0
			minL = min(minL, lc); maxL = max(maxL, lc)
			minSea = min(minSea, slm); maxSea = max(maxSea, slm)
			if w.geoT % 3 == 0:
				print("  第%3d年  冰量 %5.2f  海平面 %+6.0fm  陆格 %d  ❄️冷 %.0f" % [w.geoT, w.iceVol, slm, lc, w.climCool])
		day += 1
	print("================ 冰川性海平面验证 ================")
	print("海平面摆幅: %.0fm ~ %.0fm (跨度 %.0fm)" % [minSea, maxSea, maxSea - minSea])
	print("陆格摆幅: %d ~ %d (跨度 %d 格)" % [minL, maxL, maxL - minL])
	var breathes: bool = (maxL - minL) >= 3 and (maxSea - minSea) >= 10.0
	print("海岸随冰期呼吸: %s" % ("✅" if breathes else "❌ 摆幅太小"))
	quit(0 if breathes else 1)
