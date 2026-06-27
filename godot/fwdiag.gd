extends SceneTree
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
func _mx(F) -> float:
	var m := 0.0
	for k in Sim.SZ: m = maxf(m, F[k])
	return m
func _sum(F) -> float:
	var s := 0.0
	for k in Sim.SZ: s += F[k]
	return s
func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	for step in 80 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0:
			w.stepGeo()
			if w.geoT % 4 == 0:
				print("Y%d sumH=%.1f maxH=%.2f sumC=%.2f maxC=%.3f sumN=%.0f" % [w.geoT, _sum(w.H), _mx(w.H), _sum(w.C), _mx(w.C), _sum(w.N)])
		day += 1
	quit(0)