extends SceneTree
# 逐格地质 headless 验证:godot --headless --path godot --script res://tectcheck.gd
# 跑 80 地质年,验:① 火山热点高程被抬升 ② 全球陆地高程有界(侵蚀不把世界铲平、火山不爆表)
# ③ 仍有相当陆地(地质+海平面重塑海岸但没崩)。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")

func _hotsum(g) -> float:
	if g.hotspots.is_empty(): g._init_tect()
	var s := 0.0
	for h in g.hotspots: s += g.elev[h]
	return s
func _meanland(g) -> float:
	var s := 0.0; var n := 0
	for idx in GeoS.COLS * GeoS.ROWS:
		if g.elev[idx] > g.SEA: s += g.elev[idx] - g.SEA; n += 1
	return s / n if n > 0 else 0.0
func _landcells(w) -> int:
	var c := 0
	for k in Sim.SZ:
		if w.Land[k] != 0: c += 1
	return c

func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var hot0 := _hotsum(g); var ml0 := _meanland(g)
	var w = Sim.new()
	w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var l0 := _landcells(w)
	var day := 0
	for step in 80 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0:
			w.stepGeo()
			if w.geoT % 20 == 0:
				print("  第%3d年  热点高程Σ %.3f  陆均relief %.4f  陆格 %d  岩浆 %.1f" % [w.geoT, _hotsum(g), _meanland(g), _landcells(w), g.magmaP])
		day += 1
	var hot1 := _hotsum(g); var ml1 := _meanland(g)
	print("================ 逐格地质验证 ================")
	print("火山热点高程Σ:  初 %.3f → 末 %.3f (%+.3f)" % [hot0, hot1, hot1 - hot0])
	print("全球陆均 relief:  初 %.4f → 末 %.4f" % [ml0, ml1])
	print("陆格:  初 %d → 末 %d" % [l0, _landcells(w)])
	var built: bool = hot1 > hot0 + 0.01
	var bounded: bool = ml1 > 0.3 * ml0 and ml1 < 3.0 * ml0
	var hasland: bool = _landcells(w) > 50
	print("火山抬升热点: %s" % ("✅" if built else "❌"))
	print("地形有界(没铲平/没爆表): %s" % ("✅" if bounded else "❌"))
	print("仍有相当陆地: %s" % ("✅" if hasland else "❌"))
	quit(0 if (built and bounded and hasland) else 1)
