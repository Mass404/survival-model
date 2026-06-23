extends SceneTree
# 真大陆 + 生命联检:godot --headless --path godot --script res://geocheck.gd
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")

func _initialize() -> void:
	var g = GeoS.new()
	var t0 := Time.get_ticks_msec()
	g.generate()
	# 面积加权陆比
	var lw := 0.0
	var tw := 0.0
	for gy in GeoS.ROWS:
		var lat := 90.0 - (gy + 0.5) * 180.0 / GeoS.ROWS
		var w := cos(lat * PI / 180.0)
		for gx in GeoS.COLS:
			tw += w
			if g.elev[gy * GeoS.COLS + gx] > g.sealevel: lw += w
	print("海平面 %.3f (emin %.2f / emax %.2f),面积加权陆比 %.1f%%,生成用时 %d ms" % [g.sealevel, g.emin, g.emax, 100.0 * lw / tw, Time.get_ticks_msec() - t0])

	var mask = g.coarse_land(Sim.NLat, Sim.NLon)
	print("—— 粗网格海陆(18×24,北在上,# 陆 · 海)——")
	for j in range(Sim.NLat - 1, -1, -1):
		var line := ""
		for i in Sim.NLon: line += "#" if mask[j][i] else "·"
		print(line)
	var lc := 0
	for j in Sim.NLat:
		for i in Sim.NLon:
			if mask[j][i]: lc += 1
	print("粗网格陆格 %d / %d (%.0f%%)" % [lc, Sim.NLat * Sim.NLon, 100.0 * lc / (Sim.NLat * Sim.NLon)])

	# 生命能不能在这套真地理上点燃 + 成种
	var w := Sim.new()
	w.land_mask = mask
	w.spinUp()
	var day := 0
	for step in 30 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	var cells := 0
	var bio := 0.0
	for j in Sim.NLat:
		for i in Sim.NLon:
			if w.N[j][i] > Sim.SEED: cells += 1
			bio += w.N[j][i]
	var alive = w.phylo.filter(func(p): return p["deathY"] < 0).size()
	print("跑 30 年后:占据格 %d/%d,生物量 %.0f,现存种 %d,大灭绝 %d 次" % [cells, Sim.NLat * Sim.NLon, bio, alive, w.massExt.size()])
	var ok: bool = lw / tw > 0.15 and lw / tw < 0.5 and cells > 0 and alive > 0
	print("健全性: %s" % ("✅ 真大陆成形 + 生命存续成种" if ok else "❌ 需排查"))
	quit(0 if ok else 1)
