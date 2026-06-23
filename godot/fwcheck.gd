extends SceneTree
# 食物网 headless 验证:godot --headless --path godot --script res://fwcheck.gd
# spinUp + 跑 N 年,看 N(生产者)/H(食草)/C(食肉)总量:验三级稳定共存 + N>H>C 能量金字塔。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")

func _sum(F) -> float:
	var s := 0.0
	for k in Sim.SZ: s += F[k]
	return s
func _cells(F) -> int:
	var c := 0
	for k in Sim.SZ:
		if F[k] > Sim.SEED: c += 1
	return c

func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var w = Sim.new()
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	var hSeen := false
	var cSeen := false
	for step in 80 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0:
			w.stepGeo()
			if _sum(w.H) > 0.5: hSeen = true
			if _sum(w.C) > 0.5: cSeen = true
			if w.geoT % 20 == 0:
				print("  第%3d年  N %8.1f (%d格) | H %7.2f (%d格) | C %7.2f (%d格)" % [
					w.geoT, _sum(w.N), _cells(w.N), _sum(w.H), _cells(w.H), _sum(w.C), _cells(w.C)])
		day += 1
	var sn := _sum(w.N); var sh := _sum(w.H); var sc := _sum(w.C)
	print("================ 食物网验证 ================")
	print("末态总量:  生产者 N %.1f  食草 H %.1f  食肉 C %.1f" % [sn, sh, sc])
	var coex: bool = sh > 0.5 and sc > 0.5
	var pyr: bool = sn > sh and sh > sc
	print("三级共存(末态 H>0 且 C>0): %s" % ("✅" if coex else "❌ H=%.2f C=%.2f" % [sh, sc]))
	print("能量金字塔 N>H>C: %s (%.1f > %.1f > %.1f)" % [("✅" if pyr else "❌"), sn, sh, sc])
	print("曾点燃:  食草 %s  食肉 %s" % [("✅" if hSeen else "❌"), ("✅" if cSeen else "❌")])
	quit(0 if (coex and pyr) else 1)
