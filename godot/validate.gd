extends SceneTree
# headless 数值验证:godot --headless --path godot --script res://validate.gd
# spinUp + 跑 N 个地质年,打印关键指标,跟 evolve.html 的行为对一遍。
const Sim = preload("res://sim/World.gd")

func _initialize() -> void:
	var w = Sim.new()
	var t0 := Time.get_ticks_msec()
	w.spinUp()
	var years := 80
	var day := 0
	var first_life := -1
	var peak_species := 0
	for step in years * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0:
			w.stepGeo()
			var alive = w.phylo.filter(func(p): return p["deathY"] < 0).size()
			if alive > peak_species: peak_species = alive
			if first_life < 0 and _alive_cells(w) > 0: first_life = w.geoT
			if w.geoT % 20 == 0: print("  …第 %d 年:占据格 %d,现存种 %d,大灭绝 %d 次" % [w.geoT, _alive_cells(w), alive, w.massExt.size()])
		day += 1
	var dt := Time.get_ticks_msec() - t0

	var cells := _alive_cells(w)
	var bio := 0.0
	for k in Sim.SZ: bio += w.N[k]
	var alive_now = w.phylo.filter(func(p): return p["deathY"] < 0).size()

	print("================ Evolve 内核 headless 验证 ================")
	print("跑了 %d 地质年,用时 %d ms" % [w.geoT, dt])
	print("生命首次点燃 @ 第 %d 年" % first_life)
	print("现存被占据格: %d / %d" % [cells, Sim.NLat * Sim.NLon])
	print("全球总生物量: %.0f" % bio)
	print("现存物种数: %d (历史峰值 %d, id 已发到 %d)" % [alive_now, peak_species, w.nextSp - 1])
	print("大灭绝事件: %d 次" % w.massExt.size())
	for e in w.massExt:
		print("   · %s @ %d 年 · 损 %d 种" % [e["cause"], e["ky"], e["lost"]])
	print("全球 CO₂: %.2f (基线 %.1f)" % [w.globalCO2, Sim.CO2ref])
	print("冰期致冷量 climCool: %.1f" % w.climCool)
	print("主导体制: %s" % _dominant_morph(w))
	var ok: bool = first_life > 0 and cells > 0 and alive_now > 0 and bio > 0.0 and w.massExt.size() > 0
	print("---------------------------------------------------------")
	print("健全性: %s" % ("✅ 通过(生命点燃·存续·成种·有大灭绝)" if ok else "❌ 异常,需排查"))
	quit(0 if ok else 1)

func _alive_cells(w) -> int:
	var c := 0
	for k in Sim.SZ:
		if w.N[k] > Sim.SEED: c += 1
	return c

func _dominant_morph(w) -> String:
	var bp := {}
	for j in Sim.NLat:
		for i in Sim.NLon:
			if w.N[j * Sim.NLon + i] > Sim.SEED:
				var k = w.bodyPlan(j, i)
				bp[k] = bp.get(k, 0.0) + w.N[j * Sim.NLon + i]
	var best := ""
	var bv := -1.0
	for k in bp:
		if bp[k] > bv: bv = bp[k]; best = k
	return best if best != "" else "尚无"
