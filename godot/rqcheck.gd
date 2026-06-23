extends SceneTree
# 有性生殖+寄生(红皇后)headless 验证:godot --headless --path godot --script res://rqcheck.gd
# 对照实验:寄生开 vs 寄生关,跑同一颗星球。验:① 载量有界、宿主存活 ② 红皇后——
# 寄生世界的平均 rSex 明显高于无寄生世界(寄生压选择有性生殖)。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")

func _run(g, paraOn: bool) -> Array:
	var w = Sim.new()
	w.geo = g
	w.parasitesOn = paraOn
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	for step in 70 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	var sumN := 0.0; var maxPar := 0.0; var sx := 0.0; var nlife := 0
	for k in Sim.SZ:
		sumN += w.N[k]; maxPar = max(maxPar, w.Par[k])
		if w.N[k] > Sim.SEED: sx += w.rSex[k]; nlife += 1
	return [sumN, maxPar, (sx / nlife if nlife > 0 else 0.0)]

func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var on = _run(g, true)
	var off = _run(g, false)
	print("================ 红皇后对照验证 ================")
	print("寄生开:  生产者 N %.1f  最大载量 %.2f  平均 rSex %.3f" % [on[0], on[1], on[2]])
	print("寄生关:  生产者 N %.1f  最大载量 %.2f  平均 rSex %.3f" % [off[0], off[1], off[2]])
	var bounded: bool = on[1] <= Sim.PAR_MAX + 1e-6 and on[1] > 0.1
	var alive: bool = on[0] > 50.0
	var redqueen: bool = on[2] > off[2] + 0.05
	print("载量有界(≤%.0f): %s" % [Sim.PAR_MAX, "✅" if bounded else "❌"])
	print("宿主存活: %s" % ("✅" if alive else "❌"))
	print("红皇后(寄生→更有性): %s (Δ=%.3f)" % [("✅" if redqueen else "❌"), on[2] - off[2]])
	quit(0 if (bounded and alive and redqueen) else 1)
